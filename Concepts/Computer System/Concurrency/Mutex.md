---
date: 2026-08-15
aliases:
  - mutex, concurrency
  - data race
---
A **mutex** (mutual-exclusion lock) allows at most one execution context to hold the lock at a time. Its purpose is to protect a shared-state invariant or a compound operation that must appear indivisible.

## Critical sections and invariants

Lock the entire operation whose intermediate states must not be observed. Locking only the final write may be insufficient.

```go
type Account struct {
	mu      sync.Mutex
	balance int
}

func (a *Account) Withdraw(amount int) bool {
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.balance < amount {
		return false
	}

	a.balance -= amount
	return true
}
```

If the balance check occurred before `Lock`, two goroutines could both observe sufficient funds and both deduct. This is both an unsynchronized-access problem and a **check-then-act race**.

> A mutex protects an invariant or compound operation, not merely an assignment.

## Mutual exclusion and memory visibility

A mutex does more than prevent simultaneous execution. In Go, an `Unlock` on a mutex synchronizes before a later successful `Lock` on the same mutex.

```text
write protected state
        â†“
Unlock
        â†“ happens-before
later Lock
        â†“
read protected state
```

Writes before `Unlock` are visible after the later `Lock`. An unlocked reader does not participate in this relationship and can still race with a locked writer.

```go
func (s *Store) Get(key string) (int, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	v, ok := s.items[key]
	return v, ok
}
```

Every concurrent access to mutex-protected state should use the same mutex unless another synchronization mechanism proves that overlap is impossible.

## Fast and slow paths

Conceptually, an uncontended mutex first tries an atomic compare-and-swap:

```text
state is unlocked
        â†“
atomic unlocked â†’ locked
        â†“
enter critical section
```

Only one competing atomic operation can change the state from unlocked to locked. This atomic transition is the acquisition's linearization point.

If the atomic attempt fails, the mutex enters a contended slow path:

```text
atomic attempt fails
        â†“
possibly spin briefly
        â†“
join a waiter queue
        â†“
park
        â†“
wake after an unlock
```

Brief spinning may be cheaper than parking when the owner will release almost immediately. Prolonged spinning wastes CPU, so practical implementations bound or adapt it. Waking every waiter would cause a **thundering herd**: all waiters contend even though only one can acquire the mutex.

Go's `sync.Mutex` uses atomic state for its fast path and internal runtime semaphore-like operations to park and wake goroutines on the slow path. The internal waiting mechanism is only part of the mutex implementation.

## Keep critical sections small

Do slow independent work outside the lock:

```go
func (s *Store) FetchAndSet(key string) error {
	value, err := slowNetworkCall(key)
	if err != nil {
		return err
	}

	s.mu.Lock()
	s.items[key] = value
	s.mu.Unlock()
	return nil
}
```

Holding a global mutex during network or disk I/O serializes unrelated work. If duplicate requests for the same key must be suppressed, use a more specific design such as per-key coordination rather than automatically holding one global lock across I/O.

## Go mutexes are not reentrant

Calling `Lock` twice on the same `sync.Mutex` without an intervening `Unlock` self-deadlocks, even in the same goroutine:

```go
func outer() {
	mu.Lock()
	defer mu.Unlock()

	inner() // inner also tries mu.Lock()
}
```

The goroutine waits for a lock that it can release only after the blocked call returns. A common repair separates locking from an internal helper:

```go
func outer() {
	mu.Lock()
	defer mu.Unlock()
	innerLocked()
}

func inner() {
	mu.Lock()
	defer mu.Unlock()
	innerLocked()
}

// Caller must hold mu.
func innerLocked() {
	// Protected work
}
```

Creating another goroutine does not automatically solve the problem. If the parent waits for a child while holding the mutex and the child needs that mutex, they form a deadlock cycle.

## Do not copy a mutex after use

Use pointer receivers for structs containing a mutex:

```go
type Store struct {
	mu    sync.Mutex
	items map[string]int
}

func (s *Store) Set(key string, value int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items[key] = value
}
```

With a value receiver, each call copies the mutex. A copied map header can still point to the same underlying map, so different goroutines may lock different mutex copies while concurrently modifying the same map. Go mutexes must not be copied after first use; `go vet` can detect many copy-lock mistakes.

## Deadlocks and lock ordering

Two goroutines can deadlock if they acquire multiple locks in opposite orders:

```text
G1 holds A and waits for B
G2 holds B and waits for A
```

A common prevention rule is to define one global acquisition order, such as always locking A before B. Timeouts can limit indefinite waiting, but they require safe rollback and do not remove the underlying circular-wait design.

## Mutex versus one-permit semaphore

A binary semaphore can enforce mutual exclusion when used with discipline, but a mutex is the clearer and more specialized abstraction for protecting shared state.

| Mutex | Semaphore with one permit |
| --- | --- |
| Expresses exclusive ownership of a critical section | Expresses acquisition of a permit |
| Strictly binary state | General abstraction is count-based |
| Often detects or prevents invalid extra unlocks | Some semaphore APIs permit the count to be increased accidentally |
| Specialized fast/slow paths and lock behavior | General resource-admission behavior |

Ownership semantics vary by language. Go's `sync.Mutex` is not associated with a particular goroutine, but it is still non-reentrant. Java `synchronized` and `ReentrantLock` are reentrant and owner-aware. Python offers both `Lock` and owner-aware `RLock`.

## Interview summary

> A mutex provides exclusive access to a critical section and establishes memory ordering between unlock and a later lock. It should cover the whole invariant, and every concurrent access to protected state must participate in the same synchronization protocol. An uncontended mutex normally uses an atomic fast path; under contention it may briefly spin and then park waiters using runtime or OS mechanisms.

## Related notes

- [[Compare-and-Swap]]
- [[Semaphore]]
- [[Concurrency MOC]]
- [[Concurrency vs Parallelism]]
- [[Go Scheduler]]
- [[Goroutines and Channels]]
- [[POSIX]]
- [[Go Map and Slice Thread Safety]]
