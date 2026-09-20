---
date: 2026-09-15
aliases:
  - MySQL storage engines
  - InnoDB
  - MyISAM
  - Memory engine
  - HEAP engine
  - storage engine
---
A **MySQL storage engine** is the pluggable component that actually stores rows, builds indexes, and handles locking and transactions. The same SQL runs on any engine, but their guarantees differ sharply. **InnoDB** is the default (since MySQL 5.5) and the engine all of [[Transactions and Isolation Levels]] and [[MVCC and Locking]] describes.

## Comparison

| Feature | **InnoDB** | **MyISAM** | **Memory (HEAP)** |
| --- | --- | --- | --- |
| Transactions (ACID) | ✅ Yes | ❌ No | ❌ No |
| Locking granularity | **Row-level** | **Table-level** | **Table-level** |
| MVCC | ✅ Yes | ❌ No | ❌ No |
| Foreign keys | ✅ Yes | ❌ No | ❌ No |
| Crash recovery | ✅ Yes (redo/undo logs) | ❌ No (corrupt → manual repair) | N/A (volatile) |
| Clustered index | ✅ table *is* a [[B+ Tree]] on PK | ❌ data in a heap; indexes point to it | Hash index by default |
| Caching | Buffer pool caches data + indexes | Key cache caches **only** indexes | Entirely in **RAM** |

So beyond row-level locking, **InnoDB uniquely adds: transactions, MVCC, foreign keys, crash recovery, and clustered indexes.**

## InnoDB — the general-purpose OLTP engine

Row-level locking + MVCC give high write concurrency; redo/undo logs make it crash-safe; it supports foreign keys and clustered indexes. Every behavior in the transaction and MVCC notes (snapshots, gap locks, undo-log versioning) is InnoDB behavior. Default choice for essentially all real applications.

## MyISAM — legacy, read-heavy

- **Table-level locking:** a single write locks the **entire table**, so writes have no concurrency. Suits **read-mostly/read-only** workloads.
- **No transactions, no foreign keys, not crash-safe** (a crash can corrupt tables, needing `REPAIR TABLE`).
- **Non-clustered:** rows live in a heap (`.MYD`); indexes (`.MYI`) point at row offsets.
- **O(1) `COUNT(*)`:** MyISAM stores an exact row count as table metadata, so `SELECT COUNT(*)` with no `WHERE` is instant — whereas **InnoDB must scan**, because under MVCC different transactions can see different row counts, so no single stored count is correct. (A direct consequence of versioning.)

## Memory (HEAP) — volatile and fast

- **All data in RAM:** very fast, but **lost on restart** (only the table definition survives).
- **Table-level locking; no transactions.**
- **Default index is a HASH** — great for equality (`=`), useless for range/`ORDER BY` scans (see [[Hash Map]] vs [[B+ Tree]]); a `BTREE` index can be requested.
- No `BLOB`/`TEXT`; fixed-length rows. Used for small lookup/temp tables.

## How engine choices echo other concepts

- MyISAM's O(1) `COUNT(*)` vs InnoDB's scan is a **direct consequence of MVCC** — versioning means there is no single row count true for all transactions.
- Memory's default **hash index** cannot serve range queries — the exact [[Hash Map]] vs [[B+ Tree]] trade-off in practice.
- Table-level (MyISAM/Memory) vs row-level + gap locks (InnoDB) is why only InnoDB supports the concurrency discussed in [[MVCC and Locking]].

## Interview summary

> A MySQL storage engine implements storage, indexing, locking, and transactions beneath the shared SQL layer. InnoDB (the default) is the general-purpose OLTP engine: row-level locking, MVCC, ACID transactions, foreign keys, crash recovery via redo/undo logs, and clustered indexes. MyISAM uses table-level locking (poor write concurrency), has no transactions/FK/crash recovery, is non-clustered, but keeps an O(1) COUNT(*) via stored metadata (which InnoDB can't, because MVCC gives each transaction its own row count). Memory keeps everything in RAM (fast but volatile), table-locked, no transactions, hash-indexed by default. In short, everything the transaction and MVCC notes describe exists because we use InnoDB.

## Related notes

- [[Transactions and Isolation Levels]]
- [[MVCC and Locking]]
- [[Database Indexing]]
- [[B+ Tree]]
- [[Hash Map]]
