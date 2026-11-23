---
date: 2026-10-15
aliases:
  - distributed lock
  - redis lock
  - redlock
  - SET NX EX
  - redisson
  - watchdog
  - lua atomicity
tags:
  - topic/concurrency
  - topic/replication-consistency
  - redis
  - lua
  - redlock
  - fencing-token
---
A **distributed lock** gives mutual exclusion **across processes/machines** — a [[Mutex]] whose state lives in a shared store (commonly Redis) instead of one process's memory. The subtleties are atomic acquire/release, lock expiry vs. unfinished work, and why release needs a Lua script.

## Acquire: one atomic command

```
SET lock_key <unique-token> NX EX <seconds>
```

- **`NX`** — set only if the key does **not** exist (this *is* the "acquire": succeeds for exactly one client).
- **`EX <seconds>`** — expiry, so a crashed holder's lock auto-releases (no permanent deadlock).
- Both in **one atomic `SET`**. The old `SETNX` + separate `EXPIRE` is **not atomic** — a crash in between leaves a lock with no expiry → permanent deadlock.

## The unique token, and safe release

The value must be a **unique token** (e.g. UUID + thread id) identifying *this* holder. Why: on release you must delete **only your own** lock. A blind `DEL lock_key` could delete a lock that **another** client acquired after yours expired.

So release is a **check-and-delete**: "if the value is my token, delete it." Doing it as two separate commands races:
```
GET lock_key          # → returns stored token
# client compares: token == my_token ?
DEL lock_key          # delete
```
**Between** the GET and the DEL, your lock can expire and client B can acquire it (new token). Your client already decided "it's mine" from the now-stale GET, and the DEL **deletes B's lock**. The fix: do GET-compare-DEL **atomically in a Lua script**.

```lua
-- release: delete only if we still hold it
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
else
    return 0
end
```

## Why Lua

Redis executes a **Lua script atomically** — Redis is single-threaded and runs the whole script to completion with **no other command interleaved**. So a multi-step **check-then-act** (compare token, then delete) becomes one indivisible operation, eliminating the race. This is the same atomicity idea as [[Compare-and-Swap]], one layer up: the token compare is the "compare," the delete is the "act," and Lua makes the pair atomic.

## Expiry vs. unfinished work: the watchdog

If the work outlasts the lock's TTL, the lock expires **while you're still working**, another client acquires it, and now **two holders** race on the shared resource. Options:

- **Watchdog / lease renewal:** a background thread renews (extends) the TTL while the holder is alive. **Redisson** does this automatically (default 30 s lease, renewed every 10 s), and also supports **reentrant** locks.
- Set a TTL safely longer than the expected work, with renewal as backup.

But the watchdog only renews *while the holder is alive*, so two cases differ:
- **Holder crashes** → the watchdog thread dies with it → renewals stop → the TTL expires → lock **auto-frees**. (This is why you still need a TTL, not an infinite lock.)
- **Holder hangs forever** (alive but stuck) → the watchdog keeps renewing → the lock **never frees**. Bound this with a **max lease / renewal cap** (Redisson's `leaseTime`) or an **overall operation timeout** that aborts the work.

## Multi-node: Redlock and its controversy

A lock on a **single** Redis master is lost if that master fails before replicating. **Redlock** acquires the lock on a **majority of N independent Redis masters** to tolerate failures. It is **controversial** — Martin Kleppmann argued it is unsafe under clock skew and GC/STW pauses (a paused holder can believe it still holds the lock after expiry). For correctness-critical mutual exclusion, a consensus system ([[Raft Leader Election and Voting|Raft]]/ZooKeeper) or a fencing token is safer; Redis locks are fine when occasional double-execution is tolerable (and consumers are idempotent — see [[Idempotency]]).

## Fencing tokens: the storage rejects a stale holder

A TTL and a watchdog can't stop one failure: a holder that pauses (a long GC pause, say), lets the lock expire, then wakes up still believing it holds the lock and writes. Martin Kleppmann's fix is a **fencing token**: a number that the lock service increases every time a client acquires the lock, sent along with every write ([How to do distributed locking](https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html)).

```text
client 1: acquires the lock, token 33 → long pause → lock expires
client 2: acquires the lock, token 34 → writes with 34 → storage remembers 34
client 1: wakes up → writes with 33 → storage rejects it (33 < 34)
```

The check happens in the **storage service**, not in the lock: it remembers the highest token it has accepted and rejects writes with an older one. A plain Redis `SET ... NX` returns `OK` or nil, not a number, so the increasing token has to come from somewhere else.

## Relationship to a local mutex

| | [[Mutex]] (in-process) | Distributed lock (Redis) |
| --- | --- | --- |
| Scope | threads in one process | processes across machines |
| State | process memory | shared store (Redis) |
| Failure of holder | process dies, lock gone with it | **TTL** needed so a dead holder's lock frees |
| Release safety | owner unlocks | **token + Lua** so you free only your own |

## Interview summary

> A distributed lock is mutual exclusion across machines, typically `SET key <unique-token> NX EX <ttl>` in Redis — one atomic command (SETNX + EXPIRE separately is unsafe). The value is a unique token so release deletes only your own lock, and release is a check-and-delete done atomically in a Lua script (Redis runs Lua with no interleaving), because GET-then-DEL as two commands races. A TTL prevents a dead holder from deadlocking, but if work outlasts the TTL the lock can expire mid-work and double-grant — handled by a watchdog that renews the lease (Redisson). For multi-master fault tolerance there's Redlock, which is contested (clock/GC-pause critiques); correctness-critical locks are better served by Raft/ZooKeeper or fencing tokens, and consumers should be idempotent regardless.

## Common mistakes

From a quiz on 2026-10-30.

### Mistake 1: thinking the key must be unique (mine)

The key is the lock's name: every client competing for the lock uses the same one. It's the **value** that must be unique, a token per holder, so release can tell your lock from the next holder's (see "The unique token, and safe release").

### Mistake 2: thinking GET then DEL is a safe release (mine)

Between the two commands your lock can expire and client B can take it; your `DEL` then deletes B's lock. Compare and delete in one Lua script, which Redis runs with nothing in between (see "Why Lua").

### Mistake 3: thinking the watchdog makes lock expiry safe (mine)

It renews only while the holder is alive. A crashed holder's lock frees when the TTL runs out, but a hung holder's lock never frees unless the lease is capped. And a holder that pauses past expiry can still write after someone else got the lock; only a fencing token checked by the storage stops that (see "Fencing tokens: the storage rejects a stale holder").

## Related notes

- [[Mutex]]
- [[Semaphore]]
- [[Compare-and-Swap]]
- [[Redis Caching Patterns]]
- [[Idempotency]]
- [[Raft Leader Election and Voting]]
