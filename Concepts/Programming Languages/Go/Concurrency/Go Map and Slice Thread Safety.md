---
date: 2026-09-28
tags:
  - go
  - map
  - slice
  - concurrency
  - data-race
  - mutex
  - interview
aliases:
  - map 线程安全
  - slice 线程安全
  - map 是线程安全的吗
  - concurrent map writes
  - sync.Map
  - RWMutex vs Mutex
  - slice header
  - Go data race
---
**Go's built-in `map` and slices are not safe for concurrent use whenever at least one goroutine writes.** A concurrent map write is detected on a best-effort basis and kills the process with a `fatal error` that cannot be recovered. A racing slice `append` fails silently. Both are shared structures updated by multi-step read-modify-write sequences. This note covers why, the fixes, and when to choose `Mutex`, `RWMutex`, `sync.Map`, sharding, or not sharing at all.

## Map: why it isn't thread-safe

`m[k] = v` looks like one memory write. It is several steps (see [[Hash Map]]):

```text
1. hash k
2. find the slot                      ← reads the shared table pointer
3. write key + value into the slot
4. count++                            ← one map-wide field
5. too full? → GROW: allocate a bigger table, move entries over
```

Every write touches the shared parts (the table pointer, `count`, and possibly growth), no matter which key it is for. So two goroutines writing **different keys** can still break each other:

- Both pick the same empty slot, and one entry silently overwrites the other.
- Both do `count++`, and one increment is lost (the read-modify-write problem from [[Compare-and-Swap]]).
- One goroutine triggers growth and moves entries while the other writes into the old table. The second write ends up somewhere nobody will ever look.

> A map is **one shared data structure**, not a set of independent memory locations. Any write can reorganize the whole thing. That is the difference from writing separate slice indexes (see below).

Since Go 1.24, maps are implemented as Swiss tables instead of 8-slot buckets. The concurrency behavior is the same.

## What Go does: the concurrent-write detector

Each map has a "currently writing" flag. A write sets it at the start and clears it at the end. If another operation sees the flag set, the runtime kills the program:

```text
fatal error: concurrent map writes
fatal error: concurrent map read and map write
fatal error: concurrent map iteration and map write
```

1. **It is a `fatal error`, not a panic, so `recover()` cannot catch it.** The whole process dies, because the map may already be corrupted and continuing would be unsafe.
2. **Detection is best-effort.** The check fires only if the two operations happen to overlap at the moment it looks. Many races get through and corrupt data silently.
3. **To find races reliably, use the race detector:** `go test -race` / `go run -race`.

## Readers and writers

| Access pattern | Safe? |
| --- | --- |
| Many goroutines only read, nobody writes | **Safe**: reads don't modify the map |
| One writer plus readers | **Unsafe** |
| Many writers | **Unsafe** |

With one writer, the problem is not "which version does the reader see." A reader that runs during a write can see the map **halfway through a change**, for example in the middle of growth with only some entries moved. It can return a wrong answer or crash. This is a memory-safety problem, not a stale-data problem.

A lock is what makes "which version" have a clean answer: the reader sees the map either **entirely before** or **entirely after** the write, never in between.

## Making a map safe

| Option | How it works | Choose it when |
| --- | --- | --- |
| `sync.Mutex` + map | Lock around every access | The default. Simple, and fast enough for most cases. |
| `sync.RWMutex` + map | `RLock` for reads (many can hold it at once), `Lock` for writes | Reads **far** outnumber writes. |
| `sync.Map` | Built-in concurrent map: `Load`, `Store`, `LoadOrStore`, `CompareAndSwap` | Two specific cases (from the Go docs): keys written once and read many times, like a cache, or goroutines working on separate sets of keys. Not a general replacement: values are untyped (`any`) and there is no `len`. |
| Sharded map | N maps, each with its own mutex; pick the shard with `hash(key) % N` | Many writers are all waiting on one lock. Sharding spreads them out. |
| One owner goroutine | Only one goroutine touches the map; others send it requests over a channel | The map is part of a larger piece of state that one goroutine manages. See [[Go Channel Pitfalls and Internals]]. |

## Why maps aren't thread-safe by default

