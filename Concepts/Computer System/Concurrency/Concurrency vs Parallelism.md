---
date: 2026-06-27
tags:
  - concurrency
  - parallism
  - scheduling
  - backend
---
## One-sentence meaning

Concurrency is about managing multiple tasks that are in progress at the same time, while parallelism is about actually executing multiple tasks at the same time on different hardware resources.

## Core distinction

```text
Concurrency = dealing with many tasks at once
Parallelism = doing many tasks at once
```

Concurrency is a program structure / scheduling idea.

Parallelism is a hardware execution idea.

## Chef analogy

One chef cooking three dishes by switching between them:

```text
Concurrency, but not parallelism
```

Three chefs cooking three dishes at the same time:

```text
Concurrency and parallelism
```

## Concurrency

A concurrent program can make progress on multiple tasks by switching between them.

Example:

```text
Task A waits for database
Task B handles another request
Task C waits for network
Task D writes response
```

Even on one CPU core, concurrency is useful because many backend tasks spend time waiting for I/O.

Examples of concurrency mechanisms:

- OS threads
    
- goroutines
    
- coroutines
    
- async/await
    
- event loops
    
- virtual threads
    

## Parallelism

Parallelism means multiple pieces of work are literally running at the same time.

This requires hardware support such as:

- multiple CPU cores
    
- multiple hardware threads
    
- GPU cores
    
- multiple machines
    

Example:

```text
8 CPU cores can execute up to 8 CPU-bound threads truly simultaneously.
```

More tasks than cores can still exist, but the runtime or OS must schedule them.

## Concurrent but not parallel

A program can be concurrent but not parallel.

Example:

```text
One CPU core
Many goroutines
Runtime switches between goroutines
Only one goroutine is executing at any exact moment
```

This is still useful because when one task blocks on I/O, another task can run.

## Parallel but not obvious from programmer perspective

A program can look sequential but use parallelism internally.

Example:

```go
result := library.ComputeHugeMatrix(x)
```

This function call looks synchronous. But inside the library, it may use many worker threads or CPU cores.

So from the programmer’s surface code, it may not look concurrent, but the implementation may use parallelism internally.

## Why backend systems care about concurrency

Backend servers often handle many requests at the same time.

Even if each request is simple, requests may wait on:

- database
    
- Redis
    
- filesystem
    
- network
    
- remote APIs
    
- message queues
    

Concurrency lets the server avoid wasting time while one request is waiting.

Example:

```text
Request A waits for PostgreSQL
Request B can be handled
Request C waits for Redis
Request D can continue
```

## Important mental model

Concurrency is especially valuable for I/O-bound work.

Parallelism is especially valuable for CPU-bound work.

```text
I/O-bound service:
  concurrency helps a lot

CPU-bound computation:
  parallelism helps a lot
```

## Related notes

- [[Goroutines and Channels]]
    
- [[Thread]]
    
- [[Process]]
    
- [[Async Await]]
    
- [[Event Loop]]
    
- [[I/O Bound vs CPU Bound]]
    
- [[Go Scheduler]]