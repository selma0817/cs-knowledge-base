---
aliases:
  - GFS Atomic Record Append
  - GFS Consistency Model
tags:
  - computer-system
  - distributed-systems
  - filesystem
  - gfs
  - consistency
  - idempotency
date: 2026-07-21
summary: GFS record-append behavior, retry duplicates, padding, and the meanings of consistent and defined file regions.
---
## Positional write versus record append

| Operation | Who chooses the offset? | Main guarantee |
|---|---|---|
| Ordinary write | Application | Attempts to write at the requested byte range |
| Record append | GFS primary | Appends the intact record atomically at least once at a GFS-selected offset |

Record append exists so hundreds of producers can append to one file without first coordinating the end offset through an external distributed lock.[^gfs]

## Record-append protocol

Record append follows the normal mutation protocol, with extra logic at the primary:

1. The client pushes the record to all replicas of the fileâ€™s last chunk.
2. The primary decides whether the record fits.
3. If it fits, the primary chooses the offset and tells secondaries to use exactly that offset.
4. If it does not fit, the primary pads the remaining space, tells secondaries to do the same, and asks the client to retry on the next chunk.

The record is not split across chunks, because splitting would violate its atomicity as one record.

## The 16 MB limit

The original GFS limits one record append to one quarter of its 64 MB maximum chunk size:

\[
\frac{1}{4}\times 64\text{ MB}=16\text{ MB}
\]

This bounds worst-case fragmentation from padding. An application appending 100 MB must divide it into records no larger than 16 MB. Each record is atomic individually; the complete 100 MB sequence is not one atomic append, so other clientsâ€™ records may appear between its pieces.

## Why retries can duplicate records

If the client times out, it does not know whether the previous attempt reached some or all replicas. Retrying may place the same logical record at a second offset.

```text
attempt 1: record R may exist at offset 100
retry:     record R succeeds at offset 140
```

Therefore, record append is **at least once**, not exactly once. Applications commonly add record identifiers and checksums so readers can:

- recognize complete records;
- discard padding or partial fragments;
- deduplicate repeated record IDs.

## Consistent versus defined

GFS uses precise terms:

- A region is **consistent** if every client sees the same bytes regardless of which replica it reads.
- A region is **defined** if it is consistent and contains exactly what a successful mutation intended to write.

Defined implies consistent, but consistent does not imply defined.

| Situation | Region state |
|---|---|
| Successful ordinary write without concurrent interference | Defined and consistent |
| Successful concurrent ordinary writes | Consistent but possibly undefined because fragments may be intermingled |
| Failed mutation | Inconsistent and therefore undefined |
| Successful record occurrence | Defined |
| Padding, fragments, or duplicate areas between successful record occurrences | May be inconsistent and undefined |

A successfully appended occurrence is defined even if another copy of the same logical record also appears elsewhere. The filesystem guarantees a valid occurrence, not uniqueness.

## Connection to idempotency

Retrying an ordinary write at the same offset often overwrites the same range. Retrying append is non-idempotent because the primary may choose a new offset each time.

This is the same distributed-systems lesson seen in external tools such as email or payment APIs:

> A timeout does not prove that the operation did not happen.

Exactly-once effects usually require application-level identity and deduplication, not merely transport retries.

## Related notes

- [[Google File System]]
- [[GFS Mutation Protocol and Leases]]
- [[Filesystem Write Guarantees]]
- [[GFS Failure Recovery Replica Placement and Checksums]]

[^gfs]: Ghemawat, Gobioff, and Leung, [â€œThe Google File Systemâ€](https://research.google.com/archive/gfs-sosp2003.pdf), Â§Â§2.7 and 3.3.