---
title: Interprocess Communication MOC
aliases:
  - IPC MOC
created: 2026-08-01
tags:
  - moc
  - computer-system/operating-system
  - ipc
summary: Map of concepts for local process communication, socket behavior, byte streams, and higher-level protocols.
---

# Interprocess Communication MOC

## Foundations

- [[Interprocess Communication Pipes and Sockets]] — comparison of pipes, FIFOs, Unix sockets, TCP sockets, UDP, and shared memory
- [[Signals Message Queues and Semaphores]] — signals, message queues, semaphores, and the complete "进程间通信的方式" list
- [[File Descriptors and Kernel IO Objects]] — why files, pipes, and sockets share an interface without having the same semantics
- [[Concurrency vs Parallelism]] — concurrent execution and shared-state reasoning

## Socket behavior

- [[Unix Domain Sockets]] — pathname, listener, accepted connections, lifecycle, and stale socket entries
- [[TCP and Sockets]] — network sockets and TCP behavior
- [[Duplex Communication]] — simplex, half-duplex, full-duplex, and half-close
- [[Byte Streams and Message Framing]] — why stream reads do not reproduce write boundaries

## Higher-level protocols

- [[RPC HTTP and Serialization]] — separate transport, HTTP, RPC, codecs, and application meaning
- [[REST API]]
- [[gRPC]]
- [[HTTP2]]

## Practical case study

- [[Go net-rpc over Unix Domain Sockets]] — the MIT 6.824 MapReduce worker–master stack
- [[Goroutines and Channels]]

## Concept path

```text
process isolation
    ↓
IPC mechanism
    ↓
connected byte channel
    ↓
message framing and serialization
    ↓
RPC or another application protocol
    ↓
application behavior
```

