# Raft Commitment and Application

Parent: [[Raft MOC]]

Related: [[Raft Log Replication and AppendEntries]], [[Raft nextIndex matchIndex and Conflict Repair]], [[Raft Persistent and Volatile State]], [[MIT 6.824 Raft Lab 2B Implementation Map]]

## Four different stages

For one command, distinguish:

| Stage | Meaning |
|---|---|
| Appended locally | The leader added the entry to its own log |
| Replicated | One or more followers also store the entry |
| Committed | Raft guarantees that future leaders will contain the entry |
| Applied | The local state machine has executed or received the command |

The compact rule is:

```text
appended != replicated != committed != applied
```

`Start()` can return after only the first stage.

## Leader commitment calculation

The leader uses `matchIndex` to find the highest index `N` such that:

```text
N > commitIndex
a majority has matchIndex[peer] >= N
log[N].Term == currentTerm
```

It counts itself because its own log contains the entry.

When the leader sets:

```text
commitIndex = N
```

the entire prefix through `N` is committed.

## Why direct commitment requires the current term

An old-term entry can temporarily exist on a majority during a later term and still be vulnerable to a future candidate whose log ends in a later conflicting term.

Canonical shape:

```text
term 2: leader creates C on a minority
term 3: another leader creates conflicting D
term 4: first server becomes leader and spreads old C to a majority
```

If the term-4 leader crashes before adding a term-4 entry, the server holding `D(term 3)` may still have the more up-to-date log and win an election that overwrites C.

Therefore, a leader does not declare an older-term entry committed merely by counting its replicas in a later term.

The safe path is:

```text
append an entry from the current term
    -> replicate it to a majority
    -> commit that entry directly
    -> commit every preceding entry indirectly
```

Once a majority stores the current-term entry, any future candidate missing it is too stale to win votes from that majority. The entry and its prefix satisfy Leader Completeness.

## Propagating commitment to followers

After the leader advances `commitIndex`, it does two independent things:

```text
applyCond.Signal()
    -> wake this server's local applier

signalHeartbeat()
    -> promptly send a new LeaderCommit value to followers
```

The heartbeat announces what the leader has committed, not what the leader has already applied. `lastApplied` is never sent in the RPC.

On a follower:

```text
newCommitIndex = min(args.LeaderCommit, matchedThrough)
```

The matched-through bound avoids committing beyond the prefix that the current RPC verified.

## The applier goroutine

The applier waits for this predicate:

```text
commitIndex > lastApplied
```

When no work exists:

```go
for rf.commitIndex <= rf.lastApplied && !rf.killed() {
    rf.applyCond.Wait()
}
```

`Wait()` atomically:

1. Registers the goroutine as waiting.
2. Releases `rf.mu`.
3. Parks the goroutine.
4. Wakes after `Signal()` or `Broadcast()`.
5. Reacquires `rf.mu` before returning.

Releasing the mutex is necessary because replication handlers need the mutex to advance `commitIndex`.

## Why one signal can apply many entries

Suppose:

```text
lastApplied = 1
commitIndex = 5
```

One signal wakes the applier. It applies index 2, loops, and checks the predicate again:

```text
5 > 2 -> apply 3
5 > 3 -> apply 4
5 > 4 -> apply 5
5 <= 5 -> wait
```

`Signal()` does not carry a count. The durable shared-state difference `commitIndex - lastApplied` determines how much work exists.

## Why unlock before sending on `applyCh`

The application channel may block. Holding `rf.mu` during the send would prevent elections, heartbeats, and replication progress.

The applier therefore:

```text
lock
choose index = lastApplied + 1
copy the entry
unlock
send ApplyMsg
lock
advance lastApplied after the send succeeds
unlock
```

Updating `lastApplied` only after the successful send prevents the local Raft peer from claiming that it delivered a command that is still blocked.

## Commitment is a cluster fact; `commitIndex` is local knowledge

If a server crashes and forgets `commitIndex`, an already committed entry does not become uncommitted. Majority replication, election restriction, and durable logs preserve it. The restarted server can relearn the index from `LeaderCommit`.

See [[Raft Persistent and Volatile State]] for recovery implications.

## Interview questions

- Why is a majority-replicated old-term entry not always committed directly?
- Why does committing a current-term entry also commit its prefix?
- What is the difference between `commitIndex` and `lastApplied`?
- Why does `sync.Cond.Wait()` release and then reacquire the mutex?
- Why is one `Signal()` enough when `commitIndex` jumps by several entries?
- Why should the applier release `rf.mu` before sending to `applyCh`?

