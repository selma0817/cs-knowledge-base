---
title: Networking Layers Protocols Connections Sockets and Channels
aliases:
  - Networking Layers
  - Protocol vs Connection
  - Socket vs TCP
  - Channel Multiplexing
  - Layering
  - TCP vs RPC
tags:
  - networking
  - transport-layer
  - application-layer
  - sockets
  - interview
created: 2026-09-15
updated: 2026-09-15
status: seedling
---

# Networking Layers: Protocols, Connections, Sockets, and Channels

The terms *TCP*, *socket*, *protocol*, *channel*, and *RPC* are often confused because they live at **different layers**. Comparing them directly is a category error. Each layer carries bytes for the layer above and is oblivious to what those bytes mean.

## The stack, bottom to top

```
┌─────────────────────────────────────────────────────────────┐
│ PATTERN:      RPC, pub/sub messaging, request/response        │  a STYLE of interaction
├─────────────────────────────────────────────────────────────┤
│ APPLICATION:  HTTP, AMQP, RESP, gRPC-over-HTTP/2              │  what the bytes MEAN
│               (AMQP/HTTP2 add "channels"/"streams" here)      │
├─────────────────────────────────────────────────────────────┤
│ TRANSPORT:    TCP (reliable ordered byte stream) / UDP        │  moves BYTES reliably
│               accessed via a SOCKET (the OS handle)           │
├─────────────────────────────────────────────────────────────┤
│ NETWORK:      IP (addressing + routing)                       │  finds the machine
│               endpoint = IP:port  (e.g. 127.0.0.1:4332)       │
└─────────────────────────────────────────────────────────────┘
```

> Golden rule: each layer rides on the one below and does not understand the layers above. TCP moves bytes; it has no idea whether they are HTTP, AMQP, or an RPC call.

## Terms mapped to one analogy (a phone call)

| Term | Layer | Phone analogy |
| --- | --- | --- |
| IP address | Network | The building's street address |
| Port | Transport | The apartment/extension number |
| `IP:port` (127.0.0.1:4332) | — | One *endpoint* (a phone jack) — an address, **not** a connection |
| TCP connection | Transport | An open phone *line* between two endpoints — the **4-tuple** `(ip1,port1,ip2,port2)` |
| Socket | Transport (OS API) | The *handset* your program holds — a **file descriptor** |
| Protocol (HTTP/AMQP) | Application | The *language & etiquette* spoken on the line |
| Channel (AMQP) / stream (HTTP2) | Application | Several *separate conversations* multiplexed on the same line |
| RPC / messaging | Pattern | A *style* of conversation (ask-and-wait vs. leave-a-message) |

## TCP and the 4-tuple

A TCP **connection** is uniquely identified by the **4-tuple** `(src_ip, src_port, dst_ip, dst_port)`, which is how the kernel demultiplexes arriving packets to the right connection. TCP's rules provide a **reliable, ordered byte stream**:

