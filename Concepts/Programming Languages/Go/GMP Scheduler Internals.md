---
date: 2026-09-15
tags:
  - go
  - goroutine
  - scheduler
  - runtime
  - gomaxprocs
  - concurrency
  - interview
aliases:
  - GMP
  - GMP model
  - GMP scheduler
  - work stealing
  - netpoller
  - syscall handoff
  - async preemption
  - sysmon
---
The **GMP model** is the Go runtime scheduler: **G**oroutines multiplexed onto OS threads (**M**) through logical processors (**P**). This note is the internals deep-dive — local queues, work stealing, why P exists, syscall handoff, the netpoller, and preemption — beyond the usage-level [[Go Scheduler]] note.

## G, M, P — and the layers below

```
G  (goroutine)          software: unit of work; lightweight (~2KB growable stack), millions of them
     runs on
M  (machine / OS thread) software: kernel-schedulable thread; the thing that EXECUTES
     must hold a
P  (processor)          software: a Go-runtime "license to run Go code" + a local run queue
     ── separately, the OS schedules M onto ──
logical CPU / hyperthread  HARDWARE: what the OS sees as a "CPU" (SMT = 2 per core)
     on a
physical core            HARDWARE: the real execution unit
```

Key precision points (the common mistakes):

- **M is an OS thread, not a CPU core.** The OS schedules Ms onto logical CPUs.
- **P is software, not hardware.** It is a runtime data structure — a permit + a local run queue. An **M must hold a P to run Go code**.
- **P count = `GOMAXPROCS`**, defaulting to `runtime.NumCPU()` = the number of **logical CPUs** (hyperthreads counted), *not* physical cores. It bounds how many goroutines run in parallel.
- **Counts:** G ≫ M ≥ P. G up to millions; M dynamic (default cap 10,000); P fixed at GOMAXPROCS.

Analogy: **P = a work desk** (there are GOMAXPROCS desks). **M = a worker** who must sit at a desk to do Go work. **G = a task**. More workers than desks (Ms blocked in syscalls) just wait without a desk.

## Run queues: per-P local + global

- Each **P has its own local run queue (LRQ)** — a fixed-size (256) ring buffer plus a **`runnext`** slot for the single next goroutine (a locality optimization: a freshly created child is cache-hot and often run immediately).
- There is one shared **global run queue (GRQ)** as a fallback/overflow, protected by a lock.

`go func()` and goroutine switching push/pop the **local** queue with **no lock** (only the owning M touches it). This is the crux of the design.

## Why GMP instead of G-M

The old scheduler was **G-M with a single global run queue behind one global lock**:

```
G-M:  every go / switch / wakeup → LOCK the one global queue → serialized
      8 cores all fight over ONE lock → contention + the lock's cache line
      bounces across every core (see [[Cache Coherence and MESI]]) → does not scale
```

Adding **P with per-core local queues** removed the bottleneck:

```
GMP:  every go / switch → this P's OWN local queue → NO global lock → parallel per core
      global lock only on overflow; stealing via atomic CAS → scales with cores
```

Because a P is owned by one M at a time, the common scheduling path is lock-free. This is the single most important "why GMP" point.

## Work stealing

When a P's local queue empties, before idling the M looks for work in order:
1. the **global queue** (lock),
2. the **netpoller** (ready network I/O — below),
3. **steal half** the goroutines from another random P's local queue.

Stealing touches another P's queue, so it uses **atomic compare-and-swap** on the queue head/tail rather than a mutex — lock-free rebalancing (see [[Compare-and-Swap]]). No P idles while another has a backlog, with no central coordinator.

## Blocking syscall: P handoff

Some syscalls cannot be made async (file/disk I/O, CGo, certain OS calls). The thread genuinely blocks, so the runtime rescues the P:

```
1. G1 on M1 (holding P1) makes a BLOCKING syscall.
2. entersyscall(): P1 becomes detachable.
3. M1 BLOCKS in the kernel (with G1).                 ← this OS thread is stuck
4. sysmon hands P1 to another M → runs P1's OTHER goroutines.  ← parallelism slot rescued
5. exitsyscall(): M1 tries to reacquire a P:
     • a P is free  → grab it, resume G1
     • none free    → G1 goes to a run queue, M1 parks (idle pool)
```

