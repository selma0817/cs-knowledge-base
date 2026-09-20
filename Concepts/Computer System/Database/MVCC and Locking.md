---
date: 2026-09-15
aliases:
  - MVCC
  - multi-version concurrency control
  - snapshot
  - read view
  - undo log
  - current read
  - consistent read
  - lost update
  - gap lock
  - next-key lock
  - record lock
  - VACUUM
  - optimistic locking
---
**MVCC (Multi-Version Concurrency Control)** lets readers see a consistent point-in-time snapshot without blocking writers, by keeping multiple versions of each row. Locks handle what MVCC does not: conflicts between concurrent *writers*. This note covers both and how InnoDB and Postgres differ.

## The promise of MVCC

> With MVCC, **readers don't block writers, and writers don't block readers.**

A reader is served a consistent **old version** instead of waiting on a lock. **Writers still block writers** on the same row (two conflicting writes must serialize). This is the boundary: **MVCC handles read visibility; locks handle write conflicts.**

## MVCC vs isolation: mechanism vs guarantee

These sit at different levels of abstraction — one is a goal, the other a tool:

```
ISOLATION (the "I" in ACID)          ← WHAT: the guarantee/contract
   defined by ISOLATION LEVELS           (which anomalies are allowed)
        │  implemented by
        ▼
MECHANISMS                            ← HOW: the implementation
   • MVCC             (consistent reads without locking)
   • Locking (2PL, row/gap locks)    (write conflicts & phantoms)
```

- **Isolation / isolation levels** are the **specification** — *what* must be true (e.g. "Repeatable Read forbids dirty and non-repeatable reads"). See [[Transactions and Isolation Levels]].
- **MVCC** is one **implementation technique** for that spec. Historically databases used **pure two-phase locking (2PL)** with no MVCC, but then readers blocked writers; MVCC was the improvement.

So neither is a subset of the other: **isolation is the contract; MVCC is part of the how.** MVCC alone cannot deliver every level — InnoDB combines **MVCC (reads) + row locks (writes) + gap locks (phantoms)** to realize Repeatable Read.

**What MVCC covers:** consistent snapshots for reads, visibility rules (which version each transaction sees), and version storage/reconstruction. **What it does not cover:** write-write conflicts (row locks) and phantom prevention in a range (gap/next-key locks).

