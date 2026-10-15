---
date: 2026-10-15
tags:
  - redis
  - caching
  - backend
  - consistency
  - interview
aliases:
  - redis caching
  - cache penetration
  - cache avalanche
  - cache breakdown
  - 缓存穿透
  - 缓存雪崩
  - 缓存击穿
  - cache aside
  - cache consistency
  - delayed double delete
---
**Redis caching patterns** cover the three classic cache-miss failure modes (penetration, avalanche, breakdown) and how to keep the cache consistent with the database. The standard read/write strategy is **Cache Aside**, and cache↔DB consistency is **eventual**, not strong.

## The three failure modes (the confusable trio)

| Term | What goes wrong | Scale | Data exists in DB? |
| --- | --- | --- | --- |
| **穿透 Penetration** | requests for data that **doesn't exist** → miss cache *and* DB every time | many *different* bad keys | **No** |
| **雪崩 Avalanche** | **many** keys expire at once (or Redis is down) → flood to DB | many keys | yes |
| **击穿 Breakdown** | **one hot** key expires → concurrent requests stampede the DB for it | **one** key | yes |

### 穿透 Penetration — nonexistent data

Requests for keys that aren't in the DB at all (so never cached) hit the DB every time. Often **malicious** (attacker hammers `id=-1`, random UUIDs) or a bug. The cache can't help because there's nothing to cache.

- **Fix 1 — cache the null result** with a short TTL. When a query misses *both* cache and DB, store a null sentinel so repeats hit the cache:
  ```
  SET product:-99999 "<NULL>" EX 60     # short TTL (30–60s)
  ```
  The next request for that key hits the sentinel → return "not found", no DB touch. Short TTL because the data might get created later, and to cap memory. **Weakness:** an attacker spraying *many distinct* invalid keys fills Redis with null entries — which is why the bloom filter is stronger for that case.
- **Fix 2 — bloom filter** built from all **valid** keys (loaded at startup, each new key added on insert). On a request: **not in the filter → definitely invalid → reject** without touching cache/DB; **in the filter → probably valid → proceed**. The error is one-sided: **false positives** let a few invalid keys through, but **never false negatives** (it never rejects a valid key). You track valid keys, not invalid ones.
- Fix 3 — input validation / rate-limit suspicious patterns.

### 雪崩 Avalanche — mass expiry or Redis down

Many keys expire simultaneously, or Redis itself fails, so a wave of traffic falls through to the DB at once.

- **Fix 1 — jittered TTLs:** add a random spread so keys don't expire together.
- **Fix 2 — Redis HA** (cluster/sentinel) so Redis doesn't go fully down.
- **Fix 3 — circuit breaker / rate limiting / degradation** to shield the DB; multi-level cache (local + Redis).

### 击穿 Breakdown — one hot key expires

A single popular key that *does* exist expires, and a burst of concurrent requests for that one key all miss and stampede the DB to rebuild it. Differs from avalanche: **one key, not many.**

- **Fix 1 — mutex / [[Distributed Lock|distributed lock]]:** only the first request rebuilds the key; others wait or get a stale value.
- **Fix 2 — logical expiration:** never physically expire; store a logical-expiry field; when logically expired, one request triggers an async rebuild while others return the old value.
- **Fix 3 — never-expire / pre-warm hot keys** (needs knowing the hot keys ahead of time).

Logical expiration in detail: the value has **no Redis TTL** and carries a `logicalExpireAt` field. On read:
```
value = GET key
if now < value.logicalExpireAt:        # fresh
    return value
else:                                   # logically expired
    if tryLock(mutex):                  # exactly ONE request wins the lock
        spawn async: rebuild from DB, SET new value + new logicalExpireAt, unlock
    return value                        # STALE value returned immediately, lock winner or not
```
Exactly one request triggers the background rebuild; everyone (including that one) returns the old value right away — no stampede, no blocking. Tradeoff: readers see slightly stale data during the rebuild window.

## Cache ↔ DB consistency: Cache Aside (旁路缓存)

The standard strategy:

- **Read:** cache hit → return; **miss** → read DB → write cache → return.
- **Write:** **update the DB first, then DELETE the cache** (not update it).

Two rules and their reasons:

1. **Delete, don't update** the cache on write — avoids interleaved concurrent writes caching stale values, is lazy (re-cache only on next read), and handles computed/derived cache values.
2. **DB first, then delete** — if you delete cache *first* then update DB, a concurrent read in the gap re-caches the **old** DB value, and it persists for the whole TTL.

**The race that remains** (even with DB-then-delete):

```
Reader: cache miss → reads OLD from DB ............→ writes OLD to cache
Writer:         updates DB to NEW → deletes cache
                                    (then reader's stale write lands) → cache stuck on OLD
```

Mitigations:
- **延迟双删 (delayed double delete):** delete cache → update DB → wait a short delay → **delete cache again**, evicting anything a concurrent reader re-populated.
- **TTL as a backstop** → stale entries self-heal → **eventual consistency**.
- **Subscribe to MySQL binlog (Canal)** to invalidate the cache reliably, decoupled from app writes.

> Cache + DB is **eventual consistency**. Strong consistency needs locking/transactions, which defeats the point of a cache. Write = update DB then delete cache (Cache Aside); use delayed double delete + TTL to bound staleness.

## Interview summary

> Three cache-miss failures: penetration (data that doesn't exist anywhere → every request hits the DB; fix with cached nulls + a bloom filter), avalanche (many keys expire at once or Redis is down → fix with jittered TTLs, HA, circuit breakers), and breakdown (one hot key expires and concurrent requests stampede the DB → fix with a mutex/distributed lock, logical expiration, or never-expiring hot keys). For cache↔DB consistency use Cache Aside: read-through on miss, and on write update the DB then delete (not update) the cache, DB-first; a race can still cache a stale value, mitigated by delayed double delete, a TTL backstop, or binlog-driven invalidation (Canal). Consistency is eventual, not strong.

## Related notes

- [[Distributed Lock]]
- [[Transactions and Isolation Levels]]
- [[MVCC and Locking]]
- [[Hash Map]]
- [[Retry Backoff and Jitter]]
