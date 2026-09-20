---
date: 2026-09-15
aliases:
  - transaction
  - ACID
  - isolation levels
  - read committed
  - repeatable read
  - serializable
  - dirty read
  - non-repeatable read
  - phantom read
  - WAL
  - write-ahead logging
---
A **transaction** is a unit of work (delimited by `BEGIN` … `COMMIT`/`ROLLBACK`) that the database executes with **ACID** guarantees. Isolation levels define how concurrent transactions may interfere, trading correctness against concurrency.

## ACID

- **Atomicity** — all statements in the transaction commit, or none do (rollback undoes partial work).
- **Consistency** — the transaction moves the database from one *valid* state to another, respecting constraints.
- **Isolation** — concurrent transactions do not see each other's uncommitted, inconsistent intermediate states.
- **Durability** — once committed, changes survive a crash.

**Consistency is the odd letter out.** "Valid" is largely defined by the **schema and application** (foreign keys, unique/check constraints, business rules); the engine enforces the constraints you declare, so C is more a *consequence* of A + I + D + your rules than an independent engine mechanism. Note that **MVCC implements Isolation, not Consistency** — a common conflation. See [[MVCC and Locking]].

## Durability via Write-Ahead Logging (WAL)

Writing changes to the actual (random) table pages on every commit would be slow. Instead databases use **WAL** — "log before data":

```
On COMMIT:
  1. Append the change to a SEQUENTIAL log and fsync THAT.   ← fast: sequential I/O
  2. Return success to the client.
  3. Dirty data pages stay in RAM; flushed to data files later (a CHECKPOINT).
On CRASH:
  Replay the log to redo committed changes not yet in the data files.
```

Sequential append + one fsync is far cheaper than fsync-ing scattered random pages.

- **InnoDB:** this durability log is the **redo log** (roll *forward*). InnoDB also keeps an **undo log** for rollback + MVCC (roll *backward*) — a different log, do not confuse them. A **doublewrite buffer** guards against torn pages.
- **Postgres:** the log is simply the **WAL**.

> Two InnoDB logs: **redo** = durability/crash recovery; **undo** = rollback + old-version reconstruction for MVCC.

## The four isolation levels and three anomalies

Weakest to strongest: **Read Uncommitted → Read Committed → Repeatable Read → Serializable.** Each rules out one more anomaly:

- **Dirty read** — read a row another transaction modified but has **not committed**; if it rolls back, you read data that never existed.
- **Non-repeatable read** — read a row, another transaction **updates that same row and commits**, you read it again → a **different value for the same row**.
- **Phantom read** — run a **range/predicate query**, another transaction **inserts a new row matching the predicate** and commits, you re-run → **the set of matching rows changed** (a row appeared).

The distinction that interviewers probe: **non-repeatable read = an existing row's *value* changes; phantom = the *set of rows* matching a predicate changes.**

| Anomaly | Read Uncommitted | Read Committed | Repeatable Read | Serializable |
| --- | --- | --- | --- | --- |
| Dirty read | possible | prevented | prevented | prevented |
| Non-repeatable read | possible | possible | prevented | prevented |
| Phantom read | possible | possible | prevented* | prevented |

`*` By the SQL standard, only Serializable prevents phantoms, but **InnoDB's Repeatable Read prevents them too** via next-key/gap locks, and Postgres RR (true snapshot isolation) avoids them via snapshots. See [[MVCC and Locking]].

## Defaults (MySQL vs Postgres)

- **InnoDB (MySQL) default: Repeatable Read.**
- **Postgres default: Read Committed.**

This difference alone changes application behavior between the two databases and is a frequent interview "gotcha."

## Serializable: two philosophies

- **InnoDB Serializable** — **pessimistic**: turns plain `SELECT` into a locking read, so conflicts **block** (and can **deadlock**, `ERROR 1213` → retry).
- **Postgres Serializable** — **optimistic (SSI, Serializable Snapshot Isolation)**: runs on snapshots and **aborts** a transaction on a dangerous read-write dependency (`SQLSTATE 40001`) → the **application must catch it and retry**.

> Either way, production code at high isolation needs a **retry loop** — for deadlocks (InnoDB) or serialization failures (Postgres).

## Interview summary

> A transaction gives ACID: atomicity (all-or-nothing), consistency (valid states, mostly the app's/schema's job), isolation (concurrency control), durability (survives crashes via Write-Ahead Logging — InnoDB's redo log / Postgres's WAL, which log sequentially before flushing random data pages). Isolation levels from Read Uncommitted to Serializable each prevent one more anomaly: dirty read (an uncommitted value), non-repeatable read (a row's value changes), phantom read (the set of rows matching a predicate changes). InnoDB defaults to Repeatable Read (and prevents phantoms via gap locks); Postgres defaults to Read Committed. Serializable is pessimistic in InnoDB (locks, blocks, deadlocks) and optimistic in Postgres (SSI aborts with 40001), so high-isolation code needs a retry loop.

## Related notes

- [[MVCC and Locking]]
- [[Database Indexing]]
- [[Compare-and-Swap]]
- [[Mutex]]
