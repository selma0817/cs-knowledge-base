
Parent: [[Raft MOC]]

Related: [[Raft Heartbeats and Election Timers]], [[Raft RPC and Term Handling]]

## Starting an election

When a follower or unsuccessful candidate reaches its election deadline, it performs one atomic local transition:

```text
role = Candidate
currentTerm++
votedFor = self
votes = 1
choose a fresh randomized election timeout
capture the new election term
```

It then sends `RequestVote` RPCs concurrently to every other peer.

The self-vote counts. For `N` servers:

```text
majority = N/2 + 1
```

For five servers, the candidate needs three votes total, including its own.

## `RequestVote` is not a heartbeat

- Candidates send `RequestVote` to ask for votes.
- Leaders send `AppendEntries`.
- An `AppendEntries` with no log entries is a heartbeat.

The term is a field inside both RPCs; there is no separate "new-term message."

## Voting conditions

A receiver grants a vote when:

```text
candidate term is not stale
AND
(votedFor is none OR votedFor is this same candidate)
AND
candidate log is at least as up-to-date
```

Granting the same candidate's repeated request is idempotent. It does not constitute a second vote.

When granting a vote:

```text
votedFor = candidateId
reset election timing
```

A rejected stale request or rejected same-term request does not reset the election timeout.

## Why one vote per term matters

Any two majorities overlap. In a five-server cluster, any two sets of three contain at least one common server.

If every server grants at most one vote per term, two candidates cannot both obtain a majority in that term. The shared server would otherwise have to vote twice.

This is the basis of Raft's Election Safety Property:

> At most one leader can be elected in a given term.

## Split votes

Example with five servers:

```text
S2 receives: self + S0 = 2 votes
S3 receives: self + S1 = 2 votes
S4 receives neither request
```

Neither candidate becomes leader. When a candidate's newly established election timeout expires:

1. It starts a new election.
2. It increments the term.
3. It votes for itself again in the new term.
4. It chooses a fresh randomized timeout.

Randomization makes it unlikely that the same candidates will repeatedly time out together.

## Candidate outcomes

A candidate remains in its campaign until one of these occurs:

1. **Majority received:** become leader.
2. **Valid `AppendEntries` from a current/new-term leader:** become follower.
3. **Higher term in any request or response:** update term and become follower.
4. **Election timeout:** begin a new election in a higher term.

## Delayed vote replies

Each outbound vote RPC belongs to a specific campaign. Its goroutine must capture `electionTerm`.

A granted reply can be counted only if:

```text
role == Candidate
AND currentTerm == electionTerm
AND reply.VoteGranted
```

A higher reply term is always processed first and causes a transition to follower. Lower-term or otherwise obsolete replies are ignored.

## Vote-count lifetime

A timeless shared `voteCount` is dangerous:

```text
term 6 vote arrives late
term 7 has already reset voteCount
old vote incorrectly increments term 7 count
```

Prefer a per-election count captured by that campaign's goroutines, or store the count together with the exact term it belongs to. Any count shared across goroutines still requires synchronization.

