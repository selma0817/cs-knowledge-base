---
date: 2026-10-15
tags:
  - java
  - jmm
  - concurrency
  - memory-model
  - volatile
  - interview
aliases:
  - volatile
  - java memory model
  - JMM
  - happens-before
  - memory barrier
  - memory visibility
---
**`volatile`** is a Java Memory Model (JMM) keyword that gives a field **visibility** and **ordering** guarantees across threads — but deliberately **not atomicity**. It is the Java-level memory barrier, and it is what makes lock-free reads in [[Hash Map|ConcurrentHashMap]] safe.

## The two guarantees (and the one it does not give)

**1. Visibility.** Without `volatile`, a thread may keep a field in a register / CPU cache / store buffer and **never see another thread's update** (the JMM permits per-thread copies). A `volatile` write is published so other threads see it; a `volatile` read fetches the latest write.

```java
volatile boolean running = true;   // thread B: running = false
while (running) { ... }            // thread A — WITHOUT volatile, A may loop forever
```

**2. Ordering (happens-before).** A `volatile` write **happens-before** a later `volatile` read of the same field, and the compiler/CPU may **not reorder** across it: writes before the volatile write stay before it; reads after the volatile read stay after it. Classic use: the **double-checked-locking singleton** marks the instance `volatile` so other threads never see a *partially constructed* object (reordering of "allocate memory" vs "assign reference").

**3. NOT atomicity.** `volatile int x; x++;` is **not** atomic — it is read-modify-write (three steps). `volatile` makes each read/write individually visible/ordered, not a sequence atomic. For atomic RMW use `synchronized` or an atomic/[[Compare-and-Swap|CAS]].

> volatile = visibility + ordering, **not** atomicity. "See the latest, in order" — but `x++` can still lose updates.

## Under the hood: memory barriers (and how it relates to MESI)

`volatile` is implemented with **memory barriers (fences)** inserted around the access. From [[Cache Coherence and MESI]]: cache coherence already guarantees cores agree on a location's value **eventually**, but **store buffers and instruction reordering** can delay/reorder *when* a write becomes visible. A `volatile` write emits a **StoreLoad barrier** (on x86 often a `lock`-prefixed op / `mfence`) that **flushes the store buffer and forbids reordering**, so the coherence-guaranteed value becomes visible **immediately and in order**.

> Coherence (MESI) makes cores agree on a value **eventually**; `volatile`'s barrier makes the write visible **now** and **in order**. volatile is the Java-level fence supplying the "ordering" half that coherence alone does not.

## Why it makes ConcurrentHashMap reads lock-free

A CHM `Node` has `final K key; final int hash;` (immutable, safely published) and **`volatile V val; volatile Node next;`**; the table reference is volatile and array slots are accessed with volatile semantics (`tabAt`). So `get()` walks the bucket with volatile reads and sees the latest value with **no lock** — while writers publish via volatile writes (and serialize against each other with CAS / per-bucket `synchronized`). A reader of a key being updated sees **either the old or the new value, never a torn one**, because a reference assignment is atomic and `val` is volatile. See [[Hash Map]].

## Interview summary

> `volatile` gives a field visibility (reads see the latest write; no per-thread stale copies) and ordering (a volatile write happens-before a later volatile read, and the compiler/CPU can't reorder across it), but not atomicity — `x++` on a volatile is still a lost-update race, needing synchronized or CAS. It is implemented with memory barriers; relative to MESI, coherence makes cores agree on a value eventually while volatile's fence makes the write visible now and in order. This is exactly why ConcurrentHashMap can read without locking: val/next and the table slots are volatile, so a reader sees a consistent old-or-new value while writers publish via volatile writes and serialize only against other writers.

## Related notes

- [[Cache Coherence and MESI]]
- [[Compare-and-Swap]]
- [[Mutex]]
- [[Hash Map]]
- [[Concurrency vs Parallelism]]
