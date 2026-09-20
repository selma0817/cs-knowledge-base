---
aliases:
  - GFS Write Protocol
  - GFS Primary Lease
tags:
  - computer-system
  - distributed-systems
  - filesystem
  - gfs
  - replication
  - consistency
summary: How GFS uses a leased primary to order mutations while pipelining data independently to every replica.
date: 2026-07-21
---
## Why GFS needs a primary
## Write flow

1. The client asks the master for the lease holder and secondary locations.
2. The client caches this metadata.
3. The client pushes the data to every replica, usually through a pipelined chain.
4. After all replicas buffer the data, the client sends the mutation request to the primary.
5. The primary assigns a serial order and applies the mutation.
6. The primary tells each secondary to apply it in that order.
7. Secondaries reply to the primary; the primary replies to the client.

The data flow is separated from control flow:

```text
Bulk bytes: client -> replica pipeline
Ordering:   client -> primary -> secondaries
```

This lets the network pipeline data without making the primary carry every byte from the client to each secondary.

## Writes that cross a chunk boundary

Each chunk has a distinct handle, replica set, lease, and primary. An ordinary byte-range write cannot be one chunk-level mutation across two chunks.

With 64 MB chunks:

```text
Write 20 MB beginning at file offset 60 MB

chunk 0: 4 MB at internal offset 60 MB
chunk 1: 16 MB at internal offset 0 MB
```

The relevant condition is crossing a chunk boundary, not merely whether the request itself exceeds 64 MB.

## Lease duration and primary failure

In the original design, a lease initially lasts 60 seconds and may be extended through heartbeat traffic while the chunk is being mutated.

If the master loses contact with the primary, it cannot immediately assume the server is dead; a network partition might leave the old primary alive. It waits until the old lease expires before safely granting a conflicting lease.

```text
old lease possibly valid
    -> wait for expiration
    -> grant new lease
```

This prevents two legitimate primaries from concurrently ordering mutations for the same chunk.

## Ambiguous outcomes

Suppose the primary and one secondary apply a write, another secondary does not, and the primary crashes before replying. The client cannot distinguish success from failure:

```text
mutation not applied
versus
mutation applied but acknowledgement lost
```

GFS reports failure and the client retries. Until a successful retry repairs the affected ordinary-write range, replicas may disagree and the region is inconsistent. For record append, a retry can instead create a duplicate; see [[GFS Record Append and Consistency]].

## Related notes

- [[Google File System]]
- [[GFS Read Path and Master Scalability]]
- [[GFS Record Append and Consistency]]
- [[GFS Failure Recovery Replica Placement and Checksums]]
- [[Filesystem Write Guarantees]]

[^gfs]: Ghemawat, Gobioff, and Leung, [“The Google File System”](https://research.google.com/archive/gfs-sosp2003.pdf), §§3.1–3.2.