1. **Cost.** Most maps are used by only one goroutine (local variables, per-request data). Locking every operation would make every program pay for something only a few need.
2. **Locking each operation separately still wouldn't make your code safe.**

```go
// Suppose Get and Set each lock internally:
if m.Get(k) == nil {          // A and B both see nil...
    m.Set(k, expensive(k))    // ...both compute, both set
}
m.Set(k, m.Get(k)+1)          // A and B both read 5, both write 6 → one update lost
```

Each individual operation is atomic, but the **sequence** is not. You would still need your own mutex around the whole check-then-set. So Go leaves locking to you, where you can put the lock around exactly the right amount of code.

## RWMutex vs Mutex: why RWMutex can be slower

An `RWMutex` is a `Mutex` with extra bookkeeping for readers:

```go
type RWMutex struct {
    w           Mutex        // writers take this: a full Mutex inside
    writerSem   uint32       // where a writer waits for active readers to leave
    readerSem   uint32       // where readers wait for a writer to finish
    readerCount atomic.Int32 // active readers (made negative while a writer is pending)
    readerWait  atomic.Int32 // readers the pending writer is still waiting for
}
```

```text
Lock()     1. w.Lock()                                  ← everything a Mutex does
           2. atomically subtract a huge number from readerCount
              → readerCount goes negative = "writer pending": new RLocks now block
           3. if readers are still active, wait until they have all left
Unlock()   1. atomically add the huge number back
           2. wake every reader that blocked during the write
           3. w.Unlock()
RLock()    atomically add 1 to readerCount; if it's negative, a writer is pending → wait
RUnlock()  atomically subtract 1; if a writer is waiting, maybe wake it
```

- **A write lock costs a full `Mutex` lock plus extra atomic operations.** If every operation is a write (for example `counts[user]++`), `RWMutex` pays that extra cost and gets nothing back, so a plain `Mutex` is faster.
- **Even `RLock` writes to shared memory.** Every reader does an atomic add on the same `readerCount`, so that cache line moves between cores ([[Cache Coherence and MESI]]). With very short critical sections, many readers on many cores still contend.
- **Writers get priority.** Once a writer is waiting, new readers block, so a steady stream of readers cannot starve the writer.

> Use `RWMutex` only when reads **far** outnumber writes **and** the read critical section is long enough to make parallel reading worthwhile. Otherwise use `Mutex`.

## Worked example: per-user request counters

50 goroutines constantly run `counts[user]++` on a `map[string]int`.

```go
// Option 1: Mutex (simple default). All operations are writes, so not RWMutex.
type Counter struct {
    mu     sync.Mutex
    counts map[string]int
}

func (c *Counter) Inc(user string) {
    c.mu.Lock()
    c.counts[user]++
    c.mu.Unlock()
}
```

A naive `sync.Map` version is **broken**:

```go
// BROKEN: each sync.Map call is atomic, but the Load+Store sequence is not
v, _ := m.Load(user)
n, _ := v.(int)
m.Store(user, n+1)            // two goroutines load 5, both store 6
```

Separate key sets per goroutine would avoid the race, but in a service, requests for the same user can arrive on any goroutine, so the keys can't be guaranteed to be separate.

The correct `sync.Map` version stores a pointer to an **atomic counter** for each user. The map is then written only once per user, which is `sync.Map`'s intended use, and each increment is an atomic operation on the value:

```go
var counts sync.Map // string → *atomic.Int64

func inc(user string) {
    v, ok := counts.Load(user)
    if !ok {
        // if another goroutine stored first, LoadOrStore returns its counter
        v, _ = counts.LoadOrStore(user, new(atomic.Int64))
    }
    v.(*atomic.Int64).Add(1)
}
```

Calling `Load` first avoids allocating a new counter on every call. For heavy write contention, a sharded map of mutex-protected maps also works.

## Slice: the header

A slice variable is not the array itself. It is a **3-field header** that points to the array:

```text
s ──▶ ┌───────┬─────┬─────┐
      │  ptr  │ len │ cap │     ← the variable s is just this (24 bytes on 64-bit)
      └───┬───┴─────┴─────┘
          ▼
      [ 10 | 20 | 30 | 40 | 50 |  _ |  _ |  _ ]    backing array
```

