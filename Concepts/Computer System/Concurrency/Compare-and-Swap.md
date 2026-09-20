---
date: 2026-09-15
aliases:
  - CAS
  - compare and swap
  - compare-and-swap
  - ABA problem
  - lock-free
---
**Compare-and-swap (CAS)** is an atomic read-modify-write operation that updates a memory location *only if* it still holds an expected value. It is the primitive from which lock-free algorithms and higher-level locks are built.

## The operation

CAS takes three arguments and performs a conditional swap indivisibly:

```text
CAS(address, expected, new):
    if *address == expected:
        *address = new
        return true      // I won
    else:
        return false     // someone changed it first
```

The whole compare-and-then-swap happens as one indivisible step. There is no window between the comparison and the write for another thread to slip in. The return value tells the caller whether the swap happened.

```go
// Go: package sync/atomic
swapped := atomic.CompareAndSwapInt64(&counter, 10, 9)
```

## Optimistic, not pessimistic

A mutex is **pessimistic**: it assumes a conflict will happen, so a thread takes the lock first and every other thread **blocks** (parks and sleeps) until the lock is released. CAS is **optimistic**: a thread assumes no conflict, just tries the swap, and if someone beat it the CAS returns `false` **immediately** — the loser does not block, own anything, or wait for a wakeup.

Consider three goroutines that all read a counter of `10` and all attempt `CAS(&c, 10, 9)` at once:

- Exactly **one** succeeds. The other two get `false` instantly.
- The two losers must **re-read** the new value (`9`), recompute, and try again with `expected=9`. There is no lock to wait on.

> Mutex = block until it is your turn. CAS = everyone tries, one wins, losers retry. No ownership, no parking, no wakeup message.

## The CAS retry loop

Because losers must redo their work, CAS is almost always used inside a loop. This is the shape of every lock-free update:

```go
// Decrement only while positive, without a lock.
func tryDecrement(c *int64) bool {
	for {
		old := atomic.LoadInt64(c)
		if old <= 0 {
			return false
		}
		if atomic.CompareAndSwapInt64(c, old, old-1) {
			return true // won this round
		}
		// CAS failed: someone else changed c. Loop, re-read, retry.
	}
}
```

On a failed iteration the value observed no longer matched `expected`, so the swap was skipped; the loop re-reads the fresh value and recomputes.

For a *plain* increment or decrement, do not hand-roll a CAS loop — use `atomic.AddInt64`, which compiles to a single `LOCK XADD` (fetch-and-add) instruction that **always succeeds with no retry**. A CAS loop is only needed when the new value depends on the old in a way no single atomic instruction covers (conditional update, or swinging a pointer in a lock-free structure).

## What makes it atomic

Atomicity does not come from the language or the OS. `atomic.CompareAndSwapInt64` compiles to essentially **one CPU instruction** — on x86 that is `CMPXCHG` with a `LOCK` prefix. The hardware guarantees it:

```
your CAS code
  → LOCK CMPXCHG (one instruction)
     → acquire exclusive ownership of the cache line
        → cache-coherence protocol serializes ownership across cores
           → exactly one core's compare-and-swap sees the expected value and wins
```

A plain read-modify-write has a window between read and write where another core could interfere. The `LOCK` prefix closes that window by making the compare *and* the swap happen while the core holds the cache line exclusively and refuses to release it mid-operation. Because the coherence protocol lets only one core own a line exclusively at a time, only one core's CAS can succeed against a given value. See [[Cache Coherence and MESI]] for the full mechanism.

## The ABA problem

CAS checks "is the value still what I expect?" — but *same value* is not always *nothing changed*. In a lock-free stack whose `head` pointer is swung by CAS:

1. Thread 1 reads `head → A`, plans `CAS(head, A, B)` where `B` is A's `next`.
2. Thread 1 is preempted.
3. Other threads pop A, pop B, then push A back. Now `head → A` again — but B is no longer on the stack.
4. Thread 1 resumes and runs `CAS(head, A, B)`. It **succeeds** because head is A again — and now `head` points at B, a node that was already removed. Its stale `next` chain corrupts the stack.

