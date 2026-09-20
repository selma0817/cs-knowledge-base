---
date: 2026-06-29
tags:
  - go
  - goroutine
  - scheduler
  - runtime
  - gomaxprocs
  - concurrency
  - parallism
aliases:
  - go scheduler
  - go runtime scheduler
  - G-M-P scheduler
---
## One-sentence meaning

The Go scheduler is the runtime system that decides which goroutines run on which OS threads and CPU cores.

## Why I care

When I write:

```go
go worker()
```

I am not directly creating an OS thread.

I am creating a **goroutine**.

The Go runtime scheduler is responsible for running many goroutines over a smaller number of OS threads.

Mental model:

```text
many goroutines
  ↓
Go scheduler
  ↓
OS threads
  ↓
CPU cores
```

This is why Go can support large numbers of concurrent tasks more easily than manually creating one OS thread per task.

## Function call vs goroutine

A normal function call runs in the current goroutine:

```go
worker()
```

Meaning:

```text
same goroutine
caller waits
worker returns
caller continues
```

A goroutine call starts a new goroutine:

```go
go worker()
```

Meaning:

```text
new goroutine starts worker
current goroutine continues immediately
```

A helper function is not automatically a goroutine just because it is outside `main`.

Only the `go` keyword creates a new goroutine.

```text
helper()     same goroutine
go helper()  new goroutine
```

## Main goroutine

When a Go program starts, the runtime creates the initial goroutine and runs:

```go
func main() {
    ...
}
```

This is often called the **main goroutine**.

If `main()` returns, the whole program exits.

Other goroutines do not keep the process alive.

Example:

```go
func main() {
    go fmt.Println("hello")
}
```

This may print nothing, because `main` may exit before the new goroutine gets scheduled.

To wait for goroutines, use tools like:

```text
sync.WaitGroup
channels
context cancellation
```

## G-M-P model

> For the deep internals — per-P local run queues, why P replaced the old G-M model, work stealing, blocking-syscall P handoff, the netpoller, and async preemption — see [[GMP Scheduler Internals]]. The summary below is the usage-level mental model.

Go scheduler internals are often explained using three letters:

```text
G = goroutine
M = machine / OS thread
P = processor / runtime scheduling resource
```

### G: goroutine

A goroutine is a lightweight concurrent function execution.

Example:

```go
go doWork()
```

This creates a new goroutine.

### M: machine / OS thread

An `M` is an actual OS thread.

The operating system schedules OS threads onto CPU cores.

### P: processor / runtime execution resource

A `P` is a Go runtime resource needed to execute Go code.

A goroutine can run only when an `M` has a `P`.

Simple mental model:

```text
G = work to run
M = OS thread that can run code
P = permission/resources to run Go code
```

Or:

```text
G waits in a queue
P picks runnable Gs
M executes them on CPU cores
```

## GOMAXPROCS

`GOMAXPROCS` controls how many OS threads can execute user-level Go code at the same time.

Simple version:

```text
GOMAXPROCS ≈ max parallel Go execution slots
```

If `GOMAXPROCS = 1`, many goroutines can still exist, but only one thread executes Go code at a time.

That means the program can be concurrent but not truly parallel for Go code.

If `GOMAXPROCS = 8`, up to 8 OS threads can execute Go code at the same time, assuming enough runnable goroutines and CPU capacity.

Important:

```text
GOMAXPROCS limits parallel execution of Go code.
It does not limit the total number of goroutines.
It also does not mean there are only that many OS threads total.
```

Some OS threads may be blocked in system calls and not count against active Go execution in the same way.

## Concurrency vs parallelism

Go goroutines give concurrency.

Parallelism depends on available CPU cores and `GOMAXPROCS`.

```text
Concurrency:
  many tasks are in progress

Parallelism:
  many tasks are literally running at the same instant
```

Example:

```go
go taskA()
go taskB()
```

This creates concurrency.

Whether `taskA` and `taskB` run in parallel depends on the scheduler, CPU cores, and `GOMAXPROCS`.

## What happens when a goroutine blocks?

A goroutine can block on:

```text
channel send
channel receive
mutex lock
network I/O
sleep
system call
```

Example:

```go
x := <-ch
```

This goroutine waits until some other goroutine sends on `ch`.

The scheduler can run other goroutines while this one is blocked.

This is one of Go's main strengths:

```text
blocking one goroutine does not necessarily block the whole program
```

## Network I/O and scheduler

When a goroutine waits on network I/O, the Go runtime can park that goroutine and run other goroutines.

Mental model:

```text
goroutine A waits for network
scheduler parks A
scheduler runs goroutine B
network becomes ready
scheduler makes A runnable again
```

This is why Go backend servers can handle many concurrent requests with relatively simple blocking-looking code.

## Go vs Python async/await

Go goroutine model:

```go
go fetch()
```

Meaning:

```text
start fetch in another goroutine
current goroutine continues immediately
```

Python async/await model:

```python
await fetch()
```

Meaning:

```text
pause this async task
let the event loop run other tasks
resume when fetch is ready
```

Closer Python equivalent to `go fetch()`:

```python
asyncio.create_task(fetch())
```

