# MIT 6.824 Raft Lab 2C Persistence Map

Parent: [[Raft MOC]]

Related: [[Raft Persistent and Volatile State]], [[Raft Log Replication and AppendEntries]], [[Raft RPC and Term Handling]], [[Raft nextIndex matchIndex and Conflict Repair]]

## Goal

Lab 2C preserves Raft safety when a server crashes, loses memory, and restarts.

The required persistent state from Raft Figure 2 is:

```text
currentTerm
votedFor
log
```

The ordering principle is:

```text
modify safety-critical persistent state
    -> persist the complete new state
    -> expose the mutation through a reply, outbound RPC, or return value
```

The mutex protects against concurrent goroutines. Persistence protects against crashes. Neither replaces the other.

## `persist()`

The caller holds `rf.mu`, allowing the three fields to be encoded as one consistent snapshot:

```go
currentTerm
votedFor
log
```

They are encoded in a fixed order and passed to `SaveRaftState()`.

Persisting all three together avoids incompatible recovered combinations such as a new term with a vote that belonged to an older term.

## `readPersist()`

Recovery decodes in the exact same order into temporary variables:

```text
decode currentTerm
decode votedFor
decode log
if every decode succeeds:
    install all three fields
```

Decoding into temporaries prevents a partially corrupted byte stream from installing only some fields.

When no saved state exists, retain initialized defaults, including the dummy log entry.

## Startup ordering

`Make()` initializes defaults and then restores persisted state before starting:

```text
ticker
applier
replication workers
```

Otherwise, a background goroutine could act using term 0 or an empty log before recovery finishes.

The restarted role is always follower. Leadership is not resumed from disk.

## Every persistence point

### Start an election

```text
currentTerm++
votedFor = self
persist
send RequestVote RPCs
```

The server must not send vote requests and then crash back into an older term or forget its self-vote.

### Observe a higher term

```text
currentTerm = receivedTerm
votedFor = none
persist
become follower
```

Persist even if the ordinary RPC request will later be rejected for another reason, such as a stale candidate log.

### Grant a vote

```text
votedFor = candidate
persist
reply VoteGranted=true
```

Without this ordering, the server could grant a vote, crash, forget, and grant another candidate a vote in the same term.

### Leader accepts a client command

```text
append current-term entry
persist
return from Start or trigger replication
```

The leader's own entry must survive once other servers may observe or replicate it.

### Follower changes its log

```text
truncate conflicting suffix and/or append entries
persist
reply Success=true
```

The leader may count the success toward a majority, so the follower cannot acknowledge data that a crash would erase.

Repeated matching `AppendEntries` requests do not require another disk write when no persistent field changes.

## Persistent mutation versus RPC success

Persistence is triggered by a durable field mutation, not by whether the RPC's ordinary operation succeeds.

Example:

```text
receiver term = 4
RequestVote term = 5
candidate log is stale
```

The receiver must save:

```text
currentTerm = 5
votedFor = none
unchanged log
```

before rejecting the candidate. Observing the higher term is itself a durable transition.

## What is intentionally not persisted

```text
role
commitIndex
lastApplied
nextIndex
matchIndex
electionDeadline
notification channels and goroutine state
```

These values are safely reset, relearned, or coordinated with the application layer. See [[Raft Persistent and Volatile State]].

## Conflict repair and 2C liveness

Persistence tests also produce long divergent logs and unreliable delivery. A correct encoder can still fail if repair takes too long.

Accelerated backtracking adds:

```text
ConflictTerm
ConflictIndex
```

This is primarily a liveness optimization: the leader skips a whole conflicting range rather than decrementing `nextIndex` once per successful RPC round.

The implementation also avoids a nonstandard recent-quorum step-down that could interrupt legitimate log repair when live followers were responding with consistency rejections.

## Testing checklist

```bash
go test -run 2A -race
go test -run 2B -race
go test -run 2C -race
go test -run 2C -race -count=5
```

When recovery fails, ask:

- Did every change to `currentTerm`, `votedFor`, or `log` persist?
- Did persistence occur before the RPC reply or replication trigger?
- Did `readPersist()` run before background goroutines?
- Did encode and decode use the same field order?
- Did a higher term persist even when the request was rejected?
- Did the follower persist a changed log before returning success?
- Is the failure actually liveness under divergent logs rather than serialization?

## Readiness criterion

A complete explanation should trace both:

```text
vote -> persist -> reply -> crash -> restart without double voting
```

and:

```text
append -> persist -> replicate -> majority -> crash -> future leader retains committed prefix
```

