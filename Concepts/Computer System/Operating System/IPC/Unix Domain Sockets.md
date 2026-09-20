---
title: Unix Domain Sockets
aliases:
  - Unix Sockets
  - Local Sockets
created: 2026-08-01
tags:
  - computer-system/operating-system
  - ipc
  - sockets
  - linux
summary: A Unix-domain socket is a local IPC endpoint; a pathname can name its listener through VFS while live communication remains in kernel socket objects and buffers.
---

# Unix Domain Sockets

## Purpose

A Unix-domain socket lets processes on the same machine communicate using the socket API without IP addresses or network routing.

The closest comparison is:

| Unix-domain stream socket | TCP socket |
|---|---|
| Local machine only | Can cross machines |
| Usually addressed by a filesystem path | Addressed by IP address and port |
| Uses local kernel IPC | Uses the TCP/IP stack |
| Ordered, reliable byte stream | Ordered, reliable byte stream |
| Full-duplex once connected | Full-duplex once connected |

## Pathname versus live socket

A pathname-based Unix socket has two related but distinct parts:

```text
Filesystem namespace                 Live kernel communication state
/var/tmp/824-mr-501                  listening/connected socket objects
directory entry + socket inode       queues, buffers, connection state
```

When the server calls `bind()`, Linux creates a special filesystem entry whose inode type is socket. VFS can perform pathname lookup, permission checks, `stat`, `chmod`, `chown`, and `unlink` on that entry.

The inode may expose metadata such as:

- inode number and socket type;
- owner UID and group GID;
- permission bits and link count;
- access, modification, and status-change timestamps.

The transmitted bytes are **not regular-file contents**. They live in kernel socket buffers associated with the live endpoints.

## Server and client lifecycle

The server normally performs:

```text
socket() → bind(path) → listen() → accept()
```

Each client performs:

```text
socket() → connect(path)
```

The pathname locates the listening socket. `accept()` creates a new connected server-side socket for that client while the listening socket remains available for more connections.

With two clients, the simplified object count is:

```text
Server:
  1 listening socket
  2 connected sockets, one per client

Client 1:
  1 connected socket

Client 2:
  1 connected socket
```

The workers do not search the process table to identify the master. They connect to whichever live listener is currently bound to the agreed pathname.

## One pathname can serve many clients

Normally, only one listener can bind a particular pathname at a time, but many clients can connect to that listener:

```text
                       /var/tmp/824-mr-501
                                │
                        listening socket
                         /       |       \
                    accept   accept   accept
                      /         |         \
                 Worker 1   Worker 2   Worker 3
```

Each established connection is one-to-one. The listener is the common entry point that creates those separate connections.

## Stale pathnames and unlinking

The filesystem entry is not proof that a server is alive.

If the server crashes:

```text
pathname may remain
live listener is gone
new connect() fails
```

A restarted server normally cannot bind the occupied stale pathname. Server startup code often does:

```go
os.Remove(sockname)
net.Listen("unix", sockname)
```

If a pathname is unlinked while existing clients remain connected:

- existing connections continue to work;
- the old listener is no longer reachable through that pathname;
- new clients cannot reach it by that name;
- a new server can bind a new socket at the now-free pathname.

An old client can therefore remain connected to the old server while a new client using the same pathname reaches a new server.

## Why `os.Open(path)` is not enough

The pathname participates in the filesystem namespace, but communication uses socket system calls and socket-specific handlers.

```text
os.Open(path)       → tries regular file-style opening
connect(socket,path) → connects a socket endpoint to the listener
```

A connected socket has no meaningful seek offset and cannot be treated as persistent file contents.

## Permissions are not complete authentication

Filesystem ownership and permission bits can restrict who may connect to a pathname socket. They do not by themselves prove that the listener is the intended application. A production protocol may also authenticate peers or inspect peer credentials.

The MapReduce lab trusts its pathname convention and local environment.

## Related notes

- [[Interprocess Communication MOC]]
- [[Interprocess Communication Pipes and Sockets]]
- [[File Descriptors and Kernel IO Objects]]
- [[Duplex Communication]]
- [[Byte Streams and Message Framing]]
- [[Linux Virtual File System Paths Directories and Inodes]]
- [[TCP and Sockets]]
- [[Go net-rpc over Unix Domain Sockets]]

