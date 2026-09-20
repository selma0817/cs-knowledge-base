---
date: 2026-09-15
aliases:
  - event sourcing
  - CQRS
  - projection
  - materialized view
  - read model
  - write model
  - snapshot
  - event store
---
**Event sourcing** stores state as an **append-only log of immutable events** (the source of truth) instead of a mutable current-state row; current state is **derived** by folding the events. **CQRS** pairs with it by separating the write model (events) from query-optimized read models (projections). Both rest on the same log-as-truth idea as [[Kafka]] and [[Raft Log Replication and AppendEntries]].

## The paradigm shift: events, not state

Traditional CRUD stores current state and mutates it (`UPDATE balance = 80`). Event sourcing appends the **facts that changed it** and derives state on demand:

```
Events (source of truth):            Current state (derived fold):
  AccountOpened(balance=0)
  Deposited(+100)          ──fold──►    balance = 80
  Withdrew(-20)
```

State is a **left fold over the event log**. The events are the truth; state is a cached projection of them.

## What you gain

Overwriting `100` with `80` destroys information that event sourcing keeps:

- **Audit trail** — who did what, when, why (free compliance/history).
- **Time-travel / temporal queries** — "what was the balance on Jan 1?" = fold events up to that time.
- **Debugging** — replay the exact event sequence to reproduce a bug.
- **Rebuild new views** — derive a brand-new read model by replaying full history (e.g. backfill a fraud dashboard invented next year).
- **Event-driven integration** — other services subscribe to the event stream.

## What gets harder

- **Querying current state** — "all accounts with balance > $1000, sorted" is painful over a raw event log (→ CQRS below).
- **Replay cost** — reconstructing an aggregate means replaying its events (→ snapshots below).
- **Schema evolution** — an event written in 2024 has an old shape; you must read and replay it *forever*. Immutable history can't be `ALTER TABLE`d, so events are **versioned** and all versions handled indefinitely.
- **Complexity & eventual consistency** — more moving parts than a `balance` column.

## Snapshots

To avoid replaying millions of events, periodically persist the folded state (a **snapshot**), then reconstruct by loading the latest snapshot and replaying **only the events since it**. Turns "replay 10M events" into "load snapshot + replay 200." A snapshot is a **write/rebuild-side** optimization for **one** aggregate.

## CQRS: separate write and read models

The event log is great for **appending** but terrible for **querying**. **CQRS (Command Query Responsibility Segregation)** splits the two:

```
WRITE side (source of truth)              READ side (derived, disposable)
  command → event → append to log ──┐
                                    │  a PROJECTION consumes the events
                                    └─► and maintains a query-optimized store:
                                          accounts(id, balance)   ← SQL table / index / ES
                                        queries hit THIS, not the log
```

- The **event log is the write model** (append-only truth).
- A **projection** (materialized view / read model) is a **consumer that folds events into a query-optimized database**, shaped for the query (indexed, denormalized).
- You can build **many** projections from one log — balance queries, analytics, search — and **rebuild any of them by replaying** the log. Projections are derived and disposable; the log is the truth.

That projection — a consumer folding an event stream into a view — is exactly a **stream processor** (see [[Stream Processing]]).

**Snapshot vs projection** (do not conflate):

| Snapshot | Projection (CQRS read model) |
| --- | --- |
| Speeds up rebuilding **one** aggregate's state | A **queryable view across many** aggregates |
| Write/rebuild-side optimization | Read-side; serves queries |
| Same shape as the aggregate | Shaped for the query (indexes, denormalized) |

## Kafka as an event store

Kafka fits event sourcing naturally: topics are append-only logs, retention/**log compaction** can keep the latest event per key, and **consumer groups** build independent projections that can each **replay** from offset 0. The replayable, compacted log *is* the event store; stream processors *are* the projection builders.

## Interview summary

> Event sourcing stores immutable events as the source of truth and derives current state by folding them, instead of mutating a state row. It gains a full audit trail, time-travel, replay/debugging, and the ability to build new read models from history — at the cost of harder queries, replay expense, and permanent event schema-versioning. Snapshots avoid replaying an aggregate's whole history. Because the log is bad for queries, CQRS separates the write model (events) from read models (projections) — query-optimized views built by consuming the stream, rebuildable by replay, and distinct from snapshots. Kafka's replayable, compacted log is a natural event store, with stream processors building the projections.

## Related notes

- [[Stream Processing]]
- [[Kafka]]
- [[Raft Log Replication and AppendEntries]]
- [[Message Delivery Guarantees and Reliability]]
- [[Database Indexing]]