`s = append(s, x)` is a read-modify-write on the header, the same shape as `counter++`:

```text
1. READ s's header                           (ptr, len, cap)
2. if len < cap:  write x at ptr[len]
   else:          allocate a bigger array (~2×), copy everything over, write x there
3. WRITE the new header back into s          (len+1, and maybe a new ptr/cap)
```

## How concurrent appends get lost

**In place** (`len=5, cap=8`):

```text
A: read header (len=5)
B: read header (len=5)
A: write xA at ptr[5]
B: write xB at ptr[5]       ← overwrites xA
A: write header len=6
B: write header len=6
result: len=6, one append lost
```

**During growth** (`len=8, cap=8`): A and B each allocate their **own** new array, copy the data, and write their element into it. Each then writes a header pointing to its own array. The last header write wins, and the other array, with its element, becomes garbage.

**Torn header.** The header is three machine words, and they are not written atomically. A goroutine can read the *old* `ptr` (an 8-element array) together with the *new* `cap` (16), believe there is room, and write past the end of the array into other heap memory. Go's memory safety is guaranteed only for programs without data races.

**The final length can be almost anything.** With 2 × 500 appends, the result can be as low as **2**. This is the classic `counter++` puzzle:

```text
A: read len=0 ................ (paused)
B: 499 appends → len=499
A: write len=1                 ← wipes out B's 499
B: read len=1 ................ (paused)
A: its other 499 appends → len=500
B: write len=2                 ← wipes out A's 499
final len = 2
```

Typical runs land somewhere below 1000, varying run to run. A torn header can instead corrupt memory or crash the program.

> **Unlike maps, slices have no runtime detector.** There is no `fatal error`: the data is just silently wrong. Only `-race` finds it.

## Writing to separate indexes is safe

```go
results := make([]int, n)          // allocated in advance: header never changes
var wg sync.WaitGroup
for i := 0; i < n; i++ {
    wg.Add(1)
    go func(i int) {
        defer wg.Done()
        results[i] = work(i)       // each goroutine writes only its own element
    }(i)
}
wg.Wait()                           // required before reading results
```

Different indexes are different memory locations, and nobody changes the header (no `append`, no reassigning `results`). No goroutine writes to anything another goroutine touches, so there is no race. This is the standard pattern for collecting results from parallel work.

- **`wg.Wait()` before reading** is required. It waits for the work to finish, and it is the synchronization point that guarantees the reader sees all the writes.
- **Correct but can be slow.** `results[0]` through `results[7]` (8 ints, 64 bytes) share one cache line, so goroutines on different cores writing neighboring elements pass the line back and forth: **false sharing** ([[Cache Coherence and MESI]]). Fine for writing each result once; bad inside a hot loop.

## Fixing concurrent appends

| Fix | How | Choose it when |
| --- | --- | --- |
| Mutex around `append` | `mu.Lock(); s = append(s, x); mu.Unlock()` | Simple; low append rate |
| Allocate in advance, write own index | The pattern above | The number of results is known in advance |
| Per-goroutine local slices | Each goroutine appends to its own slice; merge after `wg.Wait()` | Unknown result count, high append rate: no sharing at all until the end |
| Single collector | Goroutines send results over a channel; one goroutine appends | Results should be processed as they arrive |

## Common misconceptions

- **"Map races only matter when two goroutines write the same key."** No. Every write touches the shared table pointer, `count`, and growth state.
- **"One writer with readers is only a stale-data problem."** No. Readers can see a half-modified structure; it is a memory-safety problem.
- **"You can `recover()` from concurrent map writes."** No. It is a `fatal error`, and the process dies.
- **"If it didn't crash, there's no race."** No. Map detection is best-effort, and slices have no detection at all. Use `-race`.
- **"`sync.Map` is the thread-safe map, so use it everywhere."** No. It fits two specific cases, is untyped, and atomic individual calls don't make a `Load` + `Store` sequence atomic.
- **"`RWMutex` is always at least as fast as `Mutex`."** No. Its write lock is a `Mutex` plus extra bookkeeping. In a write-heavy workload it pays extra for nothing.
- **"Racing appends lose at most half the appends."** No. The final length can be as low as 2, and a torn header can corrupt memory.
- **"Writing to different indexes of a slice needs a lock."** No. They are separate memory locations; you only need `wg.Wait()` before reading.