> Isolation = the contract. MVCC covers the read side (reads and writes don't block each other); locking covers the write/phantom side. Together they realize an isolation level.

## A snapshot is a lens, not a copy

A snapshot is **not** a copy of the data — it is tiny metadata: essentially **a list of transaction IDs** describing who had committed at snapshot time. When you read a row, the engine uses that list to decide **which existing version you may see**, then fetches/reconstructs it.

- **InnoDB** calls it a **read view** (the set of active/uncommitted txn IDs at creation). A row version is visible if the txn that created it committed before the read view was made.
- **Postgres** stores a snapshot as `(xmin, xmax, xip_list)`.

The snapshot lives in the **server's memory, per transaction**. The actual versions live where each engine keeps them (below).

## Snapshot timing: RR vs RC

- **Repeatable Read:** one snapshot **per transaction**, created lazily at the **first consistent read** (first plain `SELECT`) — not at connect, not at `BEGIN` — then **reused** for the whole transaction. That is *why* reads are repeatable. (`START TRANSACTION WITH CONSISTENT SNAPSHOT` forces it at `BEGIN`.)
- **Read Committed:** a **fresh snapshot per statement**, so the same query can return different committed values within one transaction (non-repeatable read by design).

```
balance = 100
-- REPEATABLE READ                         -- READ COMMITTED
T1: BEGIN;                                  T1: BEGIN;
T1: SELECT balance; → 100  (freeze here)    T1: SELECT balance; → 100
T2: UPDATE=200; COMMIT;                     T2: UPDATE=200; COMMIT;
T1: SELECT balance; → 100  (frozen)         T1: SELECT balance; → 200  (fresh snapshot)
```

The data didn't move; **which version the snapshot's lens permits** is what differs.

## Where old versions physically live — InnoDB vs Postgres

This is the key implementation divergence.

**InnoDB — reconstructed from the undo log (out-of-table):**
```
Each clustered-index row has hidden columns:
  DB_TRX_ID   → id of the last txn that modified the row
  DB_ROLL_PTR → pointer to an undo-log record (previous version's delta)
To read an older version: follow DB_ROLL_PTR back through undo records,
applying reverse deltas, until reaching a version your read view may see.
```
The table holds only the **latest** row; older versions are **rebuilt on the fly**. The table stays compact.

**Postgres — versions stored in the heap (in-table):**
```
Each row version (tuple) has:  xmin (creating txn), xmax (superseding/deleting txn)
UPDATE = write a NEW tuple + set xmax on the old tuple; both sit in the heap.
A reader picks the tuple visible to its snapshot via xmin/xmax.
```

| | InnoDB (undo log) | Postgres (in-heap versions) |
| --- | --- | --- |
| Old versions | Reconstructed from undo log | Stored in the table heap |
| Table bloat | Low (compact) | High → needs **VACUUM** |
| Rollback | Replays undo (costly for big txns) | Cheap — mark txn aborted; vacuum cleans later |
| `UPDATE` cost | In-place + undo; secondary index touched only if its columns change | New tuple; **all** indexes updated (mitigated by **HOT** updates) |
| Long-running txn | Undo log / history list can't purge | Autovacuum can't reclaim visible-to-old-txn versions → bloat |

**Postgres VACUUM & XID wraparound:** dead tuples pile up → **table/index bloat**; **VACUUM** (via **autovacuum**) reclaims them. Because Postgres uses **32-bit transaction IDs**, un-vacuumed tables risk **transaction-ID wraparound**, where old rows appear "in the future" and vanish — so VACUUM also **freezes** old tuples, and Postgres will force-shut-down to protect data in the extreme. A **long-running transaction hurts both engines** — it pins versions neither can reclaim.

## Reads: consistent vs current

- **Consistent (snapshot) read** — a plain `SELECT` — reads from the MVCC snapshot, **no locks**.
- **Current read** — `UPDATE`, `DELETE`, `SELECT ... FOR UPDATE`, `SELECT ... FOR SHARE` — reads the **latest committed** version **and takes a lock**, **bypassing the snapshot**.

This is why an `UPDATE` at RR uses the freshest value even though the transaction's plain `SELECT`s see a frozen one.

## Lost update: MVCC's trap

Snapshots give consistent reads but **not** read-modify-write correctness:

```
balance = 100
T1: SELECT balance; → 100        T2: SELECT balance; → 100
T1: UPDATE = 150; COMMIT;        T2: UPDATE = 130; COMMIT;   → 130  ❌ T1's +50 lost
```

Three fixes:
1. **Atomic SQL** — `UPDATE ... SET balance = balance + 30` (the current read reads the latest under an X lock).
2. **Pessimistic lock** — `SELECT ... FOR UPDATE` takes the X lock at read time, so the other transaction blocks.
3. **Optimistic locking (a version column)** — database-level [[Compare-and-Swap]]:
   ```sql
   UPDATE t SET val = ?, version = version + 1 WHERE id = ? AND version = <read_version>;
   -- rows_affected = 0  →  someone else won  →  re-read and RETRY
   ```
   `WHERE version = v` is the compare, the update is the swap, `rows_affected = 0` is CAS returning `false`.

**Write-write divergence:** InnoDB RR **blocks** the second writer, then applies to the latest committed value (no error). Postgres RR **aborts** the second writer if the row changed since its snapshot (`could not serialize access`, `SQLSTATE 40001`) → app retries.

## Row, gap, and next-key locks

Locks attach to **index records**, not abstract rows:

- **Record lock** — locks one existing index record (e.g. `age = 20`).
- **Gap lock** — locks the **open interval between** existing records (e.g. `(20, 30)`). It locks **no existing row**; its only purpose is to **block `INSERT`s into that range** — which is how phantoms are prevented.
- **Next-key lock** — record + the gap before it (e.g. `(20, 30]`); InnoDB's default unit for a locking read at RR.

```
records 10, 20, 30 on an age index:
  gaps: (-∞,10)  (10,20)  (20,30)  (30,+∞)

T1: SELECT * FROM users WHERE age > 15 FOR UPDATE;   -- at Repeatable Read
    scan positions at first record > 15 (which is 20) and locks (10, +∞)
      insert age=5  → OK      (gap (-∞,10), not locked)
      insert age=12 → BLOCKS  ← 12 < 15 yet still blocks: gap locks snap to
                                existing-record boundaries, not the literal predicate
      insert age=25 → BLOCKS  (gap (20,30))
```

Properties:
1. Gap locks lock **space, not rows** — they only block inserts.
2. Gap locks **do not conflict with each other** — only with an `INSERT` entering the gap.
3. They exist only at **Repeatable Read and Serializable** (disabled at Read Committed → RC allows phantoms, less contention).
4. **Exact match on a UNIQUE index → record lock only** (at most one row, no phantom possible).
5. **No usable index → InnoDB gap-locks everything it scans → effectively locks the whole table.** A missing index widens locking dramatically. This is why *indexing and locking are the same machinery* — see [[Database Indexing]].

**Deadlock:** two transactions locking rows in opposite order form a cycle; InnoDB detects it and kills a victim (`ERROR 1213`) → retry. The fix is a consistent global lock order — same rule as in [[Mutex]].

## Interview summary

> MVCC lets readers see a consistent snapshot without blocking writers by keeping row versions; a snapshot is not a data copy but a set of transaction IDs used to pick a visible version. InnoDB reconstructs old versions from the undo log (compact table), while Postgres stores every version in the heap (needs VACUUM, risks XID wraparound); a long-running transaction bloats both. RR takes one snapshot per transaction at first read; RC takes one per statement. Plain SELECT is a snapshot read; UPDATE/DELETE/SELECT FOR UPDATE are current reads that see the latest committed row and lock it. Snapshots don't stop lost updates — fix with atomic SQL, SELECT FOR UPDATE, or an optimistic version column (database CAS). Phantoms are prevented by gap/next-key locks on the index, which lock empty ranges to block inserts, snap to existing-record boundaries (so they over-lock), and balloon to whole-table locks when no index exists.

## Related notes

- [[Transactions and Isolation Levels]]
- [[Database Indexing]]
- [[Compare-and-Swap]]
- [[Mutex]]
- [[B+ Tree]]
