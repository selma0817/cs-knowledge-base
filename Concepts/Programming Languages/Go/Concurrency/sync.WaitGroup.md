---
date: 2026-06-29
tags:
  - go
  - goroutine
  - waitgroup
  - concurrency
  - syncronization
---
## One-sentence meaning

`sync.WaitGroup` is a Go synchronization tool that lets one goroutine wait until a group of other goroutines have finished.

## Why I care

When I start goroutines with `go f()`, the caller does **not** wait automatically.

```go
go worker()
fmt.Println("main continues immediately")
```

If `main()` returns too early, the whole Go program exits, even if other goroutines have not finished.

`sync.WaitGroup` solves this by letting `main` wait for goroutines to complete.

## Mental model

A `WaitGroup` is like a counter.

```text
wg.Add(n)    increase counter by n
wg.Done()    decrease counter by 1
wg.Wait()    block until counter becomes 0
```

Java analogy:

```text
sync.WaitGroup ≈ CountDownLatch
```

But unlike Java `CountDownLatch`, Go’s `WaitGroup` counter can be incremented with `Add`.

## Basic example

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
        fmt.Println("worker finished")
    }()

    wg.Wait()
    fmt.Println("main finished")
}
```

Execution idea:

```text
main goroutine:
  create WaitGroup
  Add(1), meaning "I am waiting for 1 goroutine"
  start worker goroutine
  Wait()

worker goroutine:
  print "worker finished"
  Done(), meaning "one goroutine is finished"

main goroutine:
  Wait() unblocks
  print "main finished"
```

Guaranteed ordering:

```text
worker finished
main finished
```

Because `main` cannot pass `wg.Wait()` until the worker calls `wg.Done()`.

## `defer wg.Done()`

This pattern is very common:

```go
go func() {
    defer wg.Done()

    // work here
}()
```

`defer wg.Done()` means:

```text
Call wg.Done() when this function exits.
```

This is safer than manually putting `wg.Done()` at the end, because it still runs if the function returns early.

Example:

```go
go func() {
    defer wg.Done()

    if somethingBad {
        return
    }

    doWork()
}()
```

Even if the function returns early, `wg.Done()` still runs.

## Add before starting the goroutine

Usually, call `wg.Add(1)` before `go`.

Good:

```go
wg.Add(1)
go func() {
    defer wg.Done()
    doWork()
}()
```

Risky:

```go
go func() {
    wg.Add(1)
    defer wg.Done()
    doWork()
}()
wg.Wait()
```

The risky version can be wrong because `main` might call `wg.Wait()` before the goroutine gets scheduled and calls `wg.Add(1)`.

Safe rule:

```text
Add before go.
Done inside goroutine.
Wait after starting goroutines.
```

## Waiting for many goroutines

```go
package main

import (
    "fmt"
    "sync"
)

func worker(id int, wg *sync.WaitGroup) {
    defer wg.Done()

    fmt.Println("worker", id, "done")
}

func main() {
    var wg sync.WaitGroup

    for i := 1; i <= 3; i++ {
        wg.Add(1)
        go worker(i, &wg)
    }

    wg.Wait()
    fmt.Println("all workers done")
}
```

Important detail:

```go
go worker(i, &wg)
```

We pass `&wg`, a pointer to the `WaitGroup`.

All workers must share the same `WaitGroup`.

## Do not copy a WaitGroup after use

This is bad:

```go
func worker(wg sync.WaitGroup) {
    defer wg.Done()
}
```

This copies the `WaitGroup`.

The worker decrements its own copy, not the original one that `main` is waiting on.

Better:

```go
func worker(wg *sync.WaitGroup) {
    defer wg.Done()
}
```

Mental rule:

```text
Pass WaitGroup by pointer.
Do not copy it after use.
```

## WaitGroup guarantees completion, not ordering

This code waits for both goroutines to finish:

```go
var wg sync.WaitGroup

wg.Add(2)

go func() {
    defer wg.Done()
    fmt.Println("A")
}()

go func() {
    defer wg.Done()
    fmt.Println("B")
}()

wg.Wait()
fmt.Println("done")
```

Guaranteed:

```text
A and B both print before done.
```

Not guaranteed:

```text
A before B
```

Possible output:

```text
A
B
done
```

or:

```text
B
A
done
```

So:

```text
WaitGroup controls completion.
WaitGroup does not control order.
```

If I need ordering, I need channels, locks, or normal function calls.

## WaitGroup does not return results

`WaitGroup` only waits.

It does not carry values.

For results, use channels or shared state protected by a mutex.

Example with results channel:

```go
results := make(chan int)

wg.Add(1)
go func() {
    defer wg.Done()
    results <- 42
}()
```

But now I must also think about channel blocking and closing.

## WaitGroup does not handle errors or cancellation

`WaitGroup` does not directly solve:

```text
How do I return errors?
How do I cancel other goroutines?
How do I stop work after timeout?
```

For those, common tools include:

```text
error channels
context.Context
errgroup.Group
```

`errgroup.Group` is like a higher-level version of `WaitGroup` that can collect errors and work with context cancellation.

## Common mistakes

### Mistake 1: forgetting `Done`

Bad:

```go
wg.Add(1)

go func() {
    doWork()
}()

wg.Wait()
```

This deadlocks because the counter never reaches 0.

Good:

```go
wg.Add(1)

go func() {
    defer wg.Done()
    doWork()
}()

wg.Wait()
```

### Mistake 2: calling `Done` too many times

Bad:

```go
wg.Add(1)

go func() {
    wg.Done()
    wg.Done()
}()
```

This can panic because the counter goes negative.

### Mistake 3: adding inside the goroutine

Risky:

```go
go func() {
    wg.Add(1)
    defer wg.Done()
}()
wg.Wait()
```

Good:

```go
wg.Add(1)
go func() {
    defer wg.Done()
}()
wg.Wait()
```

### Mistake 4: using WaitGroup to force print order

`WaitGroup` waits for completion, but it does not guarantee which worker runs first.

If order matters, use explicit synchronization.

## Relationship to channels

`WaitGroup` and channels solve different problems.

```text
WaitGroup:
  Wait until goroutines finish.

Channel:
  Send values, signals, or ownership between goroutines.
```

Sometimes they are used together:

```text
workers send results to results channel
WaitGroup waits until workers finish
closer goroutine closes results after wg.Wait()
main ranges over results
```

## Related notes

- [[Goroutines and Channels]]
    
- [[Worker Pool]]
    
- [[Concurrency vs Parallelism]]
    
- [[Value Pointer and Ownership]]
    
- [[Java Threads and Executors]]