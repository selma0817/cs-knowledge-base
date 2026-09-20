---
title: Go net-rpc over Unix Domain Sockets
aliases:
  - MIT 6.824 MapReduce RPC Stack
created: 2026-08-01
tags:
  - programming-languages/go
  - distributed-systems/mapreduce
  - rpc
  - ipc
summary: The MIT 6.824 MapReduce lab uses Go net/rpc and gob over an HTTP-established Unix-domain socket connection, with separate RPC handlers sharing synchronized master state.
---

# Go net-rpc over Unix Domain Sockets

## Stack

The MapReduce worker–master interaction can be read as:

```text
MapReduce task meaning
        ↓
Go net/rpc method dispatch and request/reply matching
        ↓
gob encoding of Go values
        ↓
Unix-domain stream socket carrying ordered bytes locally
```

`rpc.DialHTTP` adds an initial HTTP CONNECT handshake that transfers the established connection to the RPC handler.

## Server setup

The master conceptually performs:

```go
rpc.Register(m)
rpc.HandleHTTP()

sockname := masterSock()
os.Remove(sockname)
l, err := net.Listen("unix", sockname)
go http.Serve(l, nil)
```

The important steps are:

1. Register the `Master` value so `net/rpc` can dispatch exported methods.
2. Register the RPC HTTP handler.
3. Remove a potentially stale socket pathname.
4. Bind one listening Unix socket to the agreed pathname.
5. Accept and serve connections from many workers.

## Worker call lifecycle

A helper of this form creates one connection per RPC:

```go
func call(rpcname string, args interface{}, reply interface{}) bool {
    c, err := rpc.DialHTTP("unix", masterSock())
    if err != nil {
        return false
    }
    defer c.Close()

    return c.Call(rpcname, args, reply) == nil
}
```

Its lifecycle is:

```text
connect
  ↓
HTTP CONNECT handshake
  ↓
send one RPC request
  ↓
receive its reply
  ↓
close connected socket
```

`c.Call()` itself does not inherently require closing the connection. The helper’s `defer c.Close()` makes connection-per-call a choice of this implementation.

## One listener, many connections

```text
Master listening socket
├── accepted connection for Worker 1
├── accepted connection for Worker 2
└── accepted connection for Worker 3
```

The pathname locates the listener. Each accepted connection has its own connected socket endpoint on the master, paired with one worker endpoint.

## Connection isolation does not isolate master state

Separate workers use separate connections, but their RPC handlers access the same `Master` object:

```text
Worker 1 → RequestTask goroutine ─┐
                                  ├→ shared task table
Worker 2 → RequestTask goroutine ─┘
```

The task table therefore needs a mutex. The lock must protect the whole check-and-update decision:

```go
m.mu.Lock()

if task.Status == Available {
    task.Status = InProgress
    reply.Task = task
}

m.mu.Unlock()
```

Locking the read and write separately would leave a race between them.

## Lock scope

The master should release the mutex after it has atomically reserved the task and constructed the reply. It must not hold the lock while the worker performs the map or reduce computation.

```text
lock master state
find available task
mark task InProgress
copy assignment into reply
unlock master state
return reply

worker performs task without holding master lock
```

Otherwise, one slow worker would prevent the master from assigning independent tasks to other workers.

## Responsibility check

| Question | Component that answers it |
|---|---|
| Where is the local service? | Unix socket pathname |
| Which bytes belong to encoded values? | gob codec |
| Which method is requested? | Go `net/rpc` |
| What does `TaskMap` mean? | MapReduce application code |
| Can two task assignments race? | Master concurrency design and mutex |

## Related notes

- [[Unix Domain Sockets]]
- [[RPC HTTP and Serialization]]
- [[Byte Streams and Message Framing]]
- [[Duplex Communication]]
- [[Goroutines and Channels]]
- [[sync.WaitGroup]]
- [[Google File System]]

