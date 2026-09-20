# Raft Safety Properties and Interview Review

Parent: [[Raft MOC]]

Related: [[MIT 6.824 Raft Lab 2A Implementation Map]], [[MIT 6.824 Raft Lab 2B Implementation Map]], [[MIT 6.824 Raft Lab 2C Persistence Map]]

## Project summary

Implemented the MIT 6.824 Raft consensus labs through Lab 2C in Go: leader election, heartbeat-based authority, log replication and repair, majority commitment, ordered state-machine application, and durable recovery under crashes and unreliable RPC delivery.

The implementation uses synchronized per-peer state, one replication worker per follower, accelerated conflict backtracking, a condition-variable-driven applier, and persistence of `currentTerm`, `votedFor`, and `log`.

## Ninety-second interview explanation

> Each Raft server runs as a follower, candidate, or leader and advances through monotonically increasing terms. Randomized election timeouts trigger candidacy, and a candidate must win a majority while presenting an up-to-date log. The leader accepts a command through `Start()`, appends and persists it locally, and asynchronously replicates the missing suffix to each follower with `AppendEntries`. Followers verify the leader's prefix using the previous index and term, replace only conflicting uncommitted suffixes, persist changes, and acknowledge success. The leader tracks verified follower progress with `matchIndex` and sending estimates with `nextIndex`. When a current-term entry reaches a majority, the leader commits it and its prefix, wakes a condition-variable-based applier, and propagates the new commit index to followers. Across crashes, each peer restores its term, vote, and log before starting background goroutines; volatile leadership, replication estimates, and commit knowledge are reconstructed.

## Safety properties mapped to mechanisms

| Property | Meaning | Main mechanisms |
|---|---|---|
| Election Safety | At most one leader per term | One persisted vote per term and majority intersection |
| Leader Append-Only | A leader does not overwrite its own log | `Start()` appends; repair changes follower suffixes |
| Log Matching | Equal index and term imply equal prefixes | `PrevLogIndex`/`PrevLogTerm` check and suffix replacement |
| Leader Completeness | Future leaders contain committed entries | Candidate log-freshness rule, majority intersection, current-term commit rule |
| State Machine Safety | Servers do not apply different commands at one index | Committed common prefix and ordered application |

## Liveness mechanisms

Safety says nothing bad happens. Liveness says useful progress can eventually happen under the required timing assumptions.

- Randomized election deadlines reduce repeated split votes.
- RPCs to different peers proceed independently.
- One disconnected follower cannot prevent a majority from committing.
- Prefix mismatch retries immediately with conflict hints.
- Network failure waits for a later heartbeat instead of busy-spinning.
- Removing a nonstandard recent-quorum step-down prevents valid repair replies from repeatedly interrupting leadership.
- Accelerated backtracking skips whole conflicting ranges during Figure 8-style divergence.

Raft cannot guarantee progress without a reachable majority, but it must preserve safety during the partition.

## Exact state distinctions

```text
currentTerm  = latest election epoch observed locally
votedFor     = vote granted in currentTerm
log          = persistent ordered accepted entries
nextIndex    = leader's next sending estimate for a follower
matchIndex   = highest follower index verified by this leader
commitIndex  = highest index locally known committed
lastApplied  = highest index delivered to local state machine
```

## Concurrency architecture

```text
ticker goroutine
    -> elections and heartbeat scheduling

per-follower replication worker
    -> waits on replicateCh
    -> performs prefix search and replication

applier goroutine
    -> waits on applyCond
    -> sends committed entries to applyCh in order

RPC handler goroutines
    -> RequestVote and AppendEntries state transitions
```

Shared state is protected with one mutex per peer. RPCs and blocking `applyCh` sends happen after releasing the mutex.

## Failure scenarios to be able to trace

### Old leader returns after partition

It sends an old-term RPC, receives a higher term in the reply, updates and persists its term, and becomes follower. It cannot commit without a majority during isolation.

### Candidate receives a delayed vote

It counts the vote only if it is still candidate and still in the captured election term. Otherwise, the reply is obsolete.

### Follower has a divergent suffix

It rejects the prefix check and returns `ConflictTerm`/`ConflictIndex`. The leader moves `nextIndex` backward, finds a common prefix, and replaces only the follower's conflicting suffix.

### Leader crashes after local append but before majority

The entry survives locally because it was persisted, but it is not necessarily committed. A future legitimate leader may preserve or overwrite it.

### Follower crashes after acknowledging an entry

The acknowledged entry survives because the follower persisted before replying success.

### Server restarts with `commitIndex=0`

Committed entries remain committed globally. The server relearns `LeaderCommit` and reapplies from its recovered log or snapshot position.

## Common interviewer questions

### Why not hold the mutex across an RPC?

A slow or partitioned peer could prevent local handling of heartbeats, vote requests, higher terms, and other replies. Use lock-snapshot-unlock-RPC-relock-validate.

### Why are `nextIndex` and `matchIndex` different?

`nextIndex` is an estimate used to construct the next request. `matchIndex` is verified evidence used for commitment.

### Why can an old-term entry not be directly committed by replica counting?

A later conflicting log may still win a future election. Replicating a current-term entry to a majority establishes the election evidence that protects that entry and its whole prefix.

### What does persistence protect that the mutex does not?

The mutex protects consistency among concurrent goroutines in one execution. Persistence protects safety-critical state across process crashes and restarts.

### Why does one `sync.Cond.Signal()` apply many entries?

The signal only wakes the applier. The persistent predicate `commitIndex > lastApplied` remains true until the applier drains every outstanding index.

### Does a blocked `select` busy-wait?

No. Without a `default`, the runtime parks the goroutine until a channel operation becomes ready.

## Resume bullet candidates

- Implemented Raft consensus in Go through MIT 6.824 Lab 2C, including randomized leader election, replicated-log consistency, majority commitment, ordered application, and crash-safe persistence under unreliable networks.
- Designed per-follower replication workers with accelerated conflict backtracking and stale-reply validation, enabling efficient recovery of divergent logs while preserving Raft safety invariants.
- Built concurrency-safe state transitions using mutex-protected snapshots, nonblocking notification channels, condition-variable-driven application, and race-tested RPC processing.

Use only bullets that you can support with the actual code and test results.

## Self-test checklist

Be able to explain without reading code:

- The full path from `Start()` to `applyCh`.
- Every reason a peer changes term or role.
- The exact log-freshness comparison.
- How `PrevLogIndex` and `PrevLogTerm` establish a common prefix.
- One complete `ConflictTerm`/`ConflictIndex` repair example.
- Why only current-term entries are committed directly by counting replicas.
- Why `commitIndex` and `lastApplied` are different.
- Every mutation that calls `persist()`.
- Why `currentTerm`, `votedFor`, and `log` are persistent while the other fields are volatile.
- What each long-running goroutine waits on and how it stops.

