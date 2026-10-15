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
  - distributed-systems
  - concurrency
  - redis
  - interview
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

So release is a **check-and-delete**: "if the value is my token, delete it." That is **two logical steps**, and doing them as separate `GET` then `DEL` has a race — the lock could expire and be re-acquired by someone else *between* your GET and DEL, and your DEL would delete their lock. The fix: do it **atomically in a Lua script**.

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

## Multi-node: Redlock and its controversy

A lock on a **single** Redis master is lost if that master fails before replicating. **Redlock** acquires the lock on a **majority of N independent Redis masters** to tolerate failures. It is **controversial** — Martin Kleppmann argued it is unsafe under clock skew and GC/STW pauses (a paused holder can believe it still holds the lock after expiry). For correctness-critical mutual exclusion, a consensus system ([[Raft Leader Election and Voting|Raft]]/ZooKeeper) or a fencing token is safer; Redis locks are fine when occasional double-execution is tolerable (and consumers are idempotent — see [[Idempotency]]).

## Relationship to a local mutex

| | [[Mutex]] (in-process) | Distributed lock (Redis) |
| --- | --- | --- |
| Scope | threads in one process | processes across machines |
| State | process memory | shared store (Redis) |
| Failure of holder | process dies, lock gone with it | **TTL** needed so a dead holder's lock frees |
| Release safety | owner unlocks | **token + Lua** so you free only your own |

## Interview summary

> A distributed lock is mutual exclusion across machines, typically `SET key <unique-token> NX EX <ttl>` in Redis — one atomic command (SETNX + EXPIRE separately is unsafe). The value is a unique token so release deletes only your own lock, and release is a check-and-delete done atomically in a Lua script (Redis runs Lua with no interleaving), because GET-then-DEL as two commands races. A TTL prevents a dead holder from deadlocking, but if work outlasts the TTL the lock can expire mid-work and double-grant — handled by a watchdog that renews the lease (Redisson). For multi-master fault tolerance there's Redlock, which is contested (clock/GC-pause critiques); correctness-critical locks are better served by Raft/ZooKeeper or fencing tokens, and consumers should be idempotent regardless.

## Related notes

- [[Mutex]]
- [[Semaphore]]
- [[Compare-and-Swap]]
- [[Redis Caching Patterns]]
- [[Idempotency]]
- [[Raft Leader Election and Voting]]
