---
date: 2026-06-29
tags:
  - go
  - goroutine
  - channel
  - worker-pool
  - waitgroup
  - concurrency
aliases:
  - go-workerpool
  - worker pool pattern
---
## One-sentence meaning

A worker pool is a concurrency pattern where a fixed number of worker goroutines pull jobs from a shared jobs channel and send results to a results channel.

## Why I care

In backend systems, I often have many independent tasks:

```text
process many URLs
handle many images
call many APIs
consume many queue messages
run many database-related jobs
```

Starting one goroutine per task can be too uncontrolled.

A worker pool limits concurrency:

```text
1000 jobs
10 workers
only 10 jobs run at the same time
```

This is similar to using a fixed-size `ExecutorService` in Java.

## Java mental model

Go worker pool:

```text
jobs channel      ≈ BlockingQueue<Job>
worker goroutines ≈ fixed thread pool workers
results channel   ≈ BlockingQueue<Result>
```

Java-like idea:

```java
ExecutorService executor = Executors.newFixedThreadPool(3);
```

Go-like idea:

```go
for i := 1; i <= 3; i++ {
    go worker(i, jobs, results, &wg)
}
```

## Core roles

A clean Go worker pool usually has four roles:

```text
producer goroutine:
  sends jobs
  closes jobs

worker goroutines:
  receive jobs
  process jobs
  send results

closer goroutine:
  waits for all workers
  closes results

main goroutine:
  receives results
```

This role separation prevents circular blocking.

## Complete example

```go
package main

import (
    "fmt"
    "sync"
)

func worker(id int, jobs <-chan int, results chan<- int, wg *sync.WaitGroup) {
    defer wg.Done()

    for job := range jobs {
        fmt.Println("worker", id, "processing job", job)
        results <- job * 2
    }
}

func main() {
    jobs := make(chan int)
    results := make(chan int)

    var wg sync.WaitGroup

    // Start 3 workers.
    for i := 1; i <= 3; i++ {
        wg.Add(1)
        go worker(i, jobs, results, &wg)
    }

    // Producer goroutine.
    go func() {
        for j := 1; j <= 5; j++ {
            jobs <- j
        }
        close(jobs)
    }()

    // Closer goroutine.
    go func() {
        wg.Wait()
        close(results)
    }()

    // Result consumer.
    for result := range results {
        fmt.Println("result:", result)
    }
}
```

## Channel direction syntax

The worker function uses directional channels:

```go
func worker(id int, jobs <-chan int, results chan<- int, wg *sync.WaitGroup)
```

Meaning:

```go
jobs <-chan int
```

`jobs` is receive-only inside `worker`.

The worker can do:

```go
job := <-jobs
```

but cannot do:

```go
jobs <- 1
```

And:

```go
results chan<- int
```

`results` is send-only inside `worker`.

The worker can do:

```go
results <- value
```

but cannot do:

```go
value := <-results
```

This makes the function contract clearer:

```text
worker receives jobs
worker sends results
```

## Why workers use `range jobs`

Workers usually loop over the jobs channel:

```go
for job := range jobs {
    results <- job * 2
}
```

This means:

```text
Keep receiving jobs until jobs is closed and drained.
```

So the producer must eventually close `jobs`:

```go
close(jobs)
```

This tells workers:

```text
No more jobs will be sent.
Exit after finishing the remaining jobs.
```

If `jobs` is never closed, workers can wait forever.

## Why use WaitGroup

Each worker calls:

```go
defer wg.Done()
```

The closer goroutine does:

```go
wg.Wait()
close(results)
```

This means:

```text
Wait until all workers are done.
Then close results.
```

We need this because `main` uses:

```go
for result := range results {
    fmt.Println(result)
}
```

`range results` ends only when `results` is closed and drained.

## Why close `results` after `wg.Wait()`

Only close a channel when nobody will send to it again.

Workers send to `results`:

```go
results <- job * 2
```

Therefore, `results` must not be closed until all workers are finished.

Bad:

```go
close(results)
results <- 10 // panic: send on closed channel
```

Safe:

```go
go func() {
    wg.Wait()
    close(results)
}()
```

## Why main should not close `results`

`main` is the receiver of `results`.

Workers are the senders of `results`.

General rule:

```text
Sender closes channel.
Receiver ranges over channel.
```

If `main` closes `results` too early, a worker might send to a closed channel and panic.

## Important deadlock pattern

This version can deadlock:

```go
for j := 1; j <= 5; j++ {
    jobs <- j
}
close(jobs)

for result := range results {
    fmt.Println(result)
}
```

Why?

Because `main` tries to send all jobs before receiving any results.

With unbuffered channels, workers may get stuck sending results while `main` is still trying to send more jobs.

Blocked state:

```text
main:
  blocked sending a job to jobs

workers:
  blocked sending results to results
```

Core rule:

```text
If results is unbuffered, some goroutine must receive results while workers are sending.
```

That is why job production is often moved into its own goroutine:

```go
go func() {
    for j := 1; j <= 5; j++ {
        jobs <- j
    }
    close(jobs)
}()
```

Now `main` is free to receive results.

## Result order is not guaranteed

Jobs may be sent in order:

```text
1, 2, 3, 4, 5
```

But with multiple workers, results may arrive out of order:

```text
2, 6, 4, 10, 8
```

Why?

Because different workers may finish at different times.

So:

```text
Job submission order is not necessarily result completion order.
```

If result order matters, attach an index.

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

## Buffered vs unbuffered channels

Unbuffered:

```go
jobs := make(chan int)
results := make(chan int)
```

Meaning:

```text
send and receive must meet
strong synchronization
easier to expose deadlocks
```

Buffered:

```go
results := make(chan int, 5)
```

Meaning:

```text
up to 5 results can wait in the channel
send blocks only when buffer is full
receive blocks only when buffer is empty
```

Buffered channels can reduce blocking, but they do not remove the need to reason about ownership, closing, and backpressure.

## Worker pool as backpressure

A worker pool creates backpressure.

If workers are busy, sending into `jobs` may block.

This can be good.

It prevents the producer from creating unlimited work faster than workers can process it.

```text
producer too fast
jobs channel blocks
producer slows down
system avoids unbounded memory growth
```

## Common mistakes

### Mistake 1: not closing jobs

Bad:

```go
for j := 1; j <= 5; j++ {
    jobs <- j
}
// missing close(jobs)
```

Workers using `range jobs` may wait forever.

### Mistake 2: not closing results

Bad if main ranges over results:

```go
for result := range results {
    fmt.Println(result)
}
```

If `results` is never closed, this loop never ends.

### Mistake 3: closing results too early

Bad:

```go
close(results)
```

while workers may still send.

This can cause:

```text
panic: send on closed channel
```

### Mistake 4: assuming ordered results

With multiple workers, results are concurrent and may arrive out of order.

### Mistake 5: using main as both job producer and result consumer

This can deadlock with unbuffered channels.

Better:

```text
producer goroutine sends jobs
main goroutine receives results
```

## When to use a worker pool

Use a worker pool when:

```text
many independent jobs exist
I want bounded concurrency
I want to avoid starting unlimited goroutines
each job can be processed independently
result order is not critical or can be reconstructed
```

Examples:

```text
fetch many URLs
resize many images
process queue messages
validate many files
run many independent API calls
```

## Related notes

- [[Goroutines and Channels]]
    
- [[sync.WaitGroup]]
    
- [[Concurrency vs Parallelism]]
    
- [[Value Pointer and Ownership]]
    
- [[Java Threads and Executors]]