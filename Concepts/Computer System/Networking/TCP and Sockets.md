---
title: TCP and Sockets
aliases:
  - TCP
  - Socket
  - TCP Connection
  - TCP Byte Stream
  - 4-Tuple
tags:
  - networking
  - tcp
  - sockets
  - transport-layer
  - interview
created: 2026-07-10
updated: 2026-07-10
status: seedling
---

# TCP and Sockets

TCP provides a reliable, ordered byte stream between two socket endpoints.

It sits below application protocols such as HTTP, Redis protocol, PostgreSQL protocol, and gRPC.

## What TCP provides

TCP handles:

- retransmission of lost packets
- ordering
- duplicate removal
- flow control
- congestion control

But TCP does **not** guarantee:

- the server application processed the request
- the database transaction committed
- the HTTP response reached the client
- message boundaries are preserved

Interview sentence:

> TCP gives applications a reliable ordered byte stream, not application-level success.

## TCP connection 4-tuple

A TCP connection is identified by:

```text
source IP
source port
destination IP
destination port
```

Example:

```text
192.168.1.23:53122 -> 142.250.190.14:443
```

Two connections can share the same destination port if their source IP or source port differs.

## Socket

A socket is an operating system abstraction used by a process to send and receive network data.

A server often has:

```text
one listening socket
many connected sockets
```

Example:

```text
Listening socket:
  0.0.0.0:8080

Connected sockets:
  1.1.1.1:50001 -> 10.0.0.5:8080
  2.2.2.2:50002 -> 10.0.0.5:8080
```

## Many clients, one server port

A server can accept many clients on the same server port because each connection has a different 4-tuple.

The server port identifies the service. The 4-tuple identifies the individual connection.

## TCP has no message boundaries

If a client writes:

```text
write("hello")
write("world")
```

the server may read:

```text
"helloworld"
```

or:

```text
"hel"
"lowor"
"ld"
```

TCP preserves byte order, not application message boundaries.

Application protocols define framing. For HTTP, a header like:

```http
Content-Length: 18
```

tells the server how many bytes belong to the body.

## HTTP keep-alive

One TCP connection can carry multiple HTTP requests over time.

Without keep-alive:

```text
TCP handshake
HTTP request/response
TCP close

TCP handshake
HTTP request/response
TCP close
```

With keep-alive:

```text
TCP handshake
HTTP request/response
HTTP request/response
HTTP request/response
TCP close later
```

## Timeout and POST

If `POST /orders` times out, the server may still have created the order. Retrying can create duplicates unless the API uses an idempotency key.

See [[REST API]] and [[Network Debugging Ladder]].

## Related

- [[UDP]]
- [[TLS and HTTPS]]
- [[Internet Request Lifecycle]]
- [[IP Address vs Port]]
