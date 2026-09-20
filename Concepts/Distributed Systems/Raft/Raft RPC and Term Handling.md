
Parent: [[Raft MOC]]

Related: [[Raft Leader Election and Voting]], [[Raft Concurrency and Locking in Go]]

## RPC types needed for Lab 2A

### `RequestVote`

Sent by a candidate to gather votes.

```text
Arguments: Term, CandidateId, LastLogIndex, LastLogTerm
Reply:     Term, VoteGranted
```

### `AppendEntries`

Sent by a leader. An empty entry list is a heartbeat.

```text
Arguments: Term, LeaderId, PrevLogIndex, PrevLogTerm, Entries, LeaderCommit
Reply:     Term, Success
```

Go RPC-visible fields must begin with capital letters. `term` is not serialized; `Term` is.

## Universal term processing

Before using the ordinary meaning of any RPC request or reply:

```text
if receivedTerm > currentTerm:
    currentTerm = receivedTerm
    role = Follower
    votedFor = none
```

The higher term is authoritative election information. It does not prove leadership or log freshness.

## `RequestVote` request decision table

| Condition | Action |
|---|---|
| `args.Term < currentTerm` | Reject; reply with `currentTerm`; do not reset timer |
| `args.Term > currentTerm` | Update term, become follower, clear old vote; then evaluate voting conditions |
| Same term and already voted for another candidate | Reject; keep existing `votedFor`; do not reset timer |
| Same term and vote is available/same candidate and log passes | Grant; set `votedFor`; reset timer |

Receiving a higher-term vote request can cause a server to step down while still denying the candidate because its log is stale.

## `RequestVote` reply handling

Process a reply under the mutex:

1. If `reply.Term > currentTerm`, update the term, become follower, clear the vote, and stop processing the reply.
2. If no longer candidate, ignore the ordinary vote result.
3. If `currentTerm != electionTerm`, ignore the obsolete result.
4. If the vote is granted, increment this campaign's vote count.
5. If the count reaches a majority and the campaign is still current, become leader.

## `AppendEntries` request decision table for 2A

| Condition | Action |
|---|---|
| `args.Term < currentTerm` | Reject with current term; do not reset timer |
| `args.Term > currentTerm` | Update term, become follower, clear vote, process as current leader contact |
| Same term while candidate | Become follower; do not clear a same-term vote; reset timer |
| Same term while follower | Remain follower; reset timer |

In Lab 2A, logs are empty, so a non-stale heartbeat normally succeeds. Lab 2B adds the `prevLogIndex` and `prevLogTerm` consistency check.

A candidate that voted for itself may still accept the same-term elected leader's heartbeat. Voting for a candidate and acknowledging the candidate that actually won are separate actions.

## `AppendEntries` reply handling

In Lab 2A, the most important reply information is the term:

```text
if reply.Term > currentTerm:
    update term
    become follower
    clear votedFor
```

Ordinary replies are relevant only if the sender is still leader in the term that created the RPC. Lab 2B then uses current successful or failed replies to update per-follower replication state.

## Old leader returning after a partition

If a term-1 leader contacts a term-2 server:

```text
AppendEntriesReply {
    Term: 2
    Success: false
}
```

The reply does not need to say, "I am the new leader." The old leader observes the higher term and follows the universal rule to step down.

## RPC transport does not share Go objects across servers

`labrpc` conceptually serializes the request, invokes a handler on the receiver, serializes the receiver's reply, and decodes it into the caller's reply object.

The servers do not share the same struct. However, two caller goroutines must not decode their replies into the same local reply object, because that would be a local data race.