But they are still different.

Python async tasks usually need explicit `await` points to yield control.

Go goroutines are scheduled by the Go runtime, and normal blocking-looking code can still be concurrent.

## Go vs Java threads / virtual threads

Go goroutines are closer to Java virtual threads than classic OS threads.

Rough mapping:

```text
Go goroutine       ≈ Java virtual thread / lightweight task
Go scheduler       ≈ runtime scheduler
OS thread          ≈ actual kernel thread
GOMAXPROCS         ≈ limit on parallel Go execution
```

Classic Java thread pool thinking:

```text
many tasks
fixed number of OS threads
tasks submitted to executor
```

Go thinking:

```text
many goroutines
runtime scheduler multiplexes them onto OS threads
use worker pool only when I need bounded concurrency
```

## Does Go need worker pools?

Sometimes yes, sometimes no.

Because goroutines are lightweight, Go code often starts goroutines directly.

Example:

```go
go handleConnection(conn)
```

This is normal.

But worker pools are still common when I need to limit concurrency.

Use a worker pool when:

```text
there are many jobs
external resources are limited
I need backpressure
I want only N jobs running at once
```

Examples:

```text
limit database writes
limit API calls
process a large queue
crawl many URLs
resize many images
run CPU-heavy tasks with bounded parallelism
```

Do not use a worker pool just because Java would use an `ExecutorService`.

In Go, first ask:

```text
Do I need to bound concurrency?
Do I need backpressure?
Do I need to limit resource usage?
```

If yes, a worker pool is useful.

If no, plain goroutines may be simpler.

## Scheduler does not guarantee order

Starting a goroutine does not guarantee when it runs.

Example:

```go
func main() {
    go fmt.Println("worker")
    fmt.Println("main")
}
```

Possible output:

```text
main
```

or:

```text
worker
main
```

or:

```text
main
worker
```

The scheduler decides when the goroutine runs, and `main` may exit early.

To guarantee completion, use `WaitGroup`.

To guarantee ordering, use channels or other synchronization.

## WaitGroup vs scheduler

The scheduler decides when goroutines run.

`sync.WaitGroup` lets one goroutine wait until others finish.

```go
var wg sync.WaitGroup

wg.Add(1)
go func() {
    defer wg.Done()
    doWork()
}()

wg.Wait()
```

`WaitGroup` does not control scheduling order.

It only guarantees that `wg.Wait()` blocks until the counter returns to zero.

## Channel synchronization and scheduler

Channels can create ordering.

Example:

```go
done := make(chan bool)

go func() {
    fmt.Println("worker")
    done <- true
}()

<-done
fmt.Println("main after wait")
```

Guaranteed:

```text
worker before main after wait
```

Why?

Because the worker prints before sending on `done`, and main cannot continue until it receives from `done`.

But this version is different:

```go
done := make(chan bool)

go func() {
    done <- true
    fmt.Println("worker")
}()

<-done
fmt.Println("main after wait")
```

Now `worker` is not guaranteed before `main after wait`, because the print happens after the channel handoff.

The scheduler may run main first after the send/receive completes.

## Common misunderstandings

### Misunderstanding 1: A function outside main is automatically concurrent

Wrong:

```go
func helper() {}

func main() {
    helper()
}
```

`helper()` runs in the main goroutine.

Only this creates a new goroutine:

```go
go helper()
```

### Misunderstanding 2: `go f()` waits for `f`

Wrong.

```go
go f()
```

starts `f` and immediately continues.

Use `WaitGroup` or channel receive to wait.

### Misunderstanding 3: Goroutine means parallel

Not always.

Goroutine means concurrent.

Parallelism depends on CPU cores, runnable goroutines, blocking state, and `GOMAXPROCS`.

### Misunderstanding 4: Worker pool is always required

Not true.

Go already has lightweight goroutines.

Worker pools are mainly for bounded concurrency and backpressure.

### Misunderstanding 5: Scheduler gives deterministic order

Wrong.

Across goroutines, order is not guaranteed unless synchronization creates order.

## Backend mental model

For a Go backend service:

```text
HTTP request arrives
server may handle request in a goroutine
request handler may start more goroutines
scheduler runs goroutines over OS threads
blocking I/O parks goroutines
other goroutines continue
```

This is why Go is popular for network services:

```text
simple blocking-looking code
many concurrent requests
runtime handles scheduling complexity
```

## Key memory

```text
A goroutine is not an OS thread.

The Go scheduler multiplexes goroutines onto OS threads.

A function call is not a goroutine unless prefixed with `go`.

GOMAXPROCS controls how many OS threads can execute Go code at the same time.

The scheduler does not guarantee ordering.

Use WaitGroup for completion.

Use channels for communication and ordering.

Use worker pools when I need bounded concurrency, not automatically for every task.
```

## Related notes

- [[GMP Scheduler Internals]]
- [[Goroutines and Channels]]
    
- [[sync.WaitGroup]]
    
- [[Worker Pool]]
    
- [[Concurrency vs Parallelism]]
    
- [[Value Pointer and Ownership]]
    
- [[JVM vs Python VM]]
    
- [[Compiler vs Interpreter]]