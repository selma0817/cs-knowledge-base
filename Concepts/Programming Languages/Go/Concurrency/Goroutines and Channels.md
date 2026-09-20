---
date: 2026-06-27
tags:
  - go
  - goroutine
  - channel
  - concurrency
  - scheduler
---
## One-sentence meaning

A goroutine is a lightweight concurrent execution unit managed by the Go runtime, and a channel is a typed communication mechanism used to send values between goroutines.

## Goroutine mental model

A goroutine is like a lightweight virtual thread managed by the Go runtime.

```go
go doWork()
```

This starts `doWork` in a new goroutine and immediately continues. It does not wait for `doWork` to finish.

## Goroutine vs OS thread

|Concept|OS thread|Goroutine|
|---|---|---|
|Managed by|Operating system|Go runtime|
|Creation cost|More expensive|Cheaper|
|Stack size|Larger initial stack|Small growing stack|
|Scheduling|OS scheduler|Go scheduler|
|Typical usage|Lower-level execution unit|Many concurrent tasks|

The Go runtime multiplexes many goroutines onto fewer OS threads.

## Important example

```go
func main() {
    go fmt.Println("hello")
}
```

Problem:

```text
main may exit before the goroutine runs.
```

The program ends when the main goroutine returns. Other goroutines do not keep the process alive.

## Waiting for goroutines

A common tool is `sync.WaitGroup`.

```go
package main

import (
    "fmt"
    "sync"
)

func main() {
    var wg sync.WaitGroup

    wg.Add(1)

    go func() {
        defer wg.Done()
        fmt.Println("hello")
    }()

    wg.Wait()
}
```

Mental model:

```text
wg.Add(1)   = one task to wait for
wg.Done()   = task finished
wg.Wait()   = block until all tasks are done
```

## Go scheduler

The Go scheduler decides which goroutines run on which OS threads.

Rough mental model:

```text
many goroutines
  ↓ Go scheduler
some OS threads
  ↓ OS scheduler
CPU cores
```

A common model is:

```text
G = goroutine
M = machine / OS thread
P = processor / runtime scheduling context
```

## GOMAXPROCS

`GOMAXPROCS` controls roughly how many OS threads can execute Go code at the same time.

If `GOMAXPROCS = 1`, Go can still have many goroutines, but only one is executing Go code at a time.

If `GOMAXPROCS = 8`, up to 8 goroutines may execute Go code in parallel, assuming enough CPU cores.

## Channel mental model

A channel is a typed pipe between goroutines.

```go
ch := make(chan int)
```

This creates a channel that sends and receives `int` values.

Send:

```go
ch <- 1
```

Receive:

```go
x := <-ch
```

## Unbuffered channel

```go
ch := make(chan int)
```

An unbuffered channel has no storage space.

A send blocks until a receiver is ready.

A receive blocks until a sender is ready.

```text
sender and receiver meet at the same time
```

Example:

```go
func main() {
    ch := make(chan int)

    go func() {
        ch <- 42
    }()

    fmt.Println(<-ch)
}
```

This works because the goroutine sends while main receives.

This deadlocks:

```go
func main() {
    ch := make(chan int)

    ch <- 42
    fmt.Println(<-ch)
}
```

Why?

```text
main tries to send to an unbuffered channel
but no other goroutine is ready to receive
so main blocks forever
```

## Buffered channel

```go
ch := make(chan int, 1)
```

A buffered channel has storage capacity.

```go
func main() {
    ch := make(chan int, 1)

    ch <- 42
    fmt.Println(<-ch)
}
```

This works because the channel has buffer space for one value.

Buffered channel rules:

```text
send blocks when buffer is full
receive blocks when buffer is empty
```

## Closing channels

```go
close(ch)
```

Closing a channel means:

```text
No more values will be sent on this channel.
```

The sender usually closes the channel.

The receiver usually should not close it, because the receiver may not know whether other senders still need to send.

## Receiving from a closed channel

```go
v, ok := <-ch
```

If `ok == true`, a value was received.

If `ok == false`, the channel is closed and drained.

After a channel is closed, receiving gives the zero value of the channel type.

Example:

```go
v, ok := <-ch
if !ok {
    fmt.Println("channel closed")
}
```

## Range over channel

```go
for v := range ch {
    fmt.Println(v)
}
```

This keeps receiving values until the channel is closed.

Common pattern:

```go
func producer(ch chan int) {
    defer close(ch)

    for i := 0; i < 5; i++ {
        ch <- i
    }
}

func main() {
    ch := make(chan int)

    go producer(ch)

    for v := range ch {
        fmt.Println(v)
    }
}
```

## select

`select` waits on multiple channel operations.

```go
select {
case v := <-ch1:
    fmt.Println("received", v)

case ch2 <- 10:
    fmt.Println("sent")

case <-time.After(time.Second):
    fmt.Println("timeout")
}
```

Mental model:

```text
select lets one goroutine wait on multiple possible channel events.
```

If multiple cases are ready, Go chooses one pseudo-randomly.

If none are ready, `select` blocks unless there is a `default` case.

## Worker pool pattern

```go
jobs := make(chan Job)
results := make(chan Result)

for i := 0; i < 5; i++ {
    go worker(jobs, results)
}
```

This starts 5 worker goroutines.

Mental model:

```text
jobs channel:
  main goroutine sends work

worker goroutines:
  receive jobs
  process jobs
  send results

results channel:
  main goroutine collects results
```

If nobody consumes from `results`, workers may block forever when trying to send results.

