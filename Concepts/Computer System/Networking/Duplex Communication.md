---
title: Duplex Communication
aliases:
  - Simplex Half-Duplex and Full-Duplex
created: 2026-08-01
tags:
  - computer-system/networking
  - ipc
  - sockets
summary: Duplex describes which directions data may flow through a communication channel and whether both directions may be active at the same time.
---

# Duplex Communication

## Core idea

**Duplex is a property of a communication channel, not a protocol layer by itself.** It describes the permitted direction of data flow.

| Mode | Permitted flow | Example mental model |
|---|---|---|
| Simplex | Only one direction | A broadcast-only channel |
| Half-duplex | Both directions, but not at the same time | Walkie-talkies taking turns |
| Full-duplex | Both directions at the same time | A phone call |

Full-duplex means that simultaneous sending and receiving are **allowed**. It does not mean both endpoints must always transmit simultaneously.

## Is duplex a Unix-socket feature?

A connected Unix-domain `SOCK_STREAM` socket is full-duplex:

```text
Process A  ───── bytes ─────>  Process B
Process A  <──── bytes ─────  Process B
```

Each endpoint can read and write. This differs from an ordinary anonymous pipe, which is normally one-way:

```text
Process A  ───── bytes ─────>  Process B
```

Two pipes can be combined to create two-way communication, but a connected socket already exposes both directions through one socket endpoint.

The duplex property matters mainly after a socket connection is established. A listening socket accepts new connections; application data travels through the connected sockets returned by `accept()`.

## What layer is duplex at?

There is no single universal “duplex layer.” The term can describe capabilities at several layers:

| Context | What duplex describes |
|---|---|
| Physical/link layer | Whether a medium or link can transmit in both directions simultaneously |
| Transport layer | TCP provides a full-duplex ordered byte stream |
| Operating-system IPC | A connected Unix-domain stream socket provides a full-duplex local byte stream |
| Application layer | Whether the application protocol permits or chooses simultaneous messages in both directions |

A Unix-domain socket is not formally a TCP/IP transport-layer protocol because it never uses IP or crosses machines. It is better described as a **local IPC mechanism that provides a transport-like service**.

## Channel capability versus application behavior

A full-duplex channel does not force the application to use both directions simultaneously.

For example, a simple RPC program may follow this pattern:

```text
Client sends request
Client waits
Server sends response
```

This is a turn-taking, request-response application pattern running over a full-duplex socket. The underlying socket would still allow the server to send data while the client is sending, if the higher-level protocol supported that behavior.

This distinction is important:

> The lower layer determines what communication is possible; the higher-level protocol determines how the application uses that capability.

## Half-closing a full-duplex connection

TCP and Unix-domain stream sockets can close only one direction with `shutdown()`.

```text
Process A calls shutdown(SHUT_WR)

A can no longer send ───────X──────> B
A can still receive <─────────────── B
```

After A’s already-buffered bytes are delivered, B observes end-of-file in that direction. A can continue reading B’s response. This is called a **half-close**.

Calling `close()` normally releases the endpoint entirely once no file descriptors refer to it.

## MapReduce example

The worker–master Unix socket is full-duplex:

```text
Worker ── RPC request bytes ──> Master
Worker <── RPC reply bytes ─── Master
```

The worker’s helper happens to use it in a request-then-response pattern and closes the connection after one RPC. That is an application design choice, not a limitation of Unix sockets.

## Common misconceptions

- **“Full-duplex means two connections.”** No. One connected socket has two directions.
- **“Full-duplex means messages have boundaries.”** No. A stream can be full-duplex and still expose only continuous bytes.
- **“Duplex belongs to HTTP.”** HTTP can define an application communication pattern, but the underlying TCP or Unix socket already has its own duplex capability.
- **“A full-duplex transport makes every protocol full-duplex.”** The application protocol may intentionally impose turn-taking.

## Related notes

- [[Unix Domain Sockets]]
- [[Byte Streams and Message Framing]]
- [[Interprocess Communication Pipes and Sockets]]
- [[TCP and Sockets]]
- [[RPC HTTP and Serialization]]

