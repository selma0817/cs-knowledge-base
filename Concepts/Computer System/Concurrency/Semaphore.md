---
date: 2026-08-15
aliases:
  - semaphore
---
A **semaphore** is a synchronization primitive that manages a fixed number of permits. A task must acquire a permit before entering the limited region and release it afterward.

```text
permits available > 0 -> acquire one and continue
permits available = 0 -> wait
release               -> return a permit and wake a waiter when needed
```

The availability check and decrement must be atomic so two tasks cannot consume the same final permit.

## When to use a semaphore

Use a semaphore to represent limited concurrent capacity:

- Five database connections
- Three GPU execution slots
- Ten simultaneous calls to an external API
- A bounded number of expensive file-processing operations

A semaphore controls **how many tasks may be in a region concurrently**. It does not itself protect a multi-step shared-state invariant.

```text
Mutex:     only one task may modify this protected state
Semaphore: at most N tasks may use this limited capacity
```

If four permitted image-processing goroutines append to one shared slice, the append still needs a [[Mutex]].

## Counting and binary semaphores

- A **counting semaphore** has `N` permits.
- A **binary semaphore** has one permit.

A binary semaphore can emulate mutual exclusion, but [[Mutex]] is normally clearer and more specialized for shared-state protection. Semaphore release is about returning capacity; mutex unlock is about ending an exclusive critical section.

## Go buffered channel pattern

Go does not need a built-in public semaphore type for simple cases because a buffered channel can represent occupied slots:

```go
sem := make(chan struct{}, 4)

sem <- struct{}{}        // acquire: occupy a buffer slot
defer func() { <-sem }() // release: free a buffer slot
```

In this encoding:

```text
len(sem) = permits currently in use
cap(sem) = maximum concurrent permits
```

`struct{}{}` carries no information; only the occupied channel slot matters. When the buffer is full, another send blocks until a receive frees a slot.

An alternative encoding preloads a channel with available tokens and uses receive to acquire and send to release. Either convention is valid if it is used consistently.

## Acquire before or inside the goroutine

Acquiring before spawning provides producer backpressure:

```go
sem := make(chan struct{}, 4)
var wg sync.WaitGroup

for _, job := range jobs {
	sem <- struct{}{} // producer blocks before creating excess workers
	wg.Add(1)

	go func(j Job) {
		defer wg.Done()
		defer func() { <-sem }()
		process(j)
	}(job)
}

wg.Wait()
```

With four occupied slots, the producer blocks on the fifth send. The fifth worker does not exist until a running worker releases a slot.

If acquisition occurs inside the new goroutine:

```go
for _, job := range jobs {
	go func(j Job) {
		sem <- struct{}{}
		defer func() { <-sem }()
		process(j)
	}(job)
}
```

all goroutines may be created immediately. Only four process at once, but every other goroutine may remain parked at the channel send. With one million jobs, this can create one million goroutines even though only four are doing useful work.

## Semaphore-limited goroutines versus worker pool

Both patterns can bound concurrency, but their worker lifecycles differ.

| Semaphore-limited goroutines | [[Worker Pool]] |
| --- | --- |
| Create a new goroutine for each job over time | Create `N` long-lived worker goroutines |
| Each goroutine normally handles one job and exits | Each worker repeatedly receives and processes jobs |
| Semaphore controls admission to a limited region | Workers own job execution |
| Convenient when only one portion of a larger task is limited | Convenient for a large or continuous homogeneous job stream |

For one million jobs with concurrency four:

```text
Semaphore pattern: 1,000,000 worker goroutines created over time,
                   at most 4 active in the limited region
Worker pool:       4 long-lived worker goroutines total
```

A worker pool's worker count controls execution concurrency. Its job-channel capacity controls how many additional jobs can wait in the queue:

```go
jobs := make(chan Job, 100)
// four workers + 100 queued jobs = up to 104 admitted jobs
```

With an unbuffered job channel, no job waits inside the channel; a producer send completes only when a worker is ready to receive.

## Semaphore versus rate limiter

A semaphore limits simultaneous in-flight work, not work per unit time.

If ten permits remain fully utilized and each request takes 1 millisecond:

```text
throughput = concurrency / latency
           = 10 / 0.001 seconds
           = 10,000 requests per second
```

Enforcing ten requests per second requires a time-based rate limiter such as a token bucket. A service may need both a semaphore and a rate limiter.

## Always release permits

Release immediately with `defer` after successful acquisition:

```go
func callService() error {
	sem <- struct{}{}
	defer func() { <-sem }()

	return makeRequest()
}
```

An early return without release leaks a permit. After enough leaks, every future caller waits forever.

Waiting can also support cancellation:

```go
func callService(ctx context.Context) error {
	select {
	case sem <- struct{}{}:
		// Acquired.
	case <-ctx.Done():
		return ctx.Err()
	}
	defer func() { <-sem }()

	return makeRequest()
}
```

## Deadlocks with multiple resources

Semaphores can participate in deadlocks just like mutexes:

```text
Task A holds database permit and waits for GPU permit
Task B holds GPU permit and waits for database permit
```

Prevent circular wait with a consistent acquisition order, a coordinator that acquires the required resources together, or nonblocking acquisition with safe rollback. A timeout is an operational escape, not a complete structural solution.

## One possible implementation

A high-level counting semaphore can be implemented using a mutex, permit counter, and condition variable:

```go
func (s *Semaphore) Acquire() {
	s.mu.Lock()
	defer s.mu.Unlock()

	for s.permits == 0 {
		s.cond.Wait()
	}
	s.permits--
}

func (s *Semaphore) Release() {
	s.mu.Lock()
	s.permits++
	s.cond.Signal()
	s.mu.Unlock()
}
```

`Wait` releases the mutex while sleeping and reacquires it before returning. The condition must be checked in a loop because waking means “the state may have changed,” not “this task is guaranteed a permit.” Another task may consume the permit first, or a broadcast may wake several waiters.

This does not create infinite implementation recursion. A high-level semaphore may use a mutex and condition variable, while a runtime mutex may use a lower-level semaphore-like parking primitive. At the bottom are hardware atomics, scheduler queues, and OS-specific waiting mechanisms.

## Interview summary

> A semaphore manages `N` permits and bounds concurrent access to a limited resource. Acquire consumes a permit or waits; release returns it. In Go, a buffered channel can implement a simple semaphore, and acquiring before spawning a goroutine provides backpressure. A semaphore is not a worker pool, mutex, or rate limiter, although these mechanisms can be combined.

## Related notes

- [[Mutex]]
- [[Concurrency MOC]]
- [[Worker Pool]]
- [[Goroutines and Channels]]
- [[sync.WaitGroup]]
- [[Go Scheduler]]
- [[POSIX]]