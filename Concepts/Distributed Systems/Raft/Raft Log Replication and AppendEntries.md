# Raft Log Replication and AppendEntries

Parent: [[Raft MOC]]

Related: [[MIT 6.824 Raft Lab 2B Implementation Map]], [[Raft nextIndex matchIndex and Conflict Repair]], [[Raft Commitment and Application]], [[Raft Log Freshness and Leader Eligibility]]

## Replicated-log mental model

The leader does not send a command directly to each state machine. It first establishes an identical ordered log prefix across a majority:

```text
client command
    -> leader log entry
    -> follower log entries
    -> committed log prefix
    -> deterministic state-machine application
```

The log is the ordered consensus history. The state machine is the result of executing the committed prefix.

## Log indexing

The implementation starts with a dummy entry:

```text
index 0: {Term: 0}
```

Real commands begin at index 1. This avoids special cases when the leader needs to prove that the prefix before the first command matches.

Each entry contains:

```go
type LogEntry struct {
    Term    int
    Command interface{}
}
```

The term records which leader epoch created the entry. The index is its position in the slice.

## `Start()` means propose, not commit

If the receiving server believes it is leader, `Start(command)`:

1. Appends a new current-term entry locally.
2. Persists the changed log.
3. Updates its own replication bookkeeping.
4. Signals replication.
5. Returns immediately.

The distinction is:

```text
Start returned true
    != follower received the entry
    != majority stored the entry
    != entry committed
    != command applied
```

## `AppendEntries` carries both replication and heartbeat information

```text
Term
LeaderId
PrevLogIndex
PrevLogTerm
Entries
LeaderCommit
```

When `Entries` is empty, the RPC is normally called a heartbeat. It still checks the log prefix and carries commitment information. A heartbeat is therefore not a separate protocol.

## Prefix consistency check

Before accepting new entries, the follower asks:

```text
Do I have an entry at PrevLogIndex?
If so, does its term equal PrevLogTerm?
```

If either answer is no, it rejects without changing the log. If both are yes, the leader and follower share the same prefix through `PrevLogIndex` because of the Log Matching Property.

## Merging the leader suffix

After the prefix matches, compare incoming and local entries in order.

```text
same index and same term
    -> retain the local entry

first same index but different term
    -> delete local suffix from this index
    -> append the remaining leader suffix

incoming entry beyond local log
    -> append all remaining entries
```

The implementation does not compare command values when terms match. Raft's leader rules guarantee that two entries with the same index and term represent the same entry.

## Example

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

Once the leader finds the common prefix through index 2, it sends entries 3 through 5. The follower replaces its term-2 suffix:

```text
before: 0 1 1 2 2
after:  0 1 1 3 3 5
```

Only the uncommitted conflicting suffix is replaceable. Raft election restrictions prevent a legitimate leader from lacking an already committed entry.

## Success means a durable follower acknowledgement

If the follower changes its log, it persists before replying `Success=true`:

```text
modify log
    -> persist currentTerm, votedFor, and log
    -> return success
```

The leader may use the success reply as evidence that the follower stores the entry. Returning success before persistence would let a crash erase evidence that was counted toward a majority.

If an identical RPC changes nothing, another persistence write is unnecessary.

## Follower commitment

The follower does not infer commitment merely because it appended an entry. It follows the leader's `LeaderCommit` value:

```text
newCommitIndex = min(LeaderCommit, matchedThrough)
```

The bound prevents the follower from claiming commitment beyond the prefix this RPC verified.

## Key invariants

- A rejection caused by prefix inconsistency does not modify the follower log.
- Matching entries are retained; only the first conflicting suffix is replaced.
- Successful changed logs are persisted before the reply is exposed.
- A leader never interprets `Start()` success as consensus success.
- A heartbeat maintains authority, checks consistency, and propagates `LeaderCommit` even when it carries no new entries.

## Interview questions

- Why does Raft compare terms at `PrevLogIndex` instead of comparing full logs?
- Why is deleting the entire follower log on any mismatch incorrect?
- Why can entries with equal index and term be treated as identical?
- Why must a follower persist before returning success?
- What is the difference between appending an entry and committing it?

