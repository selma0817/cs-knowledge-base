---
date: 2026-08-16
aliases:
  - concurrency moc
---

Concurrency is the coordination of multiple tasks whose executions overlap. Parallelism is the simultaneous execution of multiple tasks. See [[Concurrency vs Parallelism]].

The execution abstractions themselves — process, thread, coroutine — and how they differ in scheduling, memory, and cost: see [[Process vs Thread vs Coroutine]].

## Core questions

- What work may happen concurrently?
- What state is shared?
- Which operations must appear indivisible?
- Is the goal correctness, bounded resource use, or both?
- Where should backpressure occur when work arrives faster than it can be processed?

## Synchronization primitives

- [[Mutex]] â€” gives exclusive access to a critical section and protects shared-state invariants.
- [[Semaphore]] â€” manages a fixed number of permits and limits concurrent resource use.
- Atomic operations â€” make a single supported read-modify-write operation indivisible.
- [[Compare-and-Swap]] â€” atomic conditional read-modify-write; the optimistic primitive behind lock-free code and lock fast paths.
- [[Cache Coherence and MESI]] â€” the hardware foundation (MESI, snooping, cache lines) that makes atomics work across cores.
- Condition variables â€” allow goroutines or threads to sleep until shared state may satisfy a condition.
- [[sync.WaitGroup]] â€” waits for a collection of goroutines to finish; it does not protect shared data.

## Go concurrency patterns

- [[Goroutines and Channels]]
- [[Go Channel Pitfalls and Internals]]
- [[Go Map and Slice Thread Safety]]
- [[Worker Pool]]
- [[sync.WaitGroup]]
- [[Go Scheduler]]

## Choosing a mechanism

| Requirement | Typical choice |
| --- | --- |
| Protect a shared map or multi-field invariant | [[Mutex]] |
| Permit at most ten in-flight API calls | [[Semaphore]] |
| Process a large stream using four long-lived workers | [[Worker Pool]] |
| Wait until several goroutines finish | [[sync.WaitGroup]] |
| Transfer ownership or communicate between goroutines | Channel |
| Update one independent counter | Atomic operation or mutex |

These mechanisms can be combined. A worker pool may contain twenty workers while a three-permit semaphore restricts how many workers may use a GPU.

## Operating-system boundary

[[POSIX]] specifies portable Unix-like APIs for threads, mutexes, semaphores, files, processes, shells, and command-line utilities. Actual implementations may use hardware atomics, runtime schedulers, and OS-specific waiting mechanisms.

## Interview checklist

- Distinguish concurrency from parallelism.
- Identify the shared invariant rather than locking only an assignment.
- Explain happens-before and memory visibility.
- Distinguish a semaphore, worker pool, and rate limiter.
- Trace where blocking and backpressure occur.
- Recognize data races, permit leaks, copied locks, and deadlocks.
- Explain atomic fast paths and contended slow paths.