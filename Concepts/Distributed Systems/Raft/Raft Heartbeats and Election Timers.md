
Parent: [[Raft MOC]]

Related: [[Raft Leader Election and Voting]], [[MIT 6.824 Raft Lab 2A Implementation Map]]

## Heartbeats are empty `AppendEntries`

Raft does not define a separate heartbeat RPC. A leader sends:

```text
AppendEntries {
    Term: leader's term
    LeaderId: leader
    Entries: empty
}
```

A newly elected leader sends an initial heartbeat immediately. It then repeats heartbeat rounds during idle periods.

Heartbeats:

- Announce the current leader and term
- Prevent follower election timeouts
- Cause a same-term candidate to become a follower
- Carry log and commit information in later labs

## Election timing is local

Each non-leader tracks a local election deadline. Two useful representations are:

```go
electionDeadline time.Time
```

or:

```go
lastElectionReset time.Time
electionTimeout   time.Duration
```

The server chooses one randomized duration for the current waiting period. It must not generate a new duration on every short ticker check, because that would continually move the deadline.

## Events that reset election timing

| Event | Reset? | Reason |
|---|---:|---|
| Valid current/new-term `AppendEntries` | Yes | A current leader is active |
| Stale `AppendEntries` | No | Obsolete leader must not suppress elections |
| Grant `RequestVote` | Yes | Give the selected candidate time to finish |
| Reject same-term vote after voting for someone else | No | Rejected candidates must not suppress progress |
| Reject stale `RequestVote` | No | Obsolete traffic must not postpone elections |
| Start a new election | Yes | Bound the duration of this campaign |
| Obsolete delayed RPC reply | No | It belongs to an old campaign |

When a leader becomes a follower, its implementation must establish meaningful follower timer state. This is timer bookkeeping, not permission to reset the election deadline for every arbitrary RPC.

## Why fixed timeouts fail

If every follower uses exactly 400 ms and all received the last heartbeat together, they may all become candidates together. A split vote can then repeat in each term.

Fresh randomized timeouts make one server more likely to time out first, collect votes, and send heartbeats before others become candidates.

Randomize again for each new election/waiting period, not only once at process startup.

## Timing relationships

The Raft paper gives:

$$
\text{broadcastTime} \ll \text{electionTimeout} \ll \text{MTBF}
$$

For Lab 2A, also require:

```text
heartbeat interval < election timeout << 5 seconds
```

The election timeout should be long enough for several heartbeat opportunities, but short enough that several split-vote rounds can still finish within the five-second test limit.

The 2020 lab limits leaders to at most 10 heartbeat rounds per second, so the periodic interval must be at least about 100 ms. A reasonable initial experiment is:

```text
heartbeat interval:          100-120 ms
randomized election timeout: 400-700 ms
```

These values are engineering choices, not Raft safety rules. Validate them under the lab tests.

## Ticker implementation model

The 2020 lab recommends a goroutine with a loop and short sleeps rather than relying on `time.Timer` or `time.Ticker` reset behavior.

Conceptually:

```text
while not killed:
    sleep for a short polling interval
    lock
    if not leader and election deadline passed:
        begin an election atomically
    unlock
```

A single long-lived loop can also schedule periodic leader heartbeats. Alternatively, a per-leadership heartbeat loop must be permanently bound to the term in which it was created.

## Preventing old heartbeat loops

Suppose a server is leader in term 1, follower in term 2, and leader again in term 3. An old term-1 loop that checks only `role == Leader` may wake during term 3 and send duplicate heartbeats.

A per-leadership loop should exit if:

```text
role != Leader OR currentTerm != leaderTerm
```

The alternative is one long-lived ticker that snapshots the current role and term on every heartbeat round.

