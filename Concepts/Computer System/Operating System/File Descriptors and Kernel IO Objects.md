---
title: File Descriptors and Kernel IO Objects
aliases:
  - Everything Is a File
  - File Descriptor Model
created: 2026-08-01
tags:
  - computer-system/operating-system
  - linux
  - filesystem
  - ipc
summary: A file descriptor is a process-local handle through which Linux exposes regular files, pipes, sockets, devices, and other kernel objects using a partly shared I/O interface.
---

# File Descriptors and Kernel IO Objects

## What a file descriptor is

A file descriptor is a small integer in a process, such as `0`, `1`, `2`, or `7`. It indexes an entry in that process’s file-descriptor table.

Conceptually:

```text
process-local fd
    ↓
file-descriptor table entry
    ↓
kernel open-file state
    ↓
regular file, pipe, socket, device, or another I/O object
```

Standard input, output, and error normally use file descriptors `0`, `1`, and `2`.

## What “everything is a file” means

The phrase means that many Linux resources share a common handle and operations such as:

```text
read()
write()
close()
poll()/select()/epoll()
```

It does **not** mean every resource is a regular disk file.

The kernel dispatches an operation to handlers appropriate for the object behind the descriptor:

| Descriptor refers to | Typical behavior |
|---|---|
| Regular file | Persistent bytes, file offset, often seekable |
| Pipe | Temporary kernel buffer, normally one-way, not seekable |
| Connected socket | Communication queues and protocol state, usually bidirectional, not seekable |
| Listening socket | Accepts connections rather than carrying ordinary application data |
| Device | Behavior defined by the device driver |

## VFS and object-specific behavior

The Virtual File System provides common abstractions for pathname lookup and file operations. Object-specific handlers implement what those operations mean.

For a regular file, `read()` may retrieve bytes backed by filesystem blocks and uses a file offset. For a socket, `read()` retrieves bytes from a receive buffer managed by the networking or IPC subsystem. Calling `lseek()` on a socket or pipe fails because there is no meaningful persistent byte position.

## Unix socket pathname versus socket descriptor

A pathname Unix socket illustrates why these ideas must be separated:

```text
pathname + inode  → names the listener through VFS
socket fd         → refers to a live kernel socket object
socket buffers    → hold bytes in transit
```

The filesystem entry can be inspected or unlinked, but it does not store the communication bytes. Once a connection is established, its endpoints remain usable even if the server pathname is deleted.

## Descriptor scope and sharing

File-descriptor numbers are local to each process. File descriptor `7` in one worker has no inherent relationship to file descriptor `7` in the master.

Descriptors can be duplicated, inherited across `fork()`, or passed between processes using suitable IPC mechanisms. Multiple descriptors can therefore refer to shared underlying kernel state even though their integer values differ.

## Relation to the filesystem

Some descriptor-backed resources have filesystem pathnames; others do not:

- regular files and pathname Unix sockets have directory entries and inodes;
- anonymous pipes have no pathname;
- TCP sockets use IP addresses and ports rather than filesystem paths;
- a Unix socket client endpoint may be unnamed.

Therefore, **having a file descriptor does not imply having a filesystem pathname**, and having a filesystem entry does not imply regular-file contents.

## Related notes

- [[Linux Virtual File System Paths Directories and Inodes]]
- [[Linux File Blocks Extents and Reads]]
- [[Unix Domain Sockets]]
- [[Interprocess Communication Pipes and Sockets]]
- [[Duplex Communication]]

