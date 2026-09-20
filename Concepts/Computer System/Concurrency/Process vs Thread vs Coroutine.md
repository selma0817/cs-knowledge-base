---
date: 2026-09-15
aliases:
  - process vs thread
  - thread vs coroutine
  - coroutine
  - goroutine vs thread
  - 进程 线程 协程
  - process thread coroutine
  - green thread
  - M:N scheduling
---
**Processes, threads, and coroutines** are three levels of execution abstraction. The key axes that separate them: **who schedules them** (kernel vs. user-space runtime), **what memory they share**, and **how cheap they are** to create and switch.

## The three, in one line each

- **Process** — the unit of **resource allocation**; has its own isolated **virtual address space**. The heaviest.
- **Thread** — the unit of **CPU scheduling**; lives inside a process, shares that process's memory. Scheduled by the **OS kernel**.
- **Coroutine** (goroutine) — a **user-space** task multiplexed onto threads by a **runtime scheduler**, not the kernel. The lightest.

## Process memory layout and what threads share

```
Process address space (shared by all its threads):
  Code / Text      the instructions               ← shared
  Global / Static  globals, statics               ← shared
  Heap             dynamically allocated objects  ← shared   (→ needs locks)
  Stack (per thread)  each thread's own call frames & locals  ← NOT shared
Also shared: open file descriptors, the whole address space (page tables).
Per thread: stack, registers, program counter.
```

The **shared heap** is exactly why concurrent data structures (maps, slices) need synchronization — two threads can reach the same heap object. Stack locals are private, so they need no locking.

## The comparison

| Dimension | Process | Thread | Coroutine (goroutine) |
| --- | --- | --- | --- |
| Unit of | resource allocation | CPU scheduling | user-space task |
| Scheduled by | OS kernel | OS kernel | **user-space runtime** (e.g. Go scheduler) |
| Memory | own isolated address space | shares process heap/code; own stack | own small growable stack; shares the thread |
| Isolation | strong (separate address space) | weak (shared memory → locks) | weak (shared memory → locks) |
| Switch cost | highest (address-space swap) | high (kernel trap, TLB/cache) | **low (user space, ~ns)** |
| Stack | — | fixed ~1–8 MB | **~2 KB, growable** |
| How many feasible | tens–hundreds | thousands | **millions** |
| Communication | IPC ([[Interprocess Communication MOC]]) | shared memory + [[Mutex]] | channels + shared memory |
| Kernel mapping | — | 1:1 with a kernel thread | **M:N** onto threads |

## Why coroutine switches are cheap (the crux)

- **OS thread switch** is expensive because it **traps into the kernel** (a mode switch to privileged mode): the kernel saves/restores the full context (all registers, PC, SP), updates scheduler structures, and often **flushes the TLB and pollutes caches** — on the order of ~1 microsecond.
- **Coroutine switch** happens **entirely in user space**: the runtime swaps the stack pointer and a few registers, with **no kernel trap, no mode switch, no TLB flush** — on the order of tens of nanoseconds.

Note: coroutines do **not** share a stack — each has its own. They share the **OS thread** they run on; the runtime swaps stack pointers to switch between them.

> Threads are scheduled by the kernel and switch through it (expensive); coroutines are scheduled by a runtime and switch in user space (cheap). Each coroutine has its own small growable stack and shares the thread it runs on.

## Creation cost and the M:N model

An OS thread has a **fixed multi-MB stack** allocated up front → only thousands fit. A goroutine starts at a **~2 KB growable stack** (grown by copying when needed) → millions fit. That ~1000× difference is why Go spawns goroutines freely.

Threads map **1:1** to kernel scheduling entities. Coroutines use an **M:N model** — many coroutines multiplexed onto few threads by the runtime. In Go this is the [[GMP Scheduler Internals]] model: **G** (goroutine) : **M** (OS thread) : **P** (scheduling context), where G ≫ M ≥ P.

## Concurrency vs parallelism

Coroutines give **concurrency** (many tasks in progress, interleaved). **Parallelism** (running at the same instant) still requires multiple threads on multiple cores — in Go, bounded by `GOMAXPROCS`. See [[Concurrency vs Parallelism]]. A single-threaded runtime can run millions of concurrent coroutines with zero parallelism.

## Interview summary

> A process is the unit of resource allocation with its own isolated address space; a thread is the unit of CPU scheduling inside a process, sharing its heap/code but with its own stack, scheduled by the kernel; a coroutine (goroutine) is a user-space task scheduled by a runtime and multiplexed M:N onto threads. Thread switches are expensive because they trap into the kernel (mode switch, full context, TLB/cache effects); coroutine switches are cheap because the runtime does them in user space by swapping a stack pointer. OS threads have fixed multi-MB stacks (thousands feasible); goroutines have ~2 KB growable stacks (millions feasible). Processes communicate via IPC; threads and coroutines share memory and need synchronization (mutexes, or channels in Go).

## Related notes

- [[GMP Scheduler Internals]]
- [[Concurrency vs Parallelism]]
- [[Mutex]]
- [[Interprocess Communication MOC]]
- [[Goroutines and Channels]]
- [[Go Scheduler]]
