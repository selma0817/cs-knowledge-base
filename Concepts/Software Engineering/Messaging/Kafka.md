---
date: 2026-09-15
aliases:
  - Kafka
  - Apache Kafka
  - topic
  - partition
  - offset
  - consumer group
  - ISR
  - in-sync replicas
  - log-based messaging
  - event streaming
  - KRaft
tags:
  - messaging
  - kafka
  - streaming
  - distributed-systems
  - interview
topic: messaging
---
**Apache Kafka** is a distributed, append-only **commit log** for high-throughput event streaming. It is best understood as the design opposite of [[Message Brokers and RabbitMQ]]: a **dumb broker + smart consumer**, where messages are **retained and replayable** rather than deleted on consumption.

## The defining difference: log, not queue

RabbitMQ **deletes** a message once a consumer acks it. Kafka **appends** messages to an immutable log and keeps them per a **retention policy**, independent of consumption:

- **Time/size retention** — keep messages for e.g. 7 days or 50 GB/partition, then delete old segments.
- **Log compaction** — alternatively keep only the latest message per key ("current state" topics).

A message can be read by many consumers and still remain until retention expires. This enables Kafka's superpower: **replay** — reset an offset and re-read history (reprocessing after a bug fix, bootstrapping a new consumer, event sourcing).

## Topics, partitions, offsets

- **Topic** — a named stream of one kind of event (e.g. `orders`). Different message *types* → different *topics*.
- **Partition** — a **shard of a topic**. A topic is split into N partitions; each message goes to **exactly one** partition (partitions *divide* messages, they do not copy them). Each partition is an ordered, append-only sequence.
- **Offset** — a monotonic position (0,1,2,…) within a partition. The consumer's bookmark.

```
Topic "orders", 4 partitions (12 orders DIVIDED across them, no duplication):
  Partition 0: [o1][o5][o9]     ← ordered, append-only
  Partition 1: [o2][o6][o10]
  Partition 2: [o3][o7][o11]
  Partition 3: [o4][o8][o12]
```

