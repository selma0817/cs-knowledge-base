---
title: Byte Streams and Message Framing
aliases:
  - Stream Boundaries
  - Message Framing
created: 2026-08-01
tags:
  - computer-system/networking
  - sockets
  - protocols
summary: TCP and Unix stream sockets preserve byte order but not the boundaries of individual write calls, so higher-level protocols must frame messages.
---

# Byte Streams and Message Framing

## A stream is continuous bytes

TCP sockets and Unix-domain `SOCK_STREAM` sockets provide an ordered byte stream.

Suppose a sender performs:

```text
write("REQUEST_ONE")
write("REQUEST_TWO")
```

The receiver must not assume that two `read()` calls will reproduce those two writes. It might observe:

```text
read 1: "REQUEST_ONE"
read 2: "REQUEST_TWO"
```

but it could also observe:

```text
read 1: "REQUEST_ONEREQUEST_TWO"
```

or:

```text
read 1: "REQU"
read 2: "EST_ONEREQ"
read 3: "UEST_TWO"
```

The guarantees are:

- successfully transmitted bytes remain in order;
- bytes are not duplicated by the stream transport;
- the transport does **not** preserve the boundaries between `write()` calls.

## Why read boundaries differ from write boundaries

The kernel moves bytes through buffers. A `read()` returns some number of currently available bytes, up to the requested buffer size. Buffering, scheduling, congestion, and timing can combine writes or split one write across multiple reads.

This is normal stream behavior, not necessarily a failure.

## Message framing

An application protocol needs a rule for determining where one logical message ends and the next begins.

| Framing method | Example | Main concern |
|---|---|---|
| Fixed size | Every record is 64 bytes | Inflexible or wasteful for variable data |
| Delimiter | Each message ends with `\n` | Delimiter must be forbidden or escaped inside data |
| Length prefix | `11` followed by 11 body bytes | Must validate lengths and incomplete input |
| Self-describing encoding | Decoder recognizes a complete structured value | Depends on the encoding and decoder |

A newline protocol is ambiguous if unescaped newlines are permitted inside a message:

```text
hello\nworld\n
```

The protocol must define whether this is one message or two.

## HTTP framing

HTTP defines boundaries for HTTP messages and bodies. For example, in HTTP/1.1:

```http
POST /message HTTP/1.1
Content-Length: 11

hello
world
```

The blank line separates headers from the body. `Content-Length: 11` instructs the parser to read all 11 body bytes, so the newline inside the body is ordinary data.

HTTP/1.1 can also use chunked transfer encoding. HTTP/2 uses length-bearing binary frames.

HTTP frames the HTTP message, but the body can contain another format such as JSON, Protobuf, an image, or plain text.

## RPC and serialization framing

In Go’s `net/rpc`:

- `net/rpc` organizes requests, replies, method names, sequence numbers, and errors;
- `gob` encodes and decodes the Go values;
- the stream socket carries the resulting bytes.

The MapReduce methods therefore do not manually reconstruct messages from arbitrary socket reads.

## Stream closure is not ordinary message framing

End-of-file tells the receiver that no more bytes will arrive in that direction. A protocol can use one connection per message and treat EOF as the end, but this prevents multiple messages from sharing a persistent connection.

Persistent protocols need framing that works before the connection closes.

## Stream sockets versus datagram sockets

| Stream socket | Datagram socket |
|---|---|
| Continuous ordered bytes | Discrete messages |
| Does not preserve write boundaries | Preserves datagram boundaries |
| Application must frame messages | Each receive corresponds to a datagram, subject to buffer size |
| TCP and Unix `SOCK_STREAM` | UDP and Unix `SOCK_DGRAM` |

Preserving message boundaries does not by itself guarantee reliable delivery. UDP preserves datagram boundaries but does not guarantee delivery, order, or uniqueness.

## Related notes

- [[Duplex Communication]]
- [[Unix Domain Sockets]]
- [[TCP and Sockets]]
- [[UDP]]
- [[HTTP2]]
- [[RPC HTTP and Serialization]]

