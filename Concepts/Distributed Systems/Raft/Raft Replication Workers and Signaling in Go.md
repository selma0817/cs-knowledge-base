# Raft Replication Workers and Signaling in Go

Parent: [[Raft MOC]]

Related: [[Raft Concurrency and Locking in Go]], [[Raft nextIndex matchIndex and Conflict Repair]], [[Raft Commitment and Application]], [[MIT 6.824 Raft Lab 2B Implementation Map]], [[Go Scheduler]], [[Goroutines and Channels]]

## Long-running goroutines created by `Make()`

One Raft peer starts:

```text
one ticker goroutine
one applier goroutine
one replicationWorker(peer) for every remote peer
```

Election RPCs and bounded AppendEntries attempts may also create shorter-lived goroutines.

The peer is one local concurrent program. `rf.mu` protects shared Raft state inside it; RPCs connect it to independent peer programs.

## Notification path from `Start()`

After appending a command, `Start()` calls:

```text
signalHeartbeat
    -> send empty token to heartbeatNow
```

The ticker receives that token:

```text
heartbeatNow
    -> broadcastHeartbeats
    -> send a token to each replicateCh[peer]
```

Each follower has its own worker:

```go
for {
    select {
    case <-rf.replicateCh[peer]:
        rf.replicateToPeer(peer)
    case <-rf.done:
        return
    }
}
```

This architecture serializes Raft-state processing for one follower while allowing different followers to progress independently.

## A blocked `select` is not busy-waiting

The worker's `select` has no `default` case. If neither channel is ready, the Go runtime registers the goroutine as waiting and parks it. The OS thread can run other goroutines.

```text
check channels
    -> neither ready
    -> park goroutine
    -> channel becomes ready
    -> mark goroutine runnable
    -> scheduler resumes it
```

A busy-waiting version would include a `default` inside a tight loop:

```go
for {
    select {
    case <-work:
        doWork()
    default:
        // immediately loops again and consumes CPU
    }
}
```

## What happens after `replicateToPeer()` returns

Returning does not automatically enter the `done` case.

```text
replicateToPeer returns
    -> current select case finishes
    -> outer for-loop repeats
    -> execute select again
```

Then:

- If a work token is already buffered, the worker immediately handles it.
- If `done` is closed, the worker exits.
- If neither is ready, the worker parks again.

## Buffered channels as coalesced notifications

`heartbeatNow` and each `replicateCh[peer]` have capacity one. Sends use:

```go
select {
case ch <- struct{}{}:
default:
}
```

This means “ensure at least one notification is pending,” not “queue every event.”

Coalescing is safe because the token contains no command. When the worker wakes, it reads the current `nextIndex` and current log and sends all missing entries.

If three commands arrive while one token is pending, the next replication attempt can carry all three.

## Retry behavior

`replicateToPeer()` itself contains a loop.

### Prefix mismatch

The follower returned valid conflict information:

```text
adjust nextIndex under the lock
unlock
reach bottom of replication loop
immediately construct and send another AppendEntries
```

There is deliberately no `return` after the mismatch update.

### Success

The leader updates `matchIndex`, `nextIndex`, and possibly `commitIndex`, then returns. The worker goes back to its blocking `select`.

### Network failure or local RPC timeout

The code returns immediately from `replicateToPeer()`. The worker waits for a future periodic heartbeat or another replication notification.

This avoids immediate retry spinning while a follower is disconnected.

### Higher term or stale leadership

If the reply shows a higher term, become follower and return. If the sender is no longer leader in the captured term, ignore the obsolete reply and return.

## Lock-snapshot-RPC-validate pattern

One attempt follows:

```text
lock
verify still leader
snapshot term, prefix, entries, and LeaderCommit
unlock

perform RPC

lock
process higher term first
verify still leader in captured term
update replication state only if reply is still relevant
unlock
```

Never hold `rf.mu` across the network call. A delayed follower must not block the peer from processing a newer term or incoming leader heartbeat.

## Shutdown

`Kill()`:

```text
atomically marks the peer dead
closes done
broadcasts applyCond
```

Closing `done` makes every receive from it ready. Workers and timers can exit, and the broadcast wakes an applier that might otherwise remain asleep forever.

## Interview questions

- Why use one replication worker per follower instead of one global sequential loop?
- Why do notification channels have capacity one?
- Why does coalescing notifications not lose log entries?
- Which failure retries immediately, and which waits for the next heartbeat?
- What makes a blocked `select` different from busy-waiting?
- Why must a reply be revalidated after the RPC returns?

