---
title: RPC HTTP and Serialization
aliases:
  - Transport Protocol and Serialization
  - RPC Layering
created: 2026-08-01
tags:
  - software-engineering/api-design
  - rpc
  - http
  - serialization
summary: Transport moves bytes, HTTP structures HTTP exchanges, RPC models remote method calls, serialization turns values into bytes, and application code gives those values domain meaning.
---

# RPC HTTP and Serialization

## Responsibilities are composable

Several technologies can participate in one request without doing the same job.

| Concern | Example technology | Responsibility |
|---|---|---|
| Communication channel | TCP or Unix-domain socket | Connect endpoints and transport bytes |
| Application protocol | HTTP | Define HTTP requests, responses, headers, status, and framing |
| Remote-call model | Go `net/rpc`, JSON-RPC, gRPC | Identify operations, match replies, dispatch calls, represent errors |
| Serialization | gob, JSON, Protobuf | Encode values as bytes and decode bytes as values |
| Domain logic | MapReduce master and worker | Define what a map task, reduce task, or completion report means |

These are responsibilities, not a rigid rule that every system must contain five separate software layers.

## HTTP and RPC are not interchangeable

HTTP is a specific application-layer protocol. RPC is a remote-call programming model implemented by many protocols and frameworks.

RPC can use HTTP:

```text
gRPC over HTTP/2 over TCP
JSON-RPC over HTTP over TCP
```

RPC can also operate without HTTP:

```text
Go net/rpc directly over a TCP connection
custom RPC directly over a Unix socket
```

HTTP can operate without RPC:

```text
browser requests an HTML page
client downloads an image
REST-style resource request
```

Therefore, RPC and HTTP are sometimes composed, but they are not inherently the same level or permanently stacked in one fixed order.

## Serialization is not the whole protocol

Serialization answers:

> How does this value become bytes, and how do those bytes become a value again?

RPC must additionally handle questions such as:

- Which method is being called?
- Which arguments belong to it?
- Which response belongs to which request?
- Did the remote method return an error?
- How is the method dispatched on the server?

In Go `net/rpc`, gob is the default codec. `net/rpc` owns the remote-call structure; gob encodes that structure and its values.

## The MIT MapReduce lab stack

The worker executes:

```go
c, err := rpc.DialHTTP("unix", sockname)
err = c.Call("Master.RequestTask", &args, &reply)
```

The connection lifecycle is:

```text
1. Establish a Unix-domain stream-socket connection
2. Send an HTTP CONNECT request to the registered RPC HTTP endpoint
3. HTTP hands the established connection to Go net/rpc
4. net/rpc exchanges gob-encoded RPC requests and replies
5. MapReduce methods interpret task-specific values
```

After the HTTP handshake, each RPC call is not a separate conventional HTTP request such as `POST /request-task`. The connection carries the RPC codec’s stream.

## Reply matching

If one persistent `rpc.Client` has several outstanding calls, `net/rpc` uses sequence numbers:

```text
request 10 → RequestTask
request 11 → ReportTaskDone

response 11 arrives first → delivered to ReportTaskDone caller
response 10 arrives later → delivered to RequestTask caller
```

Sequence numbers need to be unique within that RPC client’s conversation, not globally across all workers.

## Distinguishing failures by layer

| Failure | Likely layer |
|---|---|
| Socket path exists but no server listens | Connection/IPC layer |
| `Master.NonexistentMethod` | RPC method dispatch |
| Bytes cannot be decoded into expected values | Serialization/codec layer |
| `RequestTask` returns “wait” | MapReduce application logic |
| Concurrent handlers assign the same task | Shared-state synchronization bug |

A transport failure during a call can be ambiguous: the server may have executed the operation even if the client did not receive the reply. Safe retries may therefore require idempotent operations, request IDs, or deduplication.

## Related notes

- [[REST API]]
- [[gRPC]]
- [[HTTP2]]
- [[TCP and Sockets]]
- [[Unix Domain Sockets]]
- [[Byte Streams and Message Framing]]
- [[Go net-rpc over Unix Domain Sockets]]

