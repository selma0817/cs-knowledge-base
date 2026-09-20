# Raft Persistent and Volatile State

Parent: [[Raft MOC]]

Related: [[MIT 6.824 Raft Lab 2C Persistence Map]], [[Raft Commitment and Application]], [[Raft System Model Terms and Roles]]

## Classification

| State | Persistent? | Reason |
|---|---:|---|
| `currentTerm` | Yes | A server's logical clock must never move backward |
| `votedFor` | Yes | Prevent granting two votes in one term |
| `log` | Yes | Accepted entries must survive a crash |
| Role | No | Restart conservatively as follower |
| `commitIndex` | No | Local knowledge of commitment can be relearned |
| `lastApplied` | No, not independently | Must correspond atomically to application state |
| `nextIndex[]` | No | New leader can restart its sending estimates |
| `matchIndex[]` | No | New leader can verify follower progress again |
| Election deadline | No | Choose a fresh randomized deadline after restart |

## Why `currentTerm` and `votedFor` belong together

`votedFor` means:

```text
the server I voted for in currentTerm
```

Suppose S0 enters term 5, votes for S1, replies, crashes, and forgets `currentTerm`. After restarting at term 0, it receives a term-5 request from S2. It may treat term 5 as new, clear its old vote, and vote for S2.

Persisting only the candidate identity would not preserve which term that vote belongs to. The pair must recover as:

```text
currentTerm = 5
votedFor = S1
```

Persisting `currentTerm` also ensures delayed lower-term leaders remain obsolete after a restart.

## Why the log persists

The log is durable accepted history, not necessarily committed history.

- The leader persists a `Start()` entry before returning or replicating it.
- A follower persists changed entries before replying success.
- An uncommitted persisted suffix may still be overwritten by a later legitimate leader.
- A committed entry must remain available so election restriction and Log Matching preserve Leader Completeness.

Persistence means “survives this server's crash,” not “can never be replaced.”

## Why role is volatile

A server may have been leader before crashing, but another leader may have been elected while it was offline. Restarting as leader would resurrect stale authority.

The safe default is:

```text
role = follower
```

The server then receives a valid leader heartbeat or starts a new election after its fresh deadline.

## Why `commitIndex` can be forgotten

Commitment is a cluster-level fact. `commitIndex` is one server's knowledge of that fact.

Before crash:

```text
log         = [dummy, A, B, C]
commitIndex = 3
```

After restart:

```text
log         = [dummy, A, B, C]
commitIndex = 0
```

C did not become globally uncommitted. Durable majority logs and election restriction still prevent a future leader from losing it. A current leader can send `LeaderCommit=3`, allowing the restarted follower to relearn the index.

After a wider restart, a new leader can commit a new current-term entry; that action reconfirms and commits the whole preceding prefix.

Persisting `commitIndex` can be a recovery optimization in another design, but Raft safety does not require it.

## Why `lastApplied` is not persisted alone

`lastApplied` describes local state-machine execution, not consensus.

Persist progress first:

```text
persist lastApplied=3
crash before executing command 3
restart and incorrectly skip command 3
```

Execute first:

```text
execute command 3
crash before persisting lastApplied=3
restart and execute command 3 again
```

Correct durable recovery must atomically associate the application state with the index it represents. A snapshot provides:

```text
state-machine snapshot through index 100
lastIncludedIndex = 100
```

The server can then resume at 101. Application idempotency may help with duplicate requests, but it is not a substitute for coordinating state and progress.

## Why `nextIndex` and `matchIndex` are volatile

They are leader-local beliefs about followers:

```text
nextIndex = sending estimate
matchIndex = progress verified during this leadership period
```

A new leader initializes them conservatively and relearns them using `AppendEntries` replies. Safety depends on verification, not on preserving a previous leader's cached beliefs.

## Why timing state is volatile

An absolute election deadline from before a crash has little meaning after an unknown downtime. On restart:

```text
electionDeadline = now + fresh randomized timeout
```

This affects election liveness and collision probability, not log safety.

## Recovery mental model

```text
disk restores:
    currentTerm
    votedFor
    log

runtime reconstructs:
    follower role
    election deadline
    replication estimates
    commit knowledge
    application progress or snapshot position
    goroutines and channels
```

## Interview questions

- What failure occurs if `currentTerm` is forgotten but `votedFor` is remembered?
- Does resetting `commitIndex` make a committed entry uncommitted?
- Why is persisting `lastApplied` by itself unsafe?
- Could an implementation persist extra fields? Why are they not required by Raft safety?
- What is the difference between mutex protection and persistent storage?

