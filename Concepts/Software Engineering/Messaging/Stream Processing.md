---
date: 2026-09-15
aliases:
  - stream processing
  - windowing
  - tumbling window
  - sliding window
  - session window
  - event time
  - processing time
  - watermark
  - late data
  - stateful stream processing
  - changelog topic
  - checkpointing
  - Kafka Streams
  - Flink
---
**Stream processing** computes continuously over an **unbounded** stream of events, as they arrive, rather than running a job over a bounded dataset. It is the computation side of the log-as-truth model: [[Event Sourcing and CQRS]] writes the log, stream processing reads it to build aggregates and projections, on top of [[Kafka]].

## Batch vs stream

| Batch | Stream |
| --- | --- |
| **Bounded** dataset (yesterday's 10M orders) | **Unbounded**, infinite stream |
| Runs periodically (a midnight job) | Runs **continuously** |
| High latency (hours) | **Low latency** (near real-time) |

## Windowing

An unbounded stream never "ends," so aggregates like "orders in the last 5 minutes" are computed over **windows** — bounded slices of the stream:

- **Tumbling** — fixed-size, **non-overlapping**; each event in exactly one window. `[10:00–10:05)[10:05–10:10)`. Use: "orders per 5-minute bucket."
- **Sliding (hopping)** — fixed-size, **overlapping**, advances by a smaller step; an event can fall in several windows. 5-min window every 1 min. Use: "orders in the *last* 5 minutes, updated each minute."
- **Session** — **dynamic** size, grouped by activity, closes after an inactivity gap. Use: "a user's browsing session."

```
Tumbling:  [___][___][___]     non-overlapping
Sliding:   [___]                overlapping, slides
             [___]
Session:   [__]   [____] [_]    gaps close windows
```

## Event time vs processing time, and watermarks

- **Event time** — when the event actually happened (a timestamp inside the event).
- **Processing time** — when the processor sees it.

Use **event time** for correctness: "revenue for 10:00–10:05" should count events that *happened* then, regardless of arrival. But this creates the **late/out-of-order** problem: an event that happened at 9:59 but arrives at 10:06 may reach a window that has already **closed and emitted**.

**Watermarks** solve this: a watermark asserts *"I believe I've seen all events up to time T."* The processor **waits for the watermark to pass a window's end before finalizing** it, giving stragglers a grace period. Events later than the watermark are **dropped**, sent to a **side output**, or trigger a **window update**. An **allowed lateness** keeps windows open slightly past their end.

> Event time is correct but requires waiting for late data (added latency); watermarks track completeness of time so windows finalize at the right moment. Processing time is simpler and lower-latency but wrong under delays.

## Stateful processing and fault tolerance

Aggregations ("revenue so far") are **stateful** — the processor keeps an accumulator across events in a **state store** (often an embedded **RocksDB**). Surviving crashes without losing or double-counting state:

- **Kafka Streams → changelog topics.** Every state update is also written to a **compacted changelog topic in Kafka**. On crash, a new instance **rebuilds state by replaying the changelog** — durability piggybacks on Kafka's own replicated, replayable log.
- **Flink → checkpointing.** Periodically snapshot the entire distributed state to durable storage (S3/HDFS) **together with input offsets**, and on failure restore the last checkpoint and **replay from the matching offsets**.

**Exactly-once processing** = atomically commit three things as one unit: **advance the input offset + update the state + emit the output**. On failure all three rewind together, so no double-count. Kafka uses transactions (idempotent producer + transactional offset commit); Flink uses checkpoint barriers. As always, exactly-once holds *within* the streaming system; **external** side effects still need idempotency (see [[Message Delivery Guarantees and Reliability]]).

## Frameworks

- **Kafka Streams** — a library (not a cluster), tightly coupled to Kafka; state via changelog topics.
- **Apache Flink** — true event-time streaming, sophisticated windowing/state, checkpointing; often considered best-in-class.
- **Spark Structured Streaming** — micro-batch model (processes small batches frequently).

## Interview summary

> Stream processing runs continuously over an unbounded stream, emitting results with low latency, versus batch jobs over bounded data. Aggregates use windows — tumbling (non-overlapping), sliding (overlapping), or session (activity-gap). Correctness uses event time (when it happened) not processing time (when seen), which creates late/out-of-order data handled by watermarks that let windows wait for stragglers before finalizing. Stateful operations keep local state (RocksDB) made durable via Kafka changelog topics (Kafka Streams) or checkpoints (Flink), replaying from the last durable point on crash; exactly-once atomically commits input offset + state + output together, though external effects still need idempotency. Kafka Streams, Flink, and Spark Structured Streaming are the common engines.

## Related notes

- [[Event Sourcing and CQRS]]
- [[Kafka]]
- [[Message Delivery Guarantees and Reliability]]
- [[Idempotency]]