- **Setup:** 3-way handshake (SYN → SYN-ACK → ACK).
- **Reliability:** sequence numbers + acknowledgments + retransmission of lost segments.
- **Ordering:** reassemble segments by sequence number.
- **Flow control:** sliding window (don't overwhelm a slow receiver).
- **Congestion control:** back off when the network is congested.
- **Teardown:** FIN/ACK.

See [[TCP and Sockets]] and [[IP Address vs Port]].

## Socket vs TCP: the kernel does TCP, the socket is your handle

TCP lives in the **kernel**; the **socket is your program's handle to it**.

```
YOUR PROGRAM (user space)
   write(fd, bytes)                read(fd, buf)
        │                               ▲
        ▼        SOCKET = file descriptor (the API boundary)
┌───────────────────────────────────────────────────────────┐
│ KERNEL TCP/IP STACK:                                        │
│  send buffer → segments → seq #s → IP packets → NIC         │
│  NIC → reassemble → recv buffer → hand bytes to read()      │
└───────────────────────────────────────────────────────────┘
```

You never touch TCP directly — you `write()`/`read()` a socket and the kernel speaks TCP on your behalf. **One connected TCP socket = one endpoint of one TCP connection.**

**Is a socket a file?** It is a **file descriptor** (hence Linux's "everything is a file" — you `read`/`write`/`close` it). But a **network (`AF_INET`) socket has no filesystem path**; it is an anonymous kernel object addressed by the 4-tuple. Only a **Unix domain socket** (`AF_UNIX`, for local IPC) has a path like `/var/run/docker.sock` — see [[Unix Domain Sockets]].

> A socket is always a file descriptor. A network socket has no path (addressed by IP:port); only a Unix domain socket has a filesystem path.

## Endpoint vs socket, and how one endpoint backs many sockets

An **endpoint** (a.k.a. **socket address**) is an `IP:port` pair — an *address*, e.g. `192.168.1.10:3306`. A **socket** is the kernel object **bound to** an endpoint. They are different: the word "socket" is overloaded — casual usage calls an `IP:port` a "socket," but that is the *socket-address* sense; the OS-resource socket is a distinct file descriptor.

Incoming data is **not** a single stream at an endpoint. It arrives as **packets, each carrying the full 4-tuple** `(src_ip, src_port, dst_ip, dst_port)`, and the kernel **demultiplexes** by the whole 4-tuple. So the same destination endpoint carries many independent connections, told apart by their source side.

Two socket roles:

- **Listening socket** — `socket()` → `bind(endpoint)` → `listen()`. Its **only** job is connection setup: it completes handshakes and hands you a new socket via `accept()`. It **never carries application data**.
- **Connected socket** — returned by `accept()`, **one per established 4-tuple**, carrying that connection's byte stream (`read()`/`write()`).

Concrete: MySQL server `192.168.1.10:3306` with three clients:

```
fd 3  LISTENING   local 192.168.1.10:3306                                  (setup only)
fd 4  CONNECTED   local 192.168.1.10:3306  remote 192.168.1.20:51000       client B stream
fd 5  CONNECTED   local 192.168.1.10:3306  remote 192.168.1.30:52000       client C stream
fd 6  CONNECTED   local 192.168.1.10:3306  remote 192.168.1.40:53000       client D stream
```

All four share the local endpoint `192.168.1.10:3306`, but each connected socket is distinct, keyed by its remote endpoint. Even two connections from the *same* client are separate sockets if their source ports differ (`51000` vs `51001`) — which is exactly how a connection pool holds many connections to one database endpoint.

> Endpoint = address; socket = the kernel object bound to it. A connection (4-tuple) maps 1:1 to one connected socket. One endpoint backs one listening socket plus one connected socket per 4-tuple — the kernel demultiplexes packets by the full 4-tuple, so "many sockets at one endpoint" means many separate streams, not many listeners on one stream.

## Bytes in, meaning out: protocols and framing

TCP delivers a **raw, ordered byte stream** with **no notion of message, request, or boundary**. The application reads those bytes and interprets them by whatever **application protocol both ends agreed to speak** (HTTP, AMQP, RESP). Consequences:

- **Both ends must agree on the protocol.** The port only *hints* by convention (80=HTTP, 443=HTTPS, 5672=AMQP, 6379=RESP); the bytes are what get decoded.
- **The protocol must define message boundaries — framing** — because TCP is a pure stream: a length prefix (AMQP frames), a delimiter (HTTP `\r\n\r\n`), or `Content-Length`. See [[Byte Streams and Message Framing]].

## Channels: multiplexing streams over one connection

Opening a TCP connection per thread/request is expensive (handshake + TLS each time). Application protocols avoid this by **multiplexing many logical streams over one connection**:

```
1 TCP connection (1 socket, 1 four-tuple)
   ├── AMQP channel 1   (a producer)
   ├── AMQP channel 2   (a consumer)
   └── AMQP channel 3   ...
```

- **AMQP channels** (RabbitMQ) and **HTTP/2 streams** (see [[HTTP2]]) are the same idea: cheap virtual connections inside one real TCP connection.
- A **channel is not a socket** — it is an application-layer construct layered on top of the socket.

## Persistent TCP vs RPC: orthogonal, different layers

- **Persistent TCP** — a *transport* choice: keep the connection open across many exchanges instead of reconnecting per request.
- **RPC** — an *application pattern*: call a remote function and wait for its return value.

You do RPC **over** a TCP connection, persistent or not. Example: **gRPC = RPC (pattern) over HTTP/2 (protocol) over persistent TCP (transport)**. Messaging (RabbitMQ) is a *different* pattern — fire-and-forget publish, not call-and-wait — over AMQP over TCP. See [[RPC HTTP and Serialization]] and [[gRPC]].

> "Persistent TCP" answers *how long the pipe stays open*; "RPC" answers *what interaction pattern flows through it*. They are independent.

## Interview summary

> Networking is layered: IP addresses/routes to a machine; TCP provides a reliable ordered byte stream between two endpoints identified by a 4-tuple; a socket is the file-descriptor handle your program uses to read/write that stream while the kernel implements TCP. TCP carries only bytes with no message boundaries, so an application protocol (HTTP, AMQP, RESP) — agreed by both ends — gives the bytes meaning and defines framing. Channels (AMQP) and streams (HTTP/2) multiplex many logical conversations over one TCP connection to avoid per-request handshakes. RPC and messaging are interaction *patterns* expressed over a protocol; "persistent TCP" is an orthogonal transport choice. A network socket is a file descriptor with no filesystem path (only Unix domain sockets have paths).

## Related notes

- [[TCP and Sockets]]
- [[IP Address vs Port]]
- [[Byte Streams and Message Framing]]
- [[RPC HTTP and Serialization]]
- [[HTTP2]]
- [[Unix Domain Sockets]]
- [[Networking MOC]]