The blocked **G1 stays with the blocked M1**; the handed-off P runs the *rest* of the queue. Optimization: fast syscalls keep their P (no handoff); sysmon only hands off after ~20µs. This is why there can be far more Ms than Ps — each syscall-blocked M holds no P.

## Network I/O: the netpoller

Network I/O *can* be made async, so it never blocks a thread. Go sets network fds to non-blocking and integrates with the OS event system — **epoll** (Linux), **kqueue** (BSD/macOS), **IOCP** (Windows) — the **netpoller**:

```
1. G1 calls conn.Read(), data not ready.
2. Runtime PARKS G1, registers its fd with epoll.
3. M is FREE → runs other goroutines.                ← no thread blocked
4. Kernel marks fd ready → netpoll() returns G1 as runnable → back on a run queue.
5. G1 resumes; the Read now succeeds.
```

`netpoll()` is a non-blocking `epoll_wait` — a kernel-event source of runnable goroutines, distinct from the mutex-guarded global queue. `sysmon` also runs netpoll periodically so I/O-ready goroutines get scheduled even when all Ps are busy. This is why a few threads serve 100k connections with blocking-looking code.

**Netpoller vs syscall handoff** — two mechanisms for two situations:

| | Netpoller (network) | Blocking syscall (file/CGo) |
| --- | --- | --- |
| M blocks? | No — freed to run other Gs | Yes — stuck in the kernel |
| The G | parked, woken by netpoll | stays with the blocked M |
| The P | stays with the M | **handed off** to another M |
| Cost | ~nothing (async) | one OS thread, briefly |

## Preemption

- **Pre-1.14: cooperative.** A goroutine could only be preempted at function-call boundaries, so a tight `for {}` loop with no calls could **hog its P forever** (and stall GC).
- **1.14+: asynchronous.** The **`sysmon`** thread notices a goroutine running >10ms and sends its M a **signal (`SIGURG`)**; the handler preempts the goroutine mid-instruction. Even a call-free loop gets preempted. (`sysmon` also retakes Ps from long syscalls, runs background netpoll, and triggers GC.)

## Interview answer to "介绍一下GMP"

**30-second:** GMP is Go's scheduler. G = goroutine (lightweight, ~2KB growable stack, cheap by the millions); M = OS thread that executes; P = a logical processor holding a local run queue, and an **M must hold a P to run Go code**. P count = `GOMAXPROCS` ≈ logical CPUs, bounding parallelism. In count G ≫ M ≥ P. It multiplexes many cheap goroutines onto few threads with parallelism P.

**Add for senior depth:** each P has a **local run queue** so `go func()` is lock-free — this replaced the old G-M model's **single global lock** that didn't scale; empty Ps **steal** work; a **blocking syscall hands off its P** to another M while **network I/O parks goroutines via the netpoller**; and **sysmon async-preempts** goroutines running over 10ms.

## Interview summary

> GMP is the Go scheduler: G = goroutine (lightweight), M = OS thread (executes), P = logical processor (a permit plus a local run queue; count = GOMAXPROCS ≈ logical CPUs). An M must hold a P to run Go code, so P bounds parallelism; G ≫ M ≥ P. Each P has a local run queue, making goroutine creation and switching lock-free — the reason P was added over the old G-M model, whose single global-lock queue caused contention and cache-line bouncing. Empty Ps steal work via atomic CAS. A blocking syscall blocks its M but hands off its P to another M; network I/O parks goroutines and wakes them via the netpoller (epoll/kqueue) without blocking a thread. Since Go 1.14, sysmon async-preempts long-running goroutines via signals.

## Related notes

- [[Go Scheduler]]
- [[Compare-and-Swap]]
- [[Cache Coherence and MESI]]
- [[Mutex]]
- [[Concurrency vs Parallelism]]
- [[Goroutines and Channels]]
