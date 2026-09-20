---
aliases:
  - GFS Stale Replicas
  - GFS Re-replication
  - GFS Data Integrity
tags:
  - computer-system
  - distributed-systems
  - filesystem
  - gfs
  - replication
  - fault-tolerance
  - checksum
date: 2026-07-21
summary: How GFS detects stale replicas, rebuilds lost redundancy, isolates failures across racks, and distinguishes corruption from legal divergence.
---
## Failure is expected

GFS assumes machines, disks, processes, and networks fail routinely. Availability comes from fast restart, replication, heartbeat-based failure detection, and automatic re-replication rather than assuming durable individual servers.[^gfs]

## Chunk versions detect stale replicas

The master maintains one expected version number per logical chunk. Each replica persistently records its local version.

When granting a new lease, the master:

1. increments the chunk’s version;
2. informs all available, up-to-date replicas;
3. waits for them to persist the new version;
4. then exposes the lease to the client.

```text
Master expects H1 v8
S1 reports H1 v8 -> current
S2 reports H1 v8 -> current
S3 reports H1 v7 -> stale
```

An unavailable replica misses the version advance. When it reconnects and reports the older value, the master excludes it from mutations and new location responses and eventually garbage-collects it.

## Versions are lease epochs, not mutation counters

A version does not increase after every write:

```text
grant lease -> v8
write A     -> v8
write B     -> v8
new lease   -> v9
```

This means two replicas can both report `v8` yet contain different bytes after a partially failed mutation. Chunk versions detect replicas that missed a lease epoch; they do not prove byte-for-byte equality after every mutation.

## Why GFS clones instead of replaying missed mutations

Version numbers answer whether a replica is current, not how to transform an old copy into the latest state. GFS does not keep a durable per-replica history of every missed mutation.

Replaying would require preserving the history, identifying exactly what a server missed, ordering it, and handling partial or duplicate application. Instead, GFS creates a fresh full copy from a known-current replica.

## Re-replication priority

The master considers more than the raw replica count:

- how far a chunk is below its replication goal;
- whether it belongs to a live or recently deleted file;
- whether losing another copy would make it unavailable;
- whether it is blocking client progress.

A blocking chunk may receive boosted priority, while a chunk with only one surviving copy remains urgent because it has no redundancy. Multiple repairs can proceed concurrently within throttling limits.

## Destination placement

The emptiest server is not automatically the best destination. Placement also considers:

- balancing disk utilization;
- avoiding too many recent chunk creations on one server;
- limiting simultaneous clone work;
- available network bandwidth;
- spreading replicas across racks and failure domains.

Rack diversity protects against correlated switch, power, or network failures. GFS also throttles cloning so recovery traffic does not overwhelm client traffic.

## Checksums detect local corruption

Each chunkserver divides a chunk into 64 KB blocks and stores a 32-bit checksum per block. It recomputes and compares checksums to verify its own stored bytes.

```text
stored checksum != checksum of local bytes
    -> local corruption
```

GFS does not generally declare a replica corrupt merely because its checksum differs from another replica’s checksum:

```text
checksum(S1) != checksum(S3)
    -> replicas disagree
    -> does not reveal which logical outcome is correct
```

Both replicas can be internally intact yet legally divergent after a failed record append. Cross-replica disagreement therefore differs from a local integrity failure.

## Related notes

- [[Google File System]]
- [[GFS Architecture Chunks and Metadata]]
- [[GFS Mutation Protocol and Leases]]
- [[GFS Record Append and Consistency]]
- [[GFS Snapshots Garbage Collection and Workloads]]

[^gfs]: Ghemawat, Gobioff, and Leung, [“The Google File System”](https://research.google.com/archive/gfs-sosp2003.pdf), §§4.2–4.5 and 5.1–5.2.
