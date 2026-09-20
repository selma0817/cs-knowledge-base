---
aliases:
  - GFS Copy-on-Write
  - GFS Lazy Deletion
  - GFS Workload Trade-offs
tags:
  - computer-system
  - distributed-systems
  - filesystem
  - gfs
  - snapshot
  - garbage-collection
  - copy-on-write
date: 2026-07-21
summary: How GFS implements copy-on-write snapshots and lazy deletion, and how its target workload shapes its trade-offs.
---
## Filesystem snapshot versus master checkpoint

A GFS filesystem snapshot is a user-visible copy of a file or directory tree. A master checkpoint is an internal recovery representation of master metadata. They are different mechanisms.

## Copy-on-write snapshot

At snapshot creation, the master revokes or waits out leases, logs the operation, and duplicates namespace metadata. Both paths initially reference the same chunk handles:[^gfs]

```text
/data/file     -> [H1, H2, H3]
/snapshot/file -> [H1, H2, H3]
```

No file data is copied at this point.

On the first later write to shared chunk `H2`:

1. The client asks the master for the lease holder.
2. The master sees that `H2` has more than one reference.
3. It creates a new handle `H2'`.
4. It asks every chunkserver with a current `H2` replica to copy it locally as `H2'`.
5. It updates the writer’s file-to-chunk mapping.
6. It grants a lease on `H2'` and allows the normal mutation protocol to proceed.

```text
/data/file     -> [H1, H2', H3]
/snapshot/file -> [H1, H2,  H3]
```

Even a one-byte update may require copying the affected chunk, but untouched chunks remain shared. Local copying avoids transferring the original chunk across the network.

## Lazy deletion

Deleting a file does not immediately erase all replicas. The master logs the deletion and renames the file to a hidden, timestamped name. In the original configuration, hidden files older than three days were removed during namespace scans; the interval was configurable.

After the namespace entry is removed:

1. Its chunks become unreachable from live file mappings.
2. The master identifies those chunks as orphaned.
3. Chunkservers report stored handles through heartbeats.
4. The master tells them which unknown handles may be deleted.

## Why lazy deletion helps

- Accidental deletions can be reversed during the retention window.
- Offline chunkservers do not block a synchronous delete protocol.
- Lost delete messages do not require indefinitely retained retry state.
- Cleanup is batched with normal background scans and heartbeats.

The cost is delayed space reclamation. A deleted 2 TB file replicated three times may continue occupying roughly 6 TB until garbage collection.

## Workloads GFS fits

GFS was designed for:

- a modest number of very large files;
- high sustained bandwidth rather than minimum per-request latency;
- large streaming reads;
- large sequential writes and append-heavy files;
- many concurrent producers appending results;
- applications able to recognize checksummed records and deduplicate IDs;
- routine machine and disk failures.

## Workloads GFS does not fit well

It is a poor match for:

- millions or billions of tiny files;
- frequent small random overwrites;
- low-latency transactional databases;
- cross-record transactions;
- strict exactly-once effects without application-level deduplication;
- workloads that cannot tolerate the relaxed consistency model.

A 2 KB record is not automatically a 2 KB file. Packing many records into large files reduces namespace pressure, but it does not add database transactions or make random updates efficient.

## Design lesson

GFS is not trying to be a universally optimal POSIX filesystem. Its unusual choices—64 MB chunks, a single master, record append, relaxed consistency, and lazy cleanup—are coherent because they optimize for Google’s measured workload assumptions.

> Evaluate a system by the workload and guarantees it was designed for, not by whether it maximizes every desirable property simultaneously.

## Related notes

- [[Google File System]]
- [[GFS Read Path and Master Scalability]]
- [[GFS Record Append and Consistency]]
- [[GFS Failure Recovery Replica Placement and Checksums]]
- [[Linux Page Cache Writeback and Journaling]]

[^gfs]: Ghemawat, Gobioff, and Leung, [“The Google File System”](https://research.google.com/archive/gfs-sosp2003.pdf), §§2.1–2.2, 3.4, and 4.4.
