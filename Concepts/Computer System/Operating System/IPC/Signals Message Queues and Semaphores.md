---
title: Signals Message Queues and Semaphores
aliases:
  - signals
  - message queue IPC
  - semaphore IPC
  - IPC mechanisms
  - 进程间通信的方式
  - process communication methods
created: 2026-09-15
tags:
  - computer-system/operating-system
  - ipc
  - signals
  - semaphore
  - interview
summary: The three IPC mechanisms beyond pipes/sockets/shared-memory — signals, message queues, semaphores — plus the complete list of ways processes communicate.
---

# Signals, Message Queues, and Semaphores

Companion to [[Interprocess Communication Pipes and Sockets]], covering the IPC mechanisms it leaves thin: **signals** (async notification), **message queues** (discrete messages), and **semaphores** (cross-process coordination). Together these complete the answer to "进程间通信的方式 / list the ways processes communicate."

## Signals — asynchronous notification, no data

A **signal** is a **software interrupt** delivered to a process, identified only by a **number** (`SIGTERM`=15, `SIGKILL`=9, `SIGINT`=2 from Ctrl+C, `SIGUSR1/2` user-defined). It carries **no data payload** — it is a notification, not a data channel.

`kill pid` is misnamed: it **sends a signal** (default `SIGTERM`), it does not inherently terminate. On receiving a signal a process can:
1. **run a custom handler** (e.g. catch `SIGTERM` to flush and shut down gracefully),
2. **take the default action** (terminate / ignore / stop / core-dump), or
3. **ignore** it — except `SIGKILL` and `SIGSTOP`, which cannot be caught or ignored.

**Use for:** lightweight async control/notification — reload config (`SIGHUP`), graceful shutdown (`SIGTERM`), child exited (`SIGCHLD`), custom events (`SIGUSR1/2`).
**Advantages:** no channel/buffer setup (just need the pid); interrupts the target asynchronously wherever it is.
**Limits:** no payload, small fixed set, and standard signals **do not queue** — duplicates can coalesce. (Real-time signals via `sigqueue` can carry a small value and do queue.)

> A signal is an async, payload-free notification identified by a number. `kill` *sends* a signal; the process handles it, ignores it, or takes the default. For control/notification, not data.

## Message queues — discrete, typed messages

A **message queue** is a kernel-held queue of **discrete messages**. Its defining differences from a **pipe** (a byte stream):

- **Message boundaries preserved.** A pipe merges writes ("hello"+"world" may read as "hellow"); a message queue delivers **whole messages**, never merged.
- **Typed / prioritized, selective receive.** System V queues tag messages with a *type* and let you receive **by type** (out of order); POSIX queues support **priorities**. A pipe is strictly FIFO bytes.
- **Kernel persistence / decoupled lifetimes.** Messages stay in the queue until read, **even if the sender exits** (until the queue is removed). A pipe's data is gone once the ends close.

APIs: System V (`msgget`/`msgsnd`/`msgrcv`) and POSIX (`mq_open`/`mq_send`/`mq_receive`).

> A pipe is an unstructured byte stream; a message queue preserves discrete, optionally typed/prioritized messages that persist in the kernel until read.

## Semaphores — cross-process coordination

A **semaphore** is a kernel-held **integer counter** with two atomic operations:

- **`wait`** (P / `down` / `sem_wait`): **decrement**; if it would go below 0, **block** until positive. "Consume a unit; wait if none."
- **`post`** (V / `up` / `sem_post`): **increment**; if a process is blocked, **wake one**. "Produce a unit; wake a waiter."

It transfers **no data** — it **coordinates**. Two properties matter:

- **Counting** — initialize to N to allow N concurrent accessors (a mutex is strictly 1).
- **No ownership** — the kernel records no "who waited," so **any process can `post`**, not just the one that `wait`ed. This is what a mutex (which has an owner: locker unlocks) cannot do, and it is exactly what enables **cross-process signaling**.

**Paired with shared memory.** Shared memory transfers data fast (no copying) but has **no built-in synchronization** — concurrent access races. A semaphore supplies the missing coordination.

### Producer–consumer over shared memory

```
empty = N   ← counts FREE slots     full = 0   ← counts FILLED slots
mutex = 1   ← binary, protects the buffer's internal pointers

Producer:                         Consumer:
  wait(empty)                       wait(full)
  wait(mutex); put item; post(mutex)   wait(mutex); take item; post(mutex)
  post(full)   // "+1 item!"           post(empty)  // "+1 free slot!"
```

The key moment: the producer's **`post(full)` wakes a consumer blocked in `wait(full)`** — a *different* process posts than the one that waits. That cross-process wakeup is the no-ownership property doing real work; a mutex cannot signal across actors like this. `empty`/`full` do signaling + backpressure; the binary `mutex` does mutual exclusion on the buffer.

> A semaphore is an owner-free kernel counter: `wait` decrements/blocks, `post` increments/wakes. Because any process may `post`, a producer can wake a consumer — the signaling a mutex can't do. It carries no data, so it pairs with shared memory (fast but unsynchronized) to coordinate access. See [[Semaphore]] and [[Mutex]].

## The complete list: 进程间通信的方式

| Mechanism | Data or coordination? | Defining trait | Scope |
| --- | --- | --- | --- |
| Anonymous pipe | data | byte stream, ephemeral, related processes | same machine |
| Named pipe (FIFO) | data | byte stream via a pathname, unrelated processes | same machine |
| Message queue | data | discrete typed/prioritized messages, kernel-persistent | same machine |
| Shared memory | data | fastest (no copy), **needs external synchronization** | same machine |
| Socket (Unix domain) | data | full-duplex byte stream, client-server | same machine |
| Socket (TCP/UDP) | data | works **across machines** | local or network |
| **Signal** | notification | async software interrupt, no payload, pid-addressed | same machine |
| **Semaphore** | coordination | owner-free counter; pairs with shared memory | same machine |

Details on pipes/sockets/shared memory: [[Interprocess Communication Pipes and Sockets]] and [[Unix Domain Sockets]].

## Interview summary

> Beyond pipes, sockets, and shared memory, processes communicate via signals, message queues, and semaphores. A signal is an async, payload-free software interrupt identified by a number (kill *sends* one; the process handles/ignores/defaults, except SIGKILL/SIGSTOP) — good for control/notification, not data. A message queue holds discrete, optionally typed/prioritized messages that preserve boundaries (unlike a pipe's byte stream) and persist in the kernel until read. A semaphore is an owner-free counter (wait decrements/blocks, post increments/wakes) used for coordination, not data; because any process can post, it enables cross-process signaling a mutex can't, and it pairs with shared memory (fast but unsynchronized) — e.g. producer–consumer uses counting semaphores for signaling/backpressure and a binary one for mutual exclusion.

## Related notes

- [[Interprocess Communication MOC]]
- [[Interprocess Communication Pipes and Sockets]]
- [[Unix Domain Sockets]]
- [[Semaphore]]
- [[Mutex]]
- [[Process vs Thread vs Coroutine]]
