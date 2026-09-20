---
date: 2026-09-15
aliases:
  - cache coherence
  - MESI
  - MESIF
  - MOESI
  - snooping
  - false sharing
  - cache line
---
**Cache coherence** is the hardware guarantee that, although each CPU core caches memory in its own private caches, all cores observe a single consistent value for any given memory location. It is the mechanism that makes atomic operations such as [[Compare-and-Swap]] work across cores.

## Why coherence is needed

Each core has private L1/L2 caches; L3 and RAM are shared:

```
Core 0                     Core 1
 ┌──────┐                   ┌──────┐
 │ L1/L2│ (private)         │ L1/L2│ (private)
 └───┬──┘                   └───┬──┘
     └──────────┬───────────────┘
            ┌───┴────┐
            │   L3   │ (shared)
            └───┬────┘
            ┌───┴────┐
            │  RAM   │
            └────────┘
```

When a core touches address `x`, it pulls a **cache line** — a 64-byte chunk containing `x` — into its private cache and works on that copy. Without coordination, Core 0 and Core 1 could each hold their own copy of the line, both read `10`, both write `9`, and neither see the other. Coherence prevents this.

## The MESI states

Coherence protocols track a state per cache line per core. The common one is **MESI**:

| State | Meaning |
| --- | --- |
| **M**odified | This core has the only copy and has changed it; RAM is stale. |
| **E**xclusive | This core has the only copy, unchanged. |
| **S**hared | Multiple cores hold read-only copies. |
| **I**nvalid | This copy is stale and unusable. |

The ironclad rule: **a line is in Modified or Exclusive on at most one core at a time.** To write, a core must first own the line exclusively.

## Request For Ownership and serialization

Before writing a line, a core issues a **Request For Ownership (RFO)** on the interconnect: "I want exclusive ownership of this line." Every other core holding a copy must **invalidate** theirs (→ `I`) and acknowledge. Only then may the requester write.

Crucially, **the interconnect serializes RFOs** — two cores cannot both win exclusive ownership of the same line at the same instant. One goes first; the other waits. This serialization is exactly what lets a `LOCK CMPXCHG` guarantee only one core's compare-and-swap wins.

## Snooping

Coherence is enforced by **snooping**: every cache continuously watches the shared interconnect for requests touching lines it holds, and reacts per the protocol.

- "Someone wants to **write** a line I hold" → I **invalidate** my copy (or, if I hold it Modified, **forward** the fresh value first).
- "Someone wants to **read** a line I hold Modified" → I **forward** my fresh copy.

> Snooping = every cache watches the interconnect for requests about lines it holds, invalidating on a write request and forwarding fresh data on a read request.

Snooping is broadcast-based and does not scale past a modest core count. Large multi-socket systems use **directory-based coherence**: a directory tracks which cores hold each line so the protocol sends targeted messages instead of broadcasting. Same MESI states, different delivery.

## Write-back and cache-to-cache transfer

Modern caches are **write-back**, not write-through. When a core modifies a line it writes **only into its own private cache** and marks the line **Modified**; RAM and L3 stay **stale**. The dirty value is written back only on **eviction** or when another core forces it out.

So when another core needs a line that some core holds Modified, the fresh value is **not** in RAM. Via snooping, the owner **intervenes** and the line is transferred **core-to-core** (through L3 / the interconnect), typically updating memory at the same time. Reading from another core's on-chip cache is far faster than a RAM round-trip.

```
1. Core 1 issues RFO for x's line.
2. Core 0 is snooping, sees it holds that line Modified (fresh x=9).
3. Core 0 forwards the line to Core 1 (and to L3/RAM); its copy → Invalid.
4. Core 1 now has the fresh x=9. RAM was stale the whole time.
```

Plain MESI sometimes forces a write-back during such a transfer. Real CPUs optimize this:

- **Intel → MESIF**: adds an **F (Forward)** state designating one sharer as the official forwarder for clean cache-to-cache transfers.
- **AMD → MOESI**: adds an **O (Owned)** state so a core can hold a *dirty* line and keep serving copies without writing back to RAM each time.

## False sharing

Coherence operates on whole cache lines, not individual variables. If two logically independent variables land on the **same 64-byte line**, writing either one forces ownership of the whole line, so the line **ping-pongs** between cores even though the variables are unrelated. This is **false sharing**, a common cause of mysterious multithreaded slowdowns.

Fixes: pad or align hot per-core data so each sits on its own cache line (e.g. Go's `sync/atomic` counters in hot paths, or padding a struct to 64 bytes).

## Connection to atomics and memory ordering

- **Atomics ([[Compare-and-Swap]], fetch-and-add):** rely on exclusive ownership + `LOCK` to make a read-modify-write indivisible. Heavy atomic contention is expensive precisely because one line ping-pongs across all contending cores.
- **Memory barriers / ordering:** coherence guarantees a single value *per location*, but not the *order* in which one core's writes to *different* locations become visible to another. Store buffers and out-of-order execution can reorder those. Memory fences (and the acquire/release semantics behind [[Mutex]] lock/unlock) constrain that ordering. Coherence and ordering are related but distinct guarantees.

## Interview summary

> Cache coherence keeps every core's private caches consistent for each memory location. MESI tracks each line as Modified/Exclusive/Shared/Invalid, with at most one core owning a line for writing. A core must win a serialized Request For Ownership (invalidating others) before writing; snooping makes every cache react to interconnect traffic. Caches are write-back, so a dirty value lives in the modifying core's cache and moves core-to-core via forwarding, not through stale RAM. Because coherence works on whole 64-byte lines, unrelated variables sharing a line cause false sharing. This serialized ownership is the hardware foundation that makes CAS and other atomics work across cores; memory ordering is a separate guarantee enforced by fences.

## Related notes

- [[Compare-and-Swap]]
- [[Mutex]]
- [[Concurrency vs Parallelism]]
- [[Concurrency MOC]]