## Interview answer to "map 是线程安全的吗" / "slice 是线程安全的吗"

**map (30 秒):** 不是。map 的写不是一次内存写：要找槽位、更新 count，还可能触发扩容搬迁数据，所以即使写不同的 key 也会冲突。Go 运行时用一个"正在写"的标志做尽力检测，发现并发读写会直接 `fatal error: concurrent map writes`。这不是 panic，无法 recover。解决办法：默认用 `sync.Mutex`；读远多于写用 `sync.RWMutex`；key 只写一次、读很多次，或者各 goroutine 操作不相交的 key，用 `sync.Map`；写竞争激烈用分片锁。map 默认不加锁，一是大多数 map 只被一个 goroutine 使用，二是单个操作加锁也保证不了"先查后改"这类复合操作的原子性。

**slice (30 秒):** 也不是。slice 变量本身是一个三字段的 header（指针、长度、容量），`append` 是"读 header、写元素、写回 header"的读-改-写操作。并发 `append` 会互相覆盖元素，或者丢失扩容后的新数组，而且运行时不会检测，只能用 `-race` 发现。解决办法：加锁；预分配后每个 goroutine 写自己的下标（这是安全的，因为是不同的内存地址）；每个 goroutine 用自己的局部 slice，最后合并；或者通过 channel 交给一个 goroutine 统一 `append`。

**English version:**
- **Map:** not thread-safe. A write is not one memory write: it finds a slot, updates `count`, and may trigger growth, so even writes to different keys conflict. The runtime detects this on a best-effort basis and crashes with `fatal error: concurrent map writes`, which cannot be recovered. Fixes: `Mutex` by default, `RWMutex` when reads far outnumber writes, `sync.Map` for write-once/read-many keys or separate key sets, sharding for heavy write contention. Maps aren't locked by default because most are used by one goroutine, and per-operation locking can't make check-then-act sequences atomic anyway.
- **Slice:** not thread-safe. A slice is a three-word header, and `append` is a read-modify-write on it, so concurrent appends overwrite each other or lose a newly grown array, silently, with no runtime detection. Fixes: a mutex, writing to your own index of a slice allocated in advance, per-goroutine slices merged at the end, or a single collector goroutine.

**Senior add-on:** `RWMutex`'s write lock is a full `Mutex` plus reader bookkeeping, so for write-heavy workloads it is slower than `Mutex`, and even `RLock` contends on a shared atomic counter. A racing slice header can be torn (old `ptr` with new `cap`), leading to out-of-bounds writes, because Go's memory safety only holds for race-free programs. Writing to adjacent indexes is correct but can suffer false sharing.

## Interview summary

> Go maps and slices are unsafe whenever at least one goroutine writes. A map write finds a slot, updates the shared `count`, and may trigger growth, so writes to different keys still conflict. The runtime detects concurrent map access on a best-effort basis through a writing flag and crashes with an unrecoverable `fatal error`. Concurrent reads with no writers are safe. Fix with `Mutex` (default), `RWMutex` (reads far outnumber writes; its write lock is a Mutex plus bookkeeping, so it is slower for write-heavy loads), `sync.Map` (write-once/read-many or separate key sets; still needs `LoadOrStore` or atomic values, since `Load` + `Store` is not atomic), sharding, or a single owner goroutine. Maps aren't locked by default because most are used by one goroutine and per-operation locks can't make compound operations atomic. A slice is a three-word header (`ptr`, `len`, `cap`), and `append` is a read-modify-write on it, so concurrent appends silently lose elements (the final length can be as low as 2) or tear the header, with no runtime detection; only `-race` finds it. Writing to separate indexes of a slice allocated in advance is safe (distinct memory, header unchanged) but can suffer false sharing.

## Related notes

- [[Mutex]]
- [[Hash Map]]
- [[Compare-and-Swap]]
- [[Cache Coherence and MESI]]
- [[Go Channel Pitfalls and Internals]]
- [[Goroutines and Channels]]
- [[sync.WaitGroup]]
- [[Semaphore]]
