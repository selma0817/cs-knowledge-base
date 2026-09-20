---
title: Interprocess Communication Pipes and Sockets
aliases:
  - IPC Pipes and Sockets
created: 2026-08-01
tags:
  - computer-system/operating-system
  - ipc
  - sockets
summary: Pipes, FIFOs, Unix sockets, TCP sockets, and shared memory are different kernel-supported ways for processes to exchange data.
---

# Interprocess Communication Pipes and Sockets

## What is IPC?

Processes normally have separate virtual address spaces. **Interprocess communication (IPC)** mechanisms let them exchange data or coordinate through kernel-managed resources.

Common choices include pipes, FIFOs, Unix-domain sockets, network sockets, shared memory, signals, and message queues.

## Comparison

| Mechanism | Scope | Address or discovery | Direction and data model | Common use |
|---|---|---|---|---|
| Anonymous pipe | Same machine | Inherited file descriptors | Normally one-way byte stream | Shell pipelines; parent and child |
| Named pipe (FIFO) | Same machine | Filesystem pathname | Byte stream, commonly used one-way | Simple communication between unrelated processes |
| Unix-domain stream socket | Same machine | Pathname or abstract address | Full-duplex byte stream | Local client-server services |
| TCP socket | Same or different machines | IP address and port | Full-duplex ordered byte stream | Network services |
| UDP socket | Same or different machines | IP address and port | Discrete datagrams | Low-latency or message-oriented network traffic |
| Shared memory | Same machine | Shared-memory identifier or mapped object | Processes access the same memory | High-throughput local data sharing |

Shared memory avoids copying every exchange through a byte stream, but the processes must separately coordinate concurrent access with mechanisms such as mutexes, semaphores, or atomics.

## Anonymous pipe

The shell command:

```bash
cat story.txt | grep apple
```

approximately creates this arrangement:

```text
cat stdout  ── pipe ──>  grep stdin
```

The shell creates the pipe before launching the processes and gives each process the appropriate file descriptor. Neither program needs to locate the other by a public address.

## Why a Unix socket suits MapReduce workers

A MapReduce worker may start independently from the master. Both programs compute the same pathname:

```text
/var/tmp/824-mr-<UID>
```

The master binds and listens there. Each worker connects there. The pathname gives unrelated processes an agreed service address, and the listening socket supports multiple client connections.

A pipe would require the launcher to create and distribute pipe descriptors, and an ordinary pipe is only one-way. A Unix socket naturally provides the client-server model:

```text
bind → listen → connect → accept → exchange bytes
```

## IPC mechanism versus protocol

An IPC mechanism transports data. It does not automatically define what the bytes mean.

```text
Unix socket     → local byte channel
HTTP            → application message protocol
RPC             → remote-call structure and dispatch
gob             → Go-value serialization
MapReduce       → task meaning and behavior
```

RPC is not an alternative kernel IPC primitive. It is a higher-level communication model implemented over an underlying channel such as a Unix socket or TCP connection.

## File descriptors unify the interface

Pipes and sockets are exposed through file descriptors, so programs can use familiar operations such as `read()`, `write()`, and `close()`. This shared interface does not make them regular files:

- they do not store data in ordinary filesystem blocks;
- they are generally not seekable;
- their bytes live temporarily in kernel communication buffers;
- socket-specific operations include `bind()`, `listen()`, `connect()`, and `accept()`.

See [[File Descriptors and Kernel IO Objects]].

## Related notes

- [[Interprocess Communication MOC]]
- [[Signals Message Queues and Semaphores]]
- [[Unix Domain Sockets]]
- [[Duplex Communication]]
- [[File Descriptors and Kernel IO Objects]]
- [[TCP and Sockets]]
- [[Concurrency vs Parallelism]]

