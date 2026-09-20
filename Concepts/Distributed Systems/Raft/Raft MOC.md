# Raft MOC

Raft is a consensus algorithm for maintaining a replicated log across servers that can crash, become partitioned, and exchange delayed or lost messages.

## Learning map

1. [[Raft System Model Terms and Roles]]
   - What one Raft peer is
   - Followers, candidates, and leaders
   - Terms as logical election epochs

2. [[Raft Leader Election and Voting]]
   - Starting an election
   - Majority voting and split votes
   - Why randomized election timeouts are necessary

3. [[Raft Heartbeats and Election Timers]]
   - Empty `AppendEntries` as heartbeats
   - Which events reset an election timeout
   - The timing constraints used in MIT 6.824 Lab 2A

4. [[Raft RPC and Term Handling]]
   - Handling stale, current, and newer terms
   - Processing delayed RPC replies safely

5. [[Raft Log Freshness and Leader Eligibility]]
   - Why a higher term does not imply a newer log
   - The `(lastLogTerm, lastLogIndex)` comparison

6. [[Raft Concurrency and Locking in Go]]
   - Why one peer still needs a mutex
   - Locking around state transitions but not network calls
   - Preventing stale goroutines from changing current state

7. [[MIT 6.824 Raft Lab 2A Implementation Map]]
   - Required fields, RPCs, goroutines, and handlers
   - A test and debugging checklist

## Core mental model

Each Raft peer is an independent state machine. Peers share no variables and communicate only through RPCs. Within one peer, however, several goroutines share the same local Raft state, so local state transitions must be synchronized.

Raft separates three questions:

1. **Which election epoch is current?** Tracked by `currentTerm`.
2. **Who may act as leader in that term?** Decided by a majority vote.
3. **Is a candidate's log eligible?** Decided by log freshness.

## Core invariants

- Terms increase monotonically on each peer.
- A peer grants at most one vote per term.
- At most one leader can be elected in a given term.
- Any RPC request or response with a higher term makes the receiver update its term and become a follower.
- A candidate counts votes only while it is still a candidate in the election term that requested them.
- A server with a high term may still have a stale log.
- Network calls are made without holding the local Raft mutex.

## Lab boundaries

### Lab 2A

- Leader election
- `RequestVote`
- Empty `AppendEntries` heartbeats
- Terms and role transitions
- Election timing
- Concurrency-safe RPC reply processing

### Lab 2B and later

- Log replication and conflict repair
- `nextIndex` and `matchIndex`
- Commitment and application
- Persistence and recovery tests
- Snapshots

Cluster membership changes through joint consensus are described by Raft but are not required by the 2020 lab.

## Sources

- [Raft extended paper](https://raft.github.io/raft.pdf), especially Figure 2 and Sections 5.1-5.4
- [MIT 6.824 2020 Lab 2](http://nil.csail.mit.edu/6.824/2020/labs/lab-raft.html)

