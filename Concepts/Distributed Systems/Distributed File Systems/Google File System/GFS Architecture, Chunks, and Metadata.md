---
aliases:
  - GFS Architecture
  - GFS Master Metadata
tags:
  - computer-system
  - distributed-systems
  - filesystem
  - gfs
  - metadata
summary: How the GFS master, clients, chunkservers, chunks, operation log, and checkpoints divide responsibility.
---
## Three main roles

| Component | Responsibility |
|---|---|
| **Master** | Namespace, file-to-chunk mapping, chunk versions, replica placement, leases, re-replication, migration, and garbage collection |
| **GFS client library** | Translates file offsets into chunk indices, asks the master for metadata, caches locations, and communicates with chunkservers |
| **Chunkserver** | Stores chunk replicas as ordinary Linux files and serves byte-range reads and mutations |

A cluster has one active master and many chunkservers. Centralizing metadata decisions gives the master a global view, while keeping file bytes off its data path prevents ordinary reads and writes from consuming its bandwidth.[^gfs]

## Files and chunks

GFS divides a file into fixed-size 64 MB chunks. When a chunk is created, the master assigns it an immutable, globally unique 64-bit **chunk handle**.

```text
/logs/events
    logical chunk 0 -> handle H17
    logical chunk 1 -> handle H93
    logical chunk 2 -> handle H41
```

The filename belongs to the namespace. The chunk handle identifies stored data. A chunkserver request therefore uses a handle and a byte range rather than a pathname.

Each chunk normally has three replicas, although replication policy can vary across the namespace.

## What metadata does the master keep?

The master keeps three main kinds of metadata in memory:

1. File and chunk namespaces.
2. File-to-chunk mappings.
3. Current replica locations.

The first two are persisted through the master’s operation log. Replica locations are not persistently recorded as authoritative metadata; chunkservers report what they actually store when the master starts and when servers join. This avoids maintaining a supposedly durable location table that can become wrong whenever disks fail or machines disappear.

## Operation log and checkpoint

The operation log is the authoritative history of critical metadata mutations. It also establishes a logical order for concurrent namespace operations.

```text
persist metadata mutation locally and remotely
    -> acknowledge operation
    -> later include it in a checkpoint
```

The master periodically creates a checkpoint so recovery does not require replaying an indefinitely growing log:

```text
latest complete checkpoint
    + later operation-log records
    = recovered master state
```

The checkpoint is a recovery optimization. The operation log remains the ordered record of changes since that checkpoint.

## Why one master is workable

One master simplifies:

- namespace locking;
- lease assignment;
- replica placement;
- global rebalancing;
- identifying orphaned chunks.

It would be a serious bottleneck if all bytes passed through it. GFS instead restricts the master primarily to metadata and control decisions. See [[GFS Read Path and Master Scalability]] and [[GFS Mutation Protocol and Leases]].

## Common distinction

Do not confuse these two snapshots:

| Mechanism | Purpose |
|---|---|
| Master checkpoint | Recover the master’s metadata after failure |
| Filesystem snapshot | Create a user-visible copy of a file or directory tree using copy-on-write |

The latter is explained in [[GFS Snapshots Garbage Collection and Workloads]].

## Related notes

- [[Google File System]]
- [[Linux Virtual File System Paths Directories and Inodes]]
- [[Linux File Blocks Extents and Reads]]
- [[GFS Failure Recovery Replica Placement and Checksums]]

[^gfs]: Ghemawat, Gobioff, and Leung, [“The Google File System”](https://research.google.com/archive/gfs-sosp2003.pdf), §§2.3–2.6.
