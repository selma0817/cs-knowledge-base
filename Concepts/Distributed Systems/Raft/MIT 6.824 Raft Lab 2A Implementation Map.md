
Parent: [[Raft MOC]]

Related: [[Raft Concurrency and Locking in Go]], [[Raft RPC and Term Handling]], [[Raft Heartbeats and Election Timers]]

## Goal

Lab 2A implements:

- Leader election
- Term and role transitions
- `RequestVote`
- Empty `AppendEntries` heartbeats
- Election and heartbeat timing
- `GetState()`

It does not yet implement normal log replication, commitment, or application.

## Suggested local state

The exact scaffold may already provide some fields.

```text
Identity and communication
- peers []*labrpc.ClientEnd
- me int
- persister *Persister

Concurrency and lifecycle
- mu sync.Mutex
- dead int32

Election state
- currentTerm int
- votedFor int           // use a sentinel such as -1 for none
- role Role

Timing state
- electionDeadline time.Time
  OR lastElectionReset + electionTimeout

Future log state
- log []LogEntry
```

Do not store a separate server count; use `len(rf.peers)`. Compute a majority as `len(rf.peers)/2 + 1`.

## RPC structures

### `RequestVoteArgs`

```text
Term
CandidateId
LastLogIndex
LastLogTerm
```

### `RequestVoteReply`

```text
Term
VoteGranted
```

### `AppendEntriesArgs`

```text
Term
LeaderId
PrevLogIndex
PrevLogTerm
Entries
LeaderCommit
```

### `AppendEntriesReply`

```text
Term
Success
```

Every field transmitted through Go RPC must be exported with an uppercase first letter.

## `Make()` responsibilities

Initialize one peer:

```text
currentTerm = 0
role = Follower
votedFor = none
first randomized election deadline
placeholder/initial log representation
```

Start the background ticker before returning. Do not send heartbeats until this peer has actually won an election. Later persistence work will also restore saved state here.

## Ticker responsibilities

One possible architecture:

```text
loop until killed
    sleep for a short polling interval
    lock
    if follower/candidate deadline passed:
        atomically prepare a new election
    if leader heartbeat round is due:
        snapshot leader term and heartbeat arguments
    unlock
    launch prepared RPCs concurrently
```

Another architecture uses a ticker for elections and a term-bound loop for heartbeats. Either can work if old loops exit and timing remains controlled.

## Beginning an election

Under the lock:

```text
become Candidate
increment currentTerm
vote for self
create/reset a fresh randomized election deadline
record electionTerm
initialize this campaign's vote count to 1
construct a snapshot of RequestVoteArgs
```

After unlocking, send `RequestVote` to all other peers concurrently.

Each reply goroutine:

1. Owns its reply object.
2. Reacquires `rf.mu` after the RPC returns.
3. Processes a higher term first.
4. Counts the vote only if still candidate in `electionTerm`.
5. Performs the majority-to-leader transition once.

## Becoming leader

When the current campaign reaches a majority:

```text
role = Leader
```

Snapshot the term and heartbeat data, unlock, and immediately send one empty `AppendEntries` round. Continue periodic rounds at no more than 10 per second.

## `RequestVote` handler outline

Under the lock:

1. Set the reply term appropriately.
2. Reject a stale candidate term.
3. On a higher term, update local term, become follower, and clear `votedFor`.
4. Check whether this peer may vote in the term.
5. Check log freshness; this is trivial with empty 2A logs but required later.
6. If granting, record `votedFor` and reset election timing.
7. Return the receiver's current term in the reply.

## `AppendEntries` handler outline

Under the lock:

1. Reject a stale leader term and return the current term.
2. On a higher term, update the term and clear the old vote.
3. For a current/new-term leader, become/remain follower.
4. Reset election timing for valid leader contact.
5. In 2A, accept the empty heartbeat when the term is valid.
6. Return the current term.

Lab 2B will add log consistency and conflict handling.

## `GetState()`

Lock briefly and return a consistent pair:

```text
currentTerm
role == Leader
```

## Lock boundary checklist

Hold `rf.mu` while:

- Reading or changing `currentTerm`, `votedFor`, or role
- Reading or resetting election timing
- Counting votes
- Deciding whether a reply still belongs to the current term and role
- Reading the pair returned by `GetState()`

Do not hold `rf.mu` while:

- Waiting for `ClientEnd.Call`
- Sleeping
- Performing a full concurrent heartbeat broadcast

## Timing checklist

- Periodic heartbeat interval is at least about 100 ms.
- Election timeout is randomized and comfortably longer than the heartbeat interval.
- A fresh timeout is selected for each new campaign/waiting period.
- A new leader sends an immediate heartbeat.
- Several failed election rounds can still fit within five seconds.

## Testing sequence

Start with:

```bash
go test -run 2A -race
```

Then repeat because timing failures are probabilistic:

```bash
go test -run 2A -race -count=20
```

Useful questions when a test fails:

- Did a stale reply change a newer election?
- Did a rejected RPC incorrectly reset a timer?
- Did an old heartbeat goroutine survive a term change?
- Was `rf.mu` held during an RPC?
- Did concurrent RPCs share a reply object?
- Did a candidate count its own vote?
- Did the leader send its first heartbeat immediately?
- Did a higher term in a request **or reply** cause a transition to follower?
- Are all RPC-transmitted fields exported?
- Do all background loops stop after `Kill()`?

## Readiness criterion

Before expanding to Lab 2B, Lab 2A should repeatedly maintain one leader among a connected majority, replace a failed leader within the time bound, reject stale terms, and pass the Go race detector.

