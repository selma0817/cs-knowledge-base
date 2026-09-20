
Parent: [[Raft MOC]]

## One `Make()` call creates one peer

`Make(peers, me, persister, applyCh)` initializes one local Raft peer, not the entire cluster.

The surrounding service or test harness creates one peer for each configured server:

```text
Make(..., me=0, ...) -> S0
Make(..., me=1, ...) -> S1
Make(..., me=2, ...) -> S2
```

Each peer has:

- Its own `currentTerm`, `votedFor`, role, timer state, and log
- Its own background goroutines
- An index `me` identifying itself
- RPC endpoints in `peers` for contacting the fixed cluster members

In a deployed system, peers normally run in different processes or machines. MIT's `labrpc` places independent Go objects in one test process but simulates loss, delay, reordering, and disconnection between them.

## The three roles

### Follower

- Responds to candidate and leader RPCs
- Does not initiate communication normally
- Becomes a candidate when its election timeout expires

### Candidate

- Campaigns for leadership in one term
- Votes for itself and sends `RequestVote` RPCs
- Becomes leader after receiving a majority
- Starts a newer election if its election timeout expires
- Becomes follower after recognizing a current or newer leader

### Leader

- Sends an initial empty `AppendEntries` immediately after election
- Continues sending periodic heartbeats
- Drives log replication in Lab 2B
- Becomes follower after observing a higher term

Use one role field rather than independent booleans:

```go
type Role int

const (
    Follower Role = iota
    Candidate
    Leader
)
```

Separate `isFollower`, `isCandidate`, and `isLeader` booleans could represent impossible combinations.

## What a term means

A term is a logical election epoch, not the number of elections a particular server has personally observed.

- A peer increments `currentTerm` when it starts an election.
- Several candidates may compete in the same term.
- A term may finish without electing a leader.
- A partitioned peer can miss several terms and later jump directly to a newer one.
- Terms are not continuously synchronized across the cluster.

Example:

```text
S0 at term 1 receives an RPC with term 4
-> S0 moves directly to term 4
```

Terms give precedence to newer election information. They do not prove that the sender is a leader or has the newest log.

## The universal higher-term rule

If any RPC request or response contains `T > currentTerm`:

```text
currentTerm = T
role        = Follower
votedFor    = none
```

This rule applies even when the receiver currently believes it is leader.

## Can two leaders exist temporarily?

During a partition, an old leader can remain unaware that a new leader was elected in a later term:

```text
S2 believes it is leader for term 1
S3 is elected leader for term 2
```

This does not violate election safety. Raft guarantees at most one elected leader **per term**, not that no obsolete server can temporarily retain an old belief. The old leader cannot commit new entries without a majority and steps down after observing the newer term.

## Persistent and volatile state

Figure 2 classifies these as persistent:

- `currentTerm`
- `votedFor`
- `log[]`

They must eventually survive crashes, although persistence is tested more directly in a later lab.

Election roles, deadlines, and vote counts are volatile and reconstructed during execution.

## Static membership in the lab

Calling `Make()` for a new process does not safely add it to an existing cluster. Existing peers would disagree about membership and majority size. Dynamic membership requires Raft's joint-consensus transition:

```text
old configuration
-> joint old+new configuration
-> new configuration
```

Lab 2A assumes fixed membership.