**Ordering is guaranteed only within a partition, never across a topic.** To order related events (e.g. one user's), publish with a **key** (`user_id`) → same key hashes to the same partition → ordered for that key. No key → round-robin (no per-entity order).

## Partitioning gives parallelism *and* ordering

Within a consumer group each partition is read by **exactly one** consumer, which reads the log sequentially — that single-reader rule is what preserves order. So parallelism scales by **adding partitions**, not readers per partition.

```
Topic "transactions" keyed by user_id:
  Partition 0: [X:deposit][X:withdraw] → consumer A  (user X in order ✅)
  Partition 1: [Y:...]                 → consumer B  (parallel with A)
```

This is the crucial contrast with RabbitMQ: many competing consumers on one queue give parallelism but **lose ordering** (messages interleave). Kafka's partition is *both* the unit of ordering *and* the unit of parallelism — ordered per key, parallel across keys. Consequence: **max useful consumers in a group = partition count** (extras sit idle).

## Consumer groups: competing consumers + fanout unified

- **Within a group** — partitions are divided among consumers; each message is processed **once** by the group (= RabbitMQ competing consumers).
- **Across groups** — each group gets its **own full copy** of the stream at its own offsets (= RabbitMQ fanout).

```
Topic "orders"
   ├── group "billing"   → all orders, split among its consumers, each once
   └── group "analytics" → all orders again, independent offsets (its own copy)
```

Offsets are committed per **group per partition** into an internal topic `__consumer_offsets`, so a restarted consumer resumes where it left off — while still being free to rewind.

> Partitions **divide** messages for parallelism (no duplication); consumer groups **copy** the stream for independent readers. Copies happen across groups, never across partitions.

## Pull, not push

Kafka consumers **pull** (`poll()`) batches from the log. This gives natural **backpressure** (a slow consumer polls slower), efficient **batching**, trivial **replay** ("read from offset X"), and a **dumb broker** that just serves byte ranges and tracks one committed offset per group per partition — no per-message delivery state.

## Durability & HA: leader + ISR (not Raft for data)

Each partition has a **replication factor** (e.g. 3): one **leader** replica (handles all reads/writes) and **followers** on other brokers that fetch from it. The **ISR (In-Sync Replicas)** is the set of replicas caught up with the leader.

Producer `acks` knob:

| `acks` | Waits for | Durability |
| --- | --- | --- |
| `0` | nothing | fastest, can lose data |
| `1` | leader write | lost if leader dies before followers copy |
| `all` (`-1`) | **all in-sync replicas** | strongest; with `min.insync.replicas=2`, survives broker loss |

**Key distinction from RabbitMQ:** RabbitMQ quorum queues use **Raft (majority commit)** for the messages. Kafka replicates partition data via **leader + ISR** — `acks=all` waits for **all in-sync replicas**, and a **controller** elects new leaders from the ISR. Raft appears in Kafka only as **KRaft**, governing **cluster metadata/controller election** (replacing ZooKeeper since 3.x) — *not* message replication.

### Durability = replication, not fsync

Kafka does **not** fsync each message on the write path. It writes to the **OS page cache** and returns; durability comes from **replicating to multiple brokers**, not from forcing to disk on one machine:

```
Producer (acks=all), replication factor 3:
  1. Leader writes to its PAGE CACHE (not fsync'd)
  2. ISR followers fetch it → write to THEIR page caches
  3. All in-sync replicas have it → leader acks the producer
  → the message lives in the memory of 3 independent machines
```

The bet: all replicas will not crash simultaneously before the OS lazily flushes, so **N independent copies** provide durability. This is *why* Kafka is fast — it avoids fsync on the hot path. Contrast with **database WAL / RabbitMQ persistent messages**, which achieve *single-node* durability by **fsync to disk**; Kafka swaps that for *multi-node* durability via replication.

A **changelog topic** (stream state) is durable for the *same* reason — it is a normal replicated Kafka topic, not a separate fsync-based store.

Caveats: fsync *is* configurable (`log.flush.interval.*`) but usually left to the OS; spread replicas across **racks/AZs** so they do not lose power together; and set `unclean.leader.election.enable=false` so a stale out-of-sync replica cannot become leader and lose acknowledged data.

> RabbitMQ/DB: "durable = on disk (fsync)." Kafka: "durable = on multiple machines (replication)." `acks=all` + `min.insync.replicas` acknowledges once enough in-sync replicas hold it in page cache.

## Why Kafka is fast

Sequential append-only disk I/O, the OS **page cache** (no app-level cache), **zero-copy** (`sendfile`) from disk to network, and heavy **batching + compression**. Optimized for throughput over per-message latency.

## Delivery semantics

Default is **at-least-once**: a consumer commits its offset *after* processing, so a crash between processing and commit causes **reprocessing** → **duplicates** → consumers must be **idempotent** (same dedup-key-in-transaction pattern as [[Message Delivery Guarantees and Reliability]]). Committing *before* processing gives **at-most-once** (risk of loss). Kafka offers **exactly-once semantics (EOS)** via an idempotent producer + transactions, but only for **Kafka-to-Kafka** read-process-write; external side effects still require idempotent consumers.

## Kafka vs RabbitMQ

| | **RabbitMQ** | **Kafka** |
| --- | --- | --- |
| Model | queue (delete on ack) | append-only **log** (retain + replay) |
| Broker/consumer | smart broker, dumb consumer | dumb broker, smart consumer |
| Delivery | broker **pushes** | consumer **pulls** |
| Position tracking | broker tracks acks/unacked | consumer-managed **offset** |
| Ordering | none across competing consumers | **per partition** (per key) |
| Parallelism | many consumers per queue (flexible) | = partition count (planned) |
| Routing | rich (direct/topic/headers/fanout) | by partition key; routing in the consumer |
| Replication | quorum queues = **Raft** (majority) | **leader + ISR**, `acks=all` |
| Replay | no (gone after ack) | **yes** (offset reset) |
| Throughput | lower, low latency | very high |
| Best for | task queues, complex routing, RPC, low latency | event streaming, replay, high volume, per-key ordering, many independent consumers |

## Interview summary

> Kafka is a distributed append-only commit log for event streaming. A topic is split into partitions that divide messages for parallelism; ordering holds only within a partition, so a key pins related events to one partition (ordered per key, parallel across keys). Messages are retained by policy (not deleted on read), and consumers track their own offset, enabling replay. Consumer groups unify competing consumers (partitions divided within a group, each message once) and fanout (each group its own copy). Consumers pull for backpressure/batching, keeping the broker dumb. Partitions are replicated via leader + ISR (acks=all waits for all in-sync replicas; Raft/KRaft only governs metadata). Default at-least-once forces idempotent consumers. Choose Kafka for high-throughput, replayable, ordered-per-key streams with many consumers; choose RabbitMQ for flexible routing, task queues, and low-latency per-message work.

## Related notes

- [[Message Brokers and RabbitMQ]]
- [[Message Delivery Guarantees and Reliability]]
- [[Raft Log Replication and AppendEntries]]
- [[Idempotency]]
- [[Hash Map]]
