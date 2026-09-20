
Parent: [[Raft MOC]]

Related: [[Raft RPC and Term Handling]], [[MIT 6.824 Raft Lab 2A Implementation Map]]

## Why one peer needs a mutex

Peers do not share state with each other, but many goroutines inside one peer share the same `Raft` object:

- Election ticker
- `RequestVote` handlers
- `AppendEntries` handlers
- Outbound RPC reply goroutines
- Heartbeat logic
- `GetState()` calls

All may access:

```text
currentTerm
votedFor
role
election timing state
per-election votes
```

The mutex is per peer. It protects local invariants; it does not lock the cluster.

## Treat transitions as atomic local transactions

Starting an election must not interleave halfway with a higher-term heartbeat. Under `rf.mu`, update the related state together:

```text
role = Candidate
currentTerm++
votedFor = self
reset election timing
capture election term and RPC arguments
```

Without a lock, an incoming handler could update the term and role between these writes, leaving an impossible mixture of old and new state.

## Never hold the mutex across an RPC

Use three phases:

```text
1. Lock: update state and snapshot RPC arguments
2. Unlock: perform the potentially slow network call
3. Lock: validate and process the reply
```

A network call can be delayed or fail. Holding `rf.mu` while waiting would prevent the peer from processing incoming heartbeats, vote requests, higher terms, or other replies.

## Send RPCs to peers concurrently

A disconnected first follower must not delay heartbeats to every later follower in a sequential loop. Send independent RPCs concurrently so one slow peer does not cause healthy followers to time out.

## One reply object per RPC goroutine

This is unsafe:

```go
reply := AppendEntriesReply{}
for each peer {
    go send(peer, &reply)
}
```

All goroutines decode into the same local object, producing a data race and overwriting responses.

Each goroutine should own its reply:

```go
go func(peer int, args AppendEntriesArgs) {
    var reply AppendEntriesReply
    // send without lock, then lock and process
}(peer, args)
```

Passing `peer` as an argument also avoids loop-variable capture mistakes.

## Validate asynchronous replies

When a vote reply returns:

```text
process a higher reply term first
then require role == Candidate
then require currentTerm == electionTerm
```

When a heartbeat reply returns:

```text
process a higher reply term first
then require role == Leader
then require currentTerm == leaderTerm/sent term
```

An obsolete goroutine must not alter a later campaign or leadership period.

## Avoid immortal old heartbeat loops

A loop created for term 1 must not resume merely because the peer becomes leader again in term 3. Bind a per-leadership loop to its captured term and exit permanently when the role or term changes.

Alternatively, maintain one long-lived ticker that checks the current role and term each round.

## `GetState()`

`GetState()` reads `currentTerm` and leadership status as a pair. Hold the mutex briefly so it cannot return a term from one state and a role from another.

```go
rf.mu.Lock()
term := rf.currentTerm
isLeader := rf.role == Leader
rf.mu.Unlock()
```

## Shutdown

The tester calls `Kill()` to permanently stop a peer. Long-running ticker and heartbeat loops should check `rf.killed()` and exit, avoiding leaked goroutines and misleading output.

## Race testing

Run:

```bash
go test -run 2A -race
```

A passing functional test without `-race` is not sufficient evidence that local state access is safe.

