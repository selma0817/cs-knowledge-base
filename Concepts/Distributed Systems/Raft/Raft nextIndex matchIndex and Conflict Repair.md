# Raft nextIndex matchIndex and Conflict Repair

Parent: [[Raft MOC]]

Related: [[Raft Log Replication and AppendEntries]], [[MIT 6.824 Raft Lab 2B Implementation Map]], [[Raft Replication Workers and Signaling in Go]]

## Two different kinds of leader knowledge

For each follower, the leader tracks:

| Field | Meaning | Confidence |
|---|---|---|
| `nextIndex[peer]` | Next log index the leader will try to send | Estimate |
| `matchIndex[peer]` | Highest index verified to match on the follower | Confirmed fact |

Do not treat them as interchangeable.

The useful invariant is:

```text
nextIndex[peer] >= matchIndex[peer] + 1
```

## Initialization after election

For a new leader whose last log index is `L`:

```text
nextIndex[other peers] = L + 1
matchIndex[other peers] = 0

matchIndex[self] = L
nextIndex[self] = L + 1
```

Starting `nextIndex` at the end is optimistic. Rejections move it backward until a common prefix is found.

## Constructing an attempt

For one follower:

```text
next = nextIndex[peer]
PrevLogIndex = next - 1
PrevLogTerm  = leader.log[next - 1].Term
Entries      = leader.log[next:]
```

On success, the leader computes verified progress from the exact request:

```text
replicatedThrough = PrevLogIndex + len(Entries)
matchIndex[peer] = max(matchIndex[peer], replicatedThrough)
nextIndex[peer]  = max(nextIndex[peer], matchIndex[peer] + 1)
```

This avoids letting an older reply decrease confirmed progress.

## Why decrementing one-by-one is slow

A basic repair can do:

```text
on rejection: nextIndex--
```

It is logically correct but can require many successful request/reply rounds for a short or highly divergent follower. Unreliable networks amplify the delay.

Accelerated backtracking returns information about the whole conflicting run.

## Follower conflict reply

### Follower is too short

If:

```text
PrevLogIndex >= len(follower.log)
```

return:

```text
ConflictTerm  = -1
ConflictIndex = len(follower.log)
```

The leader jumps directly to the follower's end.

### Follower has a different term

If the follower has `PrevLogIndex` but its term differs:

```text
ConflictTerm = follower.log[PrevLogIndex].Term
ConflictIndex = first index in follower.log with ConflictTerm
```

The follower scans backward through the consecutive entries of that term.

## Leader use of conflict information

If `ConflictTerm == -1`:

```text
candidateNext = ConflictIndex
```

Otherwise, the leader searches its own log for the last entry with `ConflictTerm`:

```text
if leader contains ConflictTerm:
    candidateNext = one past its last entry in that term
else:
    candidateNext = ConflictIndex
```

The result is clamped to a legal range and must move backward unless confirmed progress prevents it.

## Complete example

Leader:

```text
index: 0  1  2  3  4  5
term:  0  1  1  3  3  5
```

Follower:

```text
index: 0  1  2  3  4
term:  0  1  1  2  2
```

Initial leader estimate:

```text
nextIndex[follower] = 6
```

Repair:

```text
Attempt 1:
PrevLogIndex=5
Follower too short -> ConflictTerm=-1, ConflictIndex=5
nextIndex: 6 -> 5

Attempt 2:
PrevLogIndex=4, leader term=3, follower term=2
Follower -> ConflictTerm=2, ConflictIndex=3
Leader has no term 2
nextIndex: 5 -> 3

Attempt 3:
PrevLogIndex=2, PrevLogTerm=1
Prefix matches
Leader sends indices 3..5
Follower replaces its conflicting suffix
```

After success:

```text
matchIndex[follower] = 5
nextIndex[follower] = 6
```

## Retry policy

The replication loop distinguishes two failures.

### Logical rejection

The follower replied, so the network path is working:

```text
calculate smaller nextIndex
do not return from replicateToPeer
loop immediately and send a new attempt
```

### Network-level failure or timeout

There is no reliable conflict information:

```text
return from replicateToPeer
replicationWorker blocks in select
retry after a future heartbeat or replication signal
```

Immediate retry on network failure could create a CPU- and network-intensive tight loop while a follower is disconnected.

## Common mistakes

- Setting `matchIndex` from an estimate rather than a successful RPC.
- Updating `nextIndex` using only `len(Entries)` instead of the request's `PrevLogIndex`.
- Allowing a stale reply to decrease `matchIndex`.
- Truncating the follower before the prefix matches.
- Returning conflict information that does not make backward progress.
- Waiting for the next heartbeat after every valid mismatch, making repair unnecessarily slow.
- Retrying endlessly after network failure without delay.

