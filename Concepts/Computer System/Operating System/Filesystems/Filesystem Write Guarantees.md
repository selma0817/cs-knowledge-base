---
aliases:
  - Atomicity Durability and Consistency in Filesystem
  - Concurrent File Append
tags:
  - computer-system
  - operating-system
  - filesystem
  - concurrency
  - reliability
  - durability
  - consistency
date: 2026-07-19
summary: How atomicity, durability, consistency, and ordering describe different properties of filesystem writes and concurrent appends.
---
## The properties are independent

| Property        | Question                                                                                |
| --------------- | --------------------------------------------------------------------------------------- |
| **Atomicity**   | Can an operation appear partially applied or incorrectly interleaved with another?      |
| **Durability**  | Does a completed operation survive the relevant failure, such as power loss?            |
| **Consistency** | Do filesystem structures or distributed replicas agree according to the promised rules? |
| **Ordering**    | In what sequence may observers see concurrent operations?                               |

An operation can be atomic but not durable: two concurrent appends may receive nonoverlapping ranges, yet both may remain only in dirty memory.

## Filesystem consistency versus replica consistency

The word **consistency** is used at different layers:

```text
Local structural consistency:
inode mapping <-> block-allocation metadata

Distributed replica consistency:
replica A <-> replica B <-> replica C
```

Examples:

- The inode owns block 900 while the free-space map calls it free: local filesystem consistency failure.
- Replica A contains `hello world` while replicas B and C contain `hello`: replica consistency problem.

## Acknowledgement matters

Whether data loss counts as a failure depends on the interface contract.

- If ordinary `write()` returned but no durability was promised, losing dirty data after sudden power loss may be allowed.
- If the promised durability operation returned successfully and the data still disappeared under the covered failure model, that is a durability failure.

Always ask:

> What did the system promise when it reported success?

## Concurrent append race

Suppose a file is 100 bytes long. Two writers manually implement append:

```text
A: read size -> 100
B: read size -> 100
A: write at offset 100
B: write at offset 100
```

Both selected the same position. Locking each `get_file_size()` call separately does not help, because the unsafe operation spans both checking the size and reserving the range.

This is a **check-then-act race**.

## Atomic append

The critical operation must behave like one indivisible action with respect to competing writers:

```text
determine current end
    -> reserve a nonoverlapping range
    -> update the end position
    -> perform the write
```

With Linux `O_APPEND`, repositioning to the current end and the write are performed as a single atomic step for each `write()` on supported local filesystems.[^open]

Possible valid orders include:

```text
hello AAA BBB
hello BBB AAA
```

The order may be nondeterministic while the writes still avoid choosing the same range.

## Atomic operation versus transaction

Calling the coordinated append a **transaction** conveys the intuition that several substeps must be grouped. More precisely, it is an **atomic operation** unless the interface also defines broader transaction properties such as commit, rollback, isolation, and crash recovery.

## Bridge to GFS record append

GFS was designed for many producers appending to one file. It therefore adds record append:

```text
Positional write:
client chooses offset X

GFS record append:
client supplies a record;
GFS chooses and coordinates the offset
```

This allows GFS to coordinate concurrent writers and replicas, but GFS's at-least-once behavior means retrying can create duplicates. See [[Google File System]].

## Related notes

- [[Linux Filesystem MOC]]
- [[Linux Page Cache Writeback and Journaling]]
- [[Concurrency vs Parallelism]]
- [[Google File System]]

[^open]: Linux manual pages, [`open(2)` and `O_APPEND`](https://man7.org/linux/man-pages/man2/open.2.html).