---
title: UDP
aliases:
  - User Datagram Protocol
  - UDP vs TCP
  - Datagram
  - QUIC
tags:
  - networking
  - udp
  - transport-layer
  - quic
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# UDP

UDP sends independent datagrams. It is a transport-layer protocol like [[TCP and Sockets|TCP]], but it provides fewer guarantees.

## What UDP does not provide

UDP does not provide built-in:

- connection setup
- delivery guarantee
- ordering
- retransmission
- duplicate removal
- flow control
- congestion control

It sends packet-sized messages called datagrams.

## Why use UDP?

UDP is useful when low latency or custom control matters more than built-in reliability.

Examples:

- video calls
- online games
- DNS
- QUIC / HTTP/3

## Real-time media

For video calls, late data is often less useful than missing data.

If an old video frame arrives too late, the application may prefer to drop it and continue with newer frames.

TCP's reliability can cause head-of-line blocking:

```text
packet 1 lost
packet 2 arrived
packet 3 arrived
TCP waits for packet 1 before delivering later bytes to the application
```

For real-time audio/video, this waiting can hurt latency.

## HTTP/3 and QUIC

HTTP/3 uses QUIC over UDP.

Important distinction:

```text
UDP itself is unreliable.
QUIC builds reliability, encryption, and stream multiplexing on top of UDP.
```

HTTP/3 does not mean web pages no longer need reliability. It means QUIC implements transport features in user space over UDP.

## Related

- [[TCP and Sockets]]
- [[HTTP2]]
- [[gRPC]]
- [[Internet Request Lifecycle]]