This is the **ABA problem**: the value left and came back, so CAS cannot tell the world changed.

**Fix — a version counter.** Bundle a monotonically increasing counter with the pointer and CAS the *pair*:

```text
Instead of:  CAS(head,          expected=A,      new=B)
Do:          CAS(head+counter,  expected=(A,7),  new=(B,8))
```

Every modification bumps the counter, so after ABA the pointer is back to A but the counter has moved — the pair `(A,9) ≠ (A,7)` and the CAS fails. Implementations:

- **Java:** `AtomicStampedReference` (reference + int stamp).
- **Hardware:** double-width CAS — x86-64 `CMPXCHG16B` swaps a 64-bit pointer + 64-bit counter atomically.

**GC's role.** In C/C++ a popped node may be `free()`d, so a stale CAS pointing at it is a use-after-free — ABA at its most dangerous. In a garbage-collected language (Go, Java) a node cannot be collected while a thread still holds a reference, so the **memory-safety half of ABA disappears** and lock-free code is easier to write correctly. GC does **not** remove *logical* ABA: reusing the same node object can still make the pointer recur. Non-GC languages solve reclamation with **hazard pointers** or **epoch-based reclamation (RCU-style)**.

> ABA: CAS sees "same value" and assumes "no change," but the value left and returned. Fix = version counter on the pair (double-width CAS / `AtomicStampedReference`). GC neutralizes the memory-safety danger, not the logical one.

## A mutex is built on CAS

A lock is not an alternative to atomics — it is *made of* them:

```text
Mutex.Lock():
  fast path → CAS the lock word UNLOCKED→LOCKED   (pure hardware atomic)
              success ⇒ you hold the lock; runtime never involved.
  slow path → CAS failed (contended) ⇒ ask the runtime to PARK this
              goroutine and wake it on Unlock.
```

So CAS is the atomic primitive; a mutex adds *waiting machinery* (park/wake) on top. This is why an uncontended mutex is nearly as cheap as a CAS, and why heavy contention makes it expensive — you fall to the slow path.

## Tradeoffs: CAS versus mutex

A CAS retry loop **spins** instead of sleeping. Under heavy contention this is doubly expensive: many retries are wasted work, *and* the single cache line ping-pongs between all contending cores (each attempt fires an ownership request that invalidates every other copy), so the line never settles. It is not livelock — one thread wins each round — but most work is thrown away. A mutex that parks losers avoids both costs.

| Prefer CAS / lock-free | Prefer a mutex |
| --- | --- |
| Single-word update, short operation | Critical section spans multiple variables / cache lines |
| Low to moderate contention | High contention (parking beats 64 cores spinning on one line) |
| Cannot afford to block (real-time, signal handlers, lock-free progress guarantees) | Critical section does I/O or slow work (never spin across that) |
| Update maps to one atomic instruction, or a cheap loop | Complex invariant over many fields |

When a CAS loop *is* needed under contention, add **exponential backoff** in the retry to reduce cache-line thrashing.

## Interview summary

> CAS conditionally writes a memory location only if it still equals an expected value, indivisibly, returning whether it swapped. It is optimistic concurrency: losers get `false` immediately and retry rather than block. Atomicity comes from a single `LOCK CMPXCHG` instruction backed by cache coherence, not from the language or OS. The classic pitfall is ABA, fixed with a version counter (double-width CAS); GC removes the memory-safety half of ABA but not the logical half. Mutexes are built on CAS: fast-path CAS to grab the lock, runtime park/wake on the slow path. Use CAS for short single-word updates under light contention and prefer `atomic.AddInt64` (fetch-and-add) for plain counters; prefer a mutex when contention is high or the critical section is large.

## Related notes

- [[Cache Coherence and MESI]]
- [[Mutex]]
- [[Semaphore]]
- [[Concurrency vs Parallelism]]
- [[Go Scheduler]]
- [[Concurrency MOC]]