If nobody closes `jobs`, workers using `for job := range jobs` may wait forever for more jobs.



## Deadlock pattern: main sends all jobs before receiving results

A common mistake in Go worker-pool code is making `main` send all jobs first and only receive results later.

This can deadlock when both `jobs` and `results` are unbuffered channels.

### Problem example

```go
package main

import (
    "fmt"
    "sync"
)

func worker(id int, jobs <-chan int, results chan<- int, wg *sync.WaitGroup) {
    defer wg.Done()

    for job := range jobs {
        results <- job * 2
    }
}

func main() {
    jobs := make(chan int)
    results := make(chan int)

    var wg sync.WaitGroup

    for i := 1; i <= 3; i++ {
        wg.Add(1)
        go worker(i, jobs, results, &wg)
    }

    for j := 1; j <= 5; j++ {
        jobs <- j
    }
    close(jobs)

    go func() {
        wg.Wait()
        close(results)
    }()

    for result := range results {
        fmt.Println(result)
    }
}
```

This program can deadlock.

### Why it deadlocks

`main` is trying to play two roles:

```text
main:
  1. produce all jobs
  2. receive all results later
```

But workers cannot keep receiving jobs if they get stuck sending results.

Timeline:

```text
main starts 3 workers

main sends job 1
worker A receives job 1

main sends job 2
worker B receives job 2

main sends job 3
worker C receives job 3

main tries to send job 4
but all workers are busy processing/sending results

worker A tries to send result 2
but main is not receiving from results yet

worker B tries to send result 4
but main is not receiving from results yet

worker C tries to send result 6
but main is not receiving from results yet

deadlock
```

Blocked state:

```text
main:
  blocked on jobs <- 4

workers:
  blocked on results <- ...
```

The core issue:

```text
If results is unbuffered, somebody must be receiving results while workers are sending results.
```

### Correct pattern: separate producer from result consumer

A common Go fix is to put job production in its own goroutine, so `main` can receive results while jobs are being produced.

```go
package main

import (
    "fmt"
    "sync"
)

func worker(id int, jobs <-chan int, results chan<- int, wg *sync.WaitGroup) {
    defer wg.Done()

    for job := range jobs {
        results <- job * 2
    }
}

func main() {
    jobs := make(chan int)
    results := make(chan int)

    var wg sync.WaitGroup

    for i := 1; i <= 3; i++ {
        wg.Add(1)
        go worker(i, jobs, results, &wg)
    }

    go func() {
        for j := 1; j <= 5; j++ {
            jobs <- j
        }
        close(jobs)
    }()

    go func() {
        wg.Wait()
        close(results)
    }()

    for result := range results {
        fmt.Println(result)
    }
}
```

Now the roles are separated:

```text
producer goroutine:
  sends jobs
  closes jobs

worker goroutines:
  receive jobs
  send results

closer goroutine:
  waits for workers
  closes results

main goroutine:
  receives results
```

This prevents circular blocking.

### Why close `jobs`

Workers use:

```go
for job := range jobs {
    results <- job * 2
}
```

`range jobs` keeps receiving until `jobs` is closed and drained.

So the producer closes `jobs` to say:

```text
No more jobs will be sent.
Workers can exit after finishing all received jobs.
```

If `jobs` is never closed, workers may wait forever for more jobs.

### Why close `results` after `wg.Wait()`

The `results` channel should be closed only after all workers are done sending.

```go
go func() {
    wg.Wait()
    close(results)
}()
```

This means:

```text
Wait until every worker has exited.
Then close results.
```

This is important because sending to a closed channel causes a panic.

Bad:

```go
close(results)
results <- 10 // panic: send on closed channel
```

So the safe rule is:

```text
Close a channel only when you know nobody will send to it again.
```

Since workers are the senders of `results`, `results` should be closed only after all workers finish.

### Why `main` should not close `results`

`main` is the receiver of `results`.

The workers are the senders.

Usually, the sender side owns closing the channel.

If `main` closes `results` too early, a worker may later try to send:

```go
results <- job * 2
```

and the program will panic.

Better rule:

```text
Sender closes channel.
Receiver ranges over channel.
```

### Result order is not guaranteed

With multiple workers, result order may differ from job order.

Jobs may be sent in this order:

```text
1, 2, 3, 4, 5
```

But results may arrive as:

```text
2, 6, 4, 10, 8
```

because different workers may finish at different times.

If result order matters, attach an index:

```go
type Job struct {
    Index int
    Value int
}

type Result struct {
    Index int
    Value int
}
```

Then the receiver can reconstruct the original order.

### Java mental model

This is similar to Java code using blocking queues:

```text
jobs queue:
  producer puts jobs
  workers take jobs

results queue:
  workers put results
  main takes results
```

An unbuffered Go channel is like a zero-capacity handoff queue, similar in spirit to Java `SynchronousQueue`.

A buffered Go channel is more like a bounded `BlockingQueue`.

### Key memory

```text
Unbuffered channels require sender and receiver to meet.

If workers send results on an unbuffered channel,
some goroutine must be receiving results at the same time.

Do not make main send all jobs first and receive all results later
unless results is buffered enough or another goroutine is receiving.
```


## Related notes

- [[Concurrency vs Parallelism]]
    
- [[Value Pointer and Ownership]]
    
- [[Go Scheduler]]
    
- [[sync.WaitGroup]]
    
- [[sync.Mutex]]
    
- [[Context in Go]]
    
- [[Worker Pool]]