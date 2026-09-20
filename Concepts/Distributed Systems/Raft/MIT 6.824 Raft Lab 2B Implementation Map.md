# MIT 6.824 Raft Lab 2B Implementation Map

Parent: [[Raft MOC]]

Related: [[Raft Log Replication and AppendEntries]], [[Raft nextIndex matchIndex and Conflict Repair]], [[Raft Commitment and Application]], [[Raft Replication Workers and Signaling in Go]]

## Goal

Lab 2B extends leader election into replicated-log consensus:

```text
Start(command)
    -> append locally
    -> replicate through AppendEntries
    -> repair inconsistent followers
    -> detect majority replication
    -> commit
    -> apply in index order
```

Passing election tests is not enough. A 2B implementation must preserve safety while RPCs are delayed, dropped, duplicated, or returned after the sender has changed role or term.

## State added or activated in 2B

| Field | Scope | Meaning |
|---|---|---|
| `log []LogEntry` | every server | Dummy entry at index 0 followed by replicated commands |
| `commitIndex` | every server | Highest index locally known to be committed |
| `lastApplied` | every server | Highest index delivered to the state machine |
| `nextIndex[peer]` | leader | Next index the leader will try to send to that follower |
| `matchIndex[peer]` | leader | Highest index verified to exist on that follower |
| `applyCh` | every server | Output channel to the service/tester |
| `applyCond` | every server | Wakes the applier when committed work appears |
| `replicateCh[peer]` | leader architecture | Notification channel for one follower's replication worker |

The dummy entry makes the first real command index 1 and lets `PrevLogIndex=0` always reference a valid baseline.

## `Start(command)`

`Start()` is a non-blocking proposal API, not a commitment API.

Under `rf.mu`:

```text
if not leader:
    return -1, currentTerm, false

append {Term: currentTerm, Command: command}
persist the changed log
index = last log index
matchIndex[self] = index
nextIndex[self] = index + 1
try to advance commitIndex
```

After unlocking:

```text
signal replication
return index, term, true
```

The returned index is where the entry will appear if it commits. Leadership can be lost before replication, so `true` does not mean committed.

## Replication architecture

The implementation uses one long-running worker per remote peer:

```text
signalHeartbeat
    -> heartbeatNow
    -> ticker
    -> broadcastHeartbeats
    -> replicateCh[peer]
    -> replicationWorker(peer)
    -> replicateToPeer(peer)
```

The notification is not tied to one entry. The worker reads current state and sends the entire missing suffix:

```go
Entries: append([]LogEntry(nil), rf.log[nextIndex:]...)
```

This allows multiple notifications to coalesce without losing commands.

## Constructing `AppendEntries`

Under the lock, the leader snapshots:

```text
Term
LeaderId
PrevLogIndex = nextIndex[peer] - 1
PrevLogTerm  = log[PrevLogIndex].Term
Entries      = copy(log[nextIndex[peer]:])
LeaderCommit = commitIndex
```

It copies the entries because the leader's slice may change after unlocking. It then releases `rf.mu` before the RPC.

## Follower `AppendEntries` decision

Under the lock:

1. Reject a stale term.
2. On a current or newer term, become/remain follower and reset the election deadline.
3. Reject if `PrevLogIndex` is beyond the follower log.
4. Reject if the entry at `PrevLogIndex` has a different term.
5. Once the prefix matches, retain matching entries.
6. At the first conflicting entry, truncate the local suffix and append the leader suffix.
7. Persist if the log changed.
8. Advance the follower's commit index to at most the matched-through index.
9. Return success.

A consistency rejection must not modify the log.

## Leader reply processing

After the RPC returns, reacquire `rf.mu` and process in this order:

```text
if reply has higher term:
    become follower and stop

if no longer leader or currentTerm != sent term:
    ignore stale reply

if success:
    advance matchIndex and nextIndex monotonically
    try to advance commitIndex
    stop this replication attempt

if prefix mismatch:
    move nextIndex backward using conflict hints
    immediately retry inside the same loop
```

## Commitment

The leader searches backward for the highest index `N` satisfying:

```text
N > commitIndex
log[N].Term == currentTerm
a majority has matchIndex[peer] >= N
```

It then sets `commitIndex=N`. Every preceding entry becomes committed as part of the prefix, including older-term entries.

The current-term restriction is required by [[Raft Commitment and Application]].

## Application

The applier is independent of replication:

```text
wait while commitIndex <= lastApplied
index = lastApplied + 1
copy log[index]
unlock
send ApplyMsg on applyCh
relock and advance lastApplied
repeat
```

One condition-variable signal is enough when several entries become committed because the durable predicate `commitIndex > lastApplied` remains true until the backlog is drained.

## Concurrency rules

- Hold `rf.mu` while reading or modifying Raft state.
- Do not hold it during RPC calls.
- Do not hold it while a potentially blocking `applyCh` send waits.
- Copy the entry slice placed in outbound RPC arguments.
- Validate term and role again after every asynchronous reply.
- Keep one reply object per RPC attempt.
- Never decrease a verified `matchIndex` because of an older reply.

## Testing and debugging questions

Run functional and race tests repeatedly:

```bash
go test -run 2B -race
go test -run 2B -race -count=10
```

When replication stalls, ask:

- Did `Start()` return before replication as intended?
- Does the leader send `log[nextIndex:]`, not just one arbitrary entry?
- Is `PrevLogTerm` read from the leader's own `PrevLogIndex`?
- Does a mismatch retry make backward progress?
- Can a network failure spin in a tight retry loop?
- Are `matchIndex` and `nextIndex` updated from the actual RPC arguments?
- Does commitment count the leader itself?
- Does direct commitment require the entry's term to equal `currentTerm`?
- Does a commit advance wake the local applier and notify followers through `LeaderCommit`?
- Are entries delivered exactly in increasing index order during one execution?

## Readiness criterion

A sound 2B implementation can explain and trace:

```text
local append -> follower persistence -> majority -> commit -> application
```

It can also repair arbitrarily divergent uncommitted suffixes without overwriting a committed prefix.

