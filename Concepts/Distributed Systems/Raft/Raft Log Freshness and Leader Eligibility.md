
Parent: [[Raft MOC]]

Related: [[Raft System Model Terms and Roles]], [[Raft Leader Election and Voting]]

## Term freshness and log freshness are independent

A server can have a high `currentTerm` and a stale log. For example, an isolated server may repeatedly start elections without receiving any new entries:

```text
currentTerm: 4 -> 5 -> 6
log:         unchanged
```

Therefore:

- `currentTerm` measures election knowledge.
- `lastLogTerm` and `lastLogIndex` measure log eligibility.

A higher-term message invalidates older leadership, but it does not automatically make the sender an eligible leader.

## The log freshness comparison

Raft compares candidate and receiver logs lexicographically:

```text
candidate is at least as up-to-date if:

candidateLastLogTerm > receiverLastLogTerm

OR

candidateLastLogTerm == receiverLastLogTerm
AND candidateLastLogIndex >= receiverLastLogIndex
```

The last log term is compared first. Only when those terms are equal does the index break the tie.

This is more precise than saying that the candidate must be "closest to the old leader" or simply have the longest log.

## Higher term but stale log

Suppose:

```text
S0: currentTerm=4, more up-to-date log
S2: currentTerm=5, stale log, Candidate
```

When S2 sends a term-5 `RequestVote`, S0:

1. Updates `currentTerm` to 5.
2. Becomes a follower.
3. Clears its term-4 `votedFor` value.
4. Compares the logs.
5. Denies S2's vote because S2 is stale.

Recognizing a newer term and granting a vote are separate decisions.

## Why the election restriction matters

A candidate must collect votes from a majority. If voters reject candidates whose logs are behind, the winning candidate is sufficiently up-to-date relative to that majority. Combined with majority intersection, this prevents an elected leader from missing previously committed entries.

This is the foundation of Raft's Leader Completeness Property.

## Relevance to Lab 2A

Lab 2A does not replicate client entries, so all logs are effectively equal and the freshness check is trivial. Still include or plan the RPC fields:

```go
LastLogIndex int
LastLogTerm  int
```

The behavior becomes necessary in Lab 2B.

