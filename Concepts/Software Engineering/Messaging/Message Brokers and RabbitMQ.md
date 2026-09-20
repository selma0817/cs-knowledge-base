---
date: 2026-09-15
aliases:
  - message queue
  - message broker
  - RabbitMQ
  - exchange
  - AMQP
  - fanout
  - quorum queue
tags:
  - messaging
  - rabbitmq
  - amqp
  - distributed-systems
  - interview
topic: messaging
---
A **message broker** is middleware that sits between producers and consumers so work can be sent **asynchronously** instead of via direct synchronous calls. **RabbitMQ** is a broker that speaks **AMQP** and routes messages through **exchanges** to **queues**.

## Why a message queue exists

Consider a "Place Order" endpoint that must charge payment, send email, update inventory, and notify shipping. Doing all four **synchronously** inline means: the user waits for the sum of all latencies, and if any downstream (e.g. shipping) is **down for 10 minutes**, orders **block or fail** for 10 minutes.

Putting a queue between the endpoint and the work gives three wins:

- **Asynchrony / lower latency** — the endpoint drops a message and returns immediately; workers do the slow tasks later.
- **Decoupling & failure isolation** — a down consumer doesn't fail the request; its messages wait in the queue and are retried when it recovers.
- **Load leveling (buffering)** — a spike of 10k orders/s is absorbed by the queue and fed to a 500/s downstream at its sustainable rate, so the system **degrades gracefully** instead of collapsing.

## Tradeoffs (what you give up)

Async messaging is not free — naming these separates a senior answer from "queues are great":

- **Eventual consistency** — the response is now a *promise*, not a completed fact; permanent failures need **compensating actions**.
- **Duplicates → idempotency required** — delivery is at-least-once, so consumers must be idempotent (see [[Message Delivery Guarantees and Reliability]]).
- **Ordering not guaranteed** across parallel consumers.
- **Harder debugging/observability** — failures happen "later, in a worker"; need correlation IDs and tracing.
- **Operational complexity** — the broker is now critical HA infrastructure.
- **Unbounded backlog risk** — load leveling survives *spikes*, not a permanent capacity deficit.

## The RabbitMQ model

RabbitMQ is a long-running **broker process** (written in Erlang) listening on **port 5672** for AMQP (and 15672 for its management UI). Producers publish to an **exchange**, which routes to **queues**, which consumers subscribe to.

```
                     ┌──────────── RabbitMQ broker ────────────┐
 Producer ─publish─► │  EXCHANGE ─binding─► QUEUE ─┐            │
 (never to a queue)  │     │      (routing key)     │            │
                     │     └─binding─► QUEUE ─┐     │            │
                     └────────────────────────┼─────┼───────────┘
                                              │     │
                                  Consumer ◄──┘     └──► Consumer
```

| Term | Role |
| --- | --- |
| **Producer** | Publishes a message — always to an **exchange**, never directly to a queue. |
| **Exchange** | Stateless **router**; decides which queue(s) a message goes to. Stores nothing. |
| **Queue** | Buffer holding messages until consumed. Stores messages. |
| **Binding** | Rule linking an exchange to a queue (often with a routing-key pattern). |
| **Consumer** | Subscribes to a queue; the broker **pushes** messages to it. |

**Why an exchange (decoupling).** Producers publish an event once and know **nothing** about consumers. New consumers subscribe by **binding a new queue** — the producer code never changes. A **fanout** exchange copies one `OrderPlaced` into email/shipping/inventory/payment queues; adding a fraud-detection consumer later needs zero producer changes. This is publish/subscribe decoupling.

**Exchange types:** **direct** (exact routing-key match), **fanout** (broadcast to all bound queues), **topic** (routing-key pattern like `order.*.us`), **headers** (match on header attributes).

### Fanout vs direct vs competing consumers (a common interview trap)

The confusion is "route different messages to different queues" (that is **direct**) vs "copy one message to all queues" (that is **fanout**). The tell is **how many times the producer publishes**:

- **Fanout** — the producer calls `publish()` **once** with one event; RabbitMQ **copies** it into every bound queue. The producer knows nothing about the consumers. Adding a new consumer = bind a new queue, producer untouched.
  ```
  publish("OrderPlaced{user,item,card}")  →  copied to payment / email / inventory / shipping queues
  each worker reads the SAME message but uses only the fields it needs (different jobs)
  ```
- **Direct** — the producer publishes **N typed messages**, each routed to its one matching queue by exact key. The producer must know the tasks and address each.
  ```
  publish("charge", key="payment"); publish("email", key="email"); ...   (N in → N out, 1 each)
  ```
- **Competing consumers (work queue)** — one message → **one queue** → many *identical* workers, and each message is handled by **exactly one** of them (scale a single task horizontally). This is orthogonal and composes with fanout.

| Concept | One-liner |
| --- | --- |
| Fanout | 1 publish → copied to **all** bound queues (producer ignorant of consumers) |
| Direct | route each message to the queue matching its **exact key** |
| Competing consumers | many workers on **one** queue → each message handled **once** |

> Copies across queues = more *distinct* reactions to one event (fanout). Workers within a queue = more parallelism for *one* reaction (competing consumers). "Route different messages to different queues" is direct/topic, not fanout.

## Transport: AMQP over TCP + channels

Clients open **one long-lived TCP connection** and multiplex lightweight **channels** inside it (so no TCP handshake per thread — same idea as HTTP/2 streams; see [[Networking Layers Protocols Connections Sockets and Channels]]). A consumer subscribes once (`basic.consume`) and the broker **pushes** deliveries over that open channel; the consumer sends `basic.ack` back. It is asynchronous message-passing, not RPC (though an RPC *pattern* can be built with a reply-to queue + correlation id).

## Storage and durability performance

Messages live in **RAM** by default (lost on restart). Durability is opt-in and needs a **durable queue** + **persistent message** (`delivery_mode=2`) together. Persistence stays fast because the broker:

- Writes **sequentially / append-only** (the WAL principle — sequential I/O is far faster than random).
- Uses **batched fsync (group commit)** — one fsync per batch of messages, amortizing the expensive call; publisher confirms are sent only after the batch is fsynced.
- Keeps the **delivery hot path in RAM**; messages page to disk only when queues grow large.

## Clustering and high availability

A RabbitMQ **cluster** replicates metadata (exchanges, bindings) across all nodes. Queues are made HA with **quorum queues**, which replicate the message log using the **Raft consensus algorithm** (via Erlang's `ra` library) — a message is committed once a **majority of nodes persist it**, exactly the guarantee in [[Raft Log Replication and AppendEntries]]. (Older **classic mirrored queues** are deprecated; RabbitMQ uses Erlang's native clustering, **not** ZooKeeper.)

## Interview summary

> A message broker decouples producers from consumers so work happens asynchronously, buying lower latency, failure isolation, and load leveling — at the cost of eventual consistency, duplicates (needing idempotency), lost ordering, and operational complexity. RabbitMQ is an Erlang broker speaking AMQP over persistent TCP with multiplexed channels; producers publish to a stateless exchange that routes (direct/fanout/topic/headers) to queues, which push messages to subscribed consumers. The exchange indirection gives publish/subscribe decoupling — add consumers by binding queues without touching the producer. Durability needs a durable queue plus persistent messages, kept fast by sequential append-only writes and batched fsync; HA comes from quorum queues that replicate via Raft (majority commit).

## Related notes

- [[Message Delivery Guarantees and Reliability]]
- [[Networking Layers Protocols Connections Sockets and Channels]]
- [[Raft Log Replication and AppendEntries]]
- [[Idempotency]]
- [[gRPC]]
