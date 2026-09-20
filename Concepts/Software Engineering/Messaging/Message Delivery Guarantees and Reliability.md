---
date: 2026-09-15
aliases:
  - delivery guarantees
  - at-least-once
  - at-most-once
  - exactly-once
  - publisher confirms
  - consumer ack
  - idempotent consumer
  - dead letter queue
  - DLQ
  - poison message
tags:
  - messaging
  - reliability
  - idempotency
  - distributed-systems
  - interview
topic: messaging
---
**Delivery guarantees** describe how hard a message broker tries to deliver each message exactly once. The practical truth: **exactly-once *delivery* is impossible; you build at-least-once delivery plus idempotent consumers to get exactly-once *effect*.** These concepts are broker-agnostic (RabbitMQ, Kafka, SQS) — see [[Message Brokers and RabbitMQ]] for the concrete model.

## The three guarantees

- **At-most-once** — a message is delivered zero or one time. Fast, but a crash mid-processing **loses** the message.
- **At-least-once** — a message is delivered one or more times. No loss, but **duplicates are possible**.
- **Exactly-once (delivery)** — the ideal, but **unattainable end-to-end** in a distributed system: the crash can always fall in the gap between doing the work and confirming it.

The reliability chain is only as strong as its weakest link. Each hop needs its own safety feature:

```
Producer ─[publisher confirm]─► Exchange ─► [durable queue + persistent msg] ─► [consumer ack] ─► done
   │                                              │                                 │
   └ no confirm → undetected loss                 └ not durable → lost on restart   └ auto-ack + crash → lost
```

## Consumer acknowledgements (the consumer→broker side)

The broker holds a delivered message as **unacknowledged** until the consumer confirms it. If the consumer's channel drops before acking, the broker **redelivers** it. Three modes:

| Mode | Behavior | Guarantee |
| --- | --- | --- |
| **auto-ack** | done the instant it is sent | **at-most-once** — crash mid-work → lost |
| **manual ack** (after processing) | ack only after success | **at-least-once** — crash before ack → redelivered |
| **nack / reject** | negative ack → requeue or dead-letter | for failures not to be retried blindly |

`prefetch_count` (QoS) caps how many unacked messages one consumer holds, giving **fair dispatch** and backpressure.

## Publisher confirms (the broker→producer side)

Symmetric to consumer acks. By default publishing is fire-and-forget, so a broker crash right after publish loses the message silently. With **publisher confirms** enabled, the broker sends the producer a `basic.ack` once it has **taken responsibility** — routed to all queues and (for persistent messages) **written to disk** — or a `basic.nack` on failure, and the producer **re-publishes** unconfirmed messages.

```
Consumer side:  consumer ──ack──►  broker    ("I processed it")
Producer side:  broker   ──ack──► producer   ("I safely stored it")
```

## Durability requirement

For a message to survive a broker restart, **all** must hold: a **durable queue**, a **persistent message**, and a **publisher confirm** (so the producer knows it was persisted, not lost in the RAM-before-disk window). Persistence stays fast via sequential append-only writes and batched fsync (group commit); quorum queues additionally require a **majority of nodes** to persist (Raft) before confirming.

## Idempotent consumers: turning at-least-once into exactly-once effect

Because redelivery can run a side effect twice (e.g. **double-charging a card**), consumers must be **idempotent**. The standard pattern: record a **unique message id in the same transaction as the side effect**, so a duplicate fails the unique-key insert and is safely skipped.

```sql
BEGIN;
  INSERT INTO processed_messages (msg_id) VALUES ('abc-123');  -- PK / UNIQUE
  UPDATE accounts SET balance = balance - 100 WHERE id = 42;   -- the effect
COMMIT;
-- redelivery → duplicate-key violation → rollback → consumer just acks and skips
```

This leans on [[Transactions and Isolation Levels]] and [[MVCC and Locking]] — the **unique constraint + atomic transaction** is what makes it safe under concurrent redelivery. Conceptually it is [[Compare-and-Swap]] / [[Idempotency]]: the unique key is the compare, the row is the swap, the duplicate-key error is CAS returning `false`. For external effects (payments), pass an **idempotency key** so the provider dedupes on their side.

## Dead-letter queues and retry

A **poison message** (malformed, or permanently failing) that is nacked-with-requeue loops forever and clogs the queue. A **dead-letter exchange (DLX)** routes a message to a **dead-letter queue** when it is rejected with `requeue=false`, **expires** (TTL), or the queue **overflows** a length limit. Production pattern: a **retry count** in headers + **TTL-based delayed re-injection** with **exponential backoff** (see [[Retry Backoff and Jitter]]); after N attempts the message goes to a **parking-lot DLQ** for a human. This isolates bad messages from the healthy pipeline.

## The exactly-once myth

> Exactly-once **delivery** cannot be guaranteed (the crash-between-work-and-ack gap). Systems provide **at-least-once delivery + idempotent consumers = exactly-once effect** ("effectively-once"). Even Kafka's "exactly-once semantics" is internal to Kafka; end-to-end with external side effects still requires consumer idempotency.

## Interview summary

> Brokers offer at-most-once (fast, may lose), at-least-once (safe, may duplicate), or the unattainable exactly-once delivery. Reliability is a chain: publisher confirms guard producer→broker, durable queues plus persistent messages guard broker restarts, and manual consumer acks (with redelivery on failure) guard broker→consumer — break any link and messages are lost. Because at-least-once means duplicates, consumers must be idempotent, typically by recording a unique message id in the same transaction as the side effect so redeliveries are skipped. Poison messages are shunted to a dead-letter queue with bounded retries and backoff. Exactly-once delivery is a myth; at-least-once plus idempotency yields exactly-once effect.

## Related notes

- [[Message Brokers and RabbitMQ]]
- [[Idempotency]]
- [[Transactions and Isolation Levels]]
- [[MVCC and Locking]]
- [[Compare-and-Swap]]
- [[Retry Backoff and Jitter]]
