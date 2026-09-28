---
date: 2026-09-28
tags:
  - go
  - channel
  - goroutine
  - concurrency
  - runtime
  - interview
aliases:
  - channel pitfalls
  - channel 注意事项
  - channel 的作用
  - hchan
  - goroutine leak
  - nil channel
  - done channel
  - closing channels
---
A **Go channel** is a heap-allocated, lock-protected queue (`runtime.hchan`) that goroutines use both to **pass values** and to **synchronize**, parking and waking each other through the scheduler. This note covers pitfalls and internals: the nil/open/closed behavior table, who closes a channel, goroutine leaks, nil-channel tricks, and how `hchan` works. For basic usage, see [[Goroutines and Channels]].

## What channels are for (作用)

A channel does two jobs at once:

1. **Communication**: it moves a value (and, by convention, ownership of it) from one goroutine to another. "Don't communicate by sharing memory; share memory by communicating."
2. **Synchronization**: a send and its matching receive are a meeting point. The receiver parks until data arrives, and everything the sender wrote before the send is visible to the receiver after the receive (a *happens-before* edge in the Go memory model).

Common uses built from those two jobs:

| Use | Shape |
| --- | --- |
| Pass data / results | `results <- v` |
| One-shot "done" signal | `close(done)` |
| Broadcast "stop" to many goroutines | `close(done)` wakes **every** receiver |
| Limit concurrency (semaphore) | `sem := make(chan struct{}, N)` |
| Timeout / cancellation | `select` with `time.After` or `ctx.Done()` |

> A **send wakes one** waiting receiver. A **close wakes all** of them. That asymmetry is why "stop" signals are sent by closing a channel, not by sending on it.

## The 9-cell behavior table

| | send `ch <- v` | receive `<-ch` | `close(ch)` |
| --- | --- | --- | --- |
| **nil** (`var ch chan T`) | blocks **forever** | blocks **forever** | **panic** |
| **open** | works (blocks if full / no receiver) | works (blocks if empty) | works |
| **closed** | **panic** | **never blocks**: drains buffer, then zero value + `ok == false` | **panic** |

You don't need to memorize the table. It follows from one idea:

> **`close` is a message to receivers: "no more data is coming."** Receivers must be able to observe that message safely, so receiving from a closed channel never panics. This is what makes `range ch` and `v, ok := <-ch` work. A sender or closer acting after the close means the program's logic is broken, so Go panics loudly.
>
> A **nil channel** has no wait queue at all, so nothing can ever wake a goroutine waiting on it: it blocks forever. There is nothing to close, so `close(nil)` panics.

**Exactly three panics:** send on closed, close of closed, close of nil.

A sender that is **already parked** on a channel when it gets closed is woken up and **panics**. A close wakes parked senders too, not just receivers.

"Blocks" and "blocks forever" are different. An open channel can always be unblocked by another goroutine arriving. A nil channel never can.

## Receiving from a closed channel

Closing doesn't throw away buffered values. Receivers drain them first:

```go
ch := make(chan int, 2)
ch <- 1
ch <- 2
close(ch)

for v := range ch {   // prints 1, then 2, then the loop exits
    fmt.Println(v)
}
v, ok := <-ch         // 0, false: immediately, every time
```

> A closed channel is **always ready** to receive. Inside a `select`, that is either a bug (a spinning loop, see below) or a feature (a broadcast stop signal, see `done` channels).

## nil channels in select

A nil channel is never ready, so `select` simply ignores a case on a nil channel. Setting a channel variable to `nil` **switches that case off**.

The classic bug is merging two channels:

```go
// BUG: once a is closed, <-a is always ready.
// The loop spins, floods out with 0s, and burns a full CPU core.
for {
    select {
    case v := <-a:
        out <- v
    case v := <-b:
        out <- v
    }
}
```

`v, ok` alone isn't enough. If you `continue` on `!ok`, `select` keeps picking the closed case. The fix is to detect the close and then set the channel to nil:

```go
func merge(a, b <-chan int, out chan<- int) {
    defer close(out)                 // merge is out's only sender, so it closes out
    for a != nil || b != nil {       // finished when both inputs are finished
        select {
        case v, ok := <-a:
            if !ok { a = nil; continue }
            out <- v
        case v, ok := <-b:
            if !ok { b = nil; continue }
            out <- v
        }
    }
}
```

Without `close(out)`, a downstream `for v := range out` never ends.

## Who closes the channel

The rule: **the channel is closed by whoever *knows* that no more sends can happen.**

| Situation | Who closes | How |
| --- | --- | --- |
| One sender | The sender | `defer close(ch)` in the producer |
| N senders | A **coordinator** goroutine | `go func() { wg.Wait(); close(ch) }()` |
| Receiver wants to stop early | **Nobody closes the data channel** | Receiver closes a separate `done` channel (or cancels a `context`); senders `select` on it |

- **Why not "one of the senders closes"?** It can't know whether the others are finished. If another sender sends afterward, the program panics.
- **Why not the receiver?** It knows *even less* than a sender about whether sends are still coming, so it is the worst choice. See the `results` closer goroutine in [[Goroutines and Channels]] and [[Worker Pool]].

> **Closing is a signal, not cleanup.** A channel is plain heap memory, and the GC frees it once nothing references it, whether it was closed or not. A file is different: it holds a kernel file descriptor (see [[File Descriptors and Kernel IO Objects]]), which is why files must be closed. You never *have* to close a channel. Close it only when a receiver needs to learn "no more data", for example to end a `range`.

## Goroutine leaks

A **goroutine leak** is a goroutine that never exits, usually because it is parked forever on a channel operation. The GC **never** frees a goroutine: a parked goroutine's stack is still live, and so is everything it references. A leak is a memory leak made of goroutines.

Leaked goroutines use **zero CPU** because they are parked, so a leak is silent: memory just climbs until the process runs out.

> **The universal leak shape:** one side of a channel leaves early, and the other side is left parked on an operation nobody will ever complete.

A leak is not the same thing as a **data race**, which is two goroutines accessing the same memory without synchronization, with at least one of them writing.

### Shape 1: receiver times out, sender is stranded

```go
func fetchWithTimeout(url string) (string, error) {
    ch := make(chan string)              // BUG: unbuffered
    go func() {
        ch <- slowFetch(url)             // ← leaked goroutine parks here forever
    }()
    select {
    case body := <-ch:
        return body, nil
    case <-time.After(time.Second):
        return "", errors.New("timeout") // receiver LEAVES
    }
}
```

```text
t=0s   caller: select waiting          worker: running slowFetch (takes 3s)
t=1s   caller: timeout → RETURNS       worker: still in slowFetch
t=3s   (nobody will ever receive)      worker: ch <- body   ← parked forever
```

The *caller* doesn't get stuck, because `select` with a timeout returns. The goroutine left stranded is the **sender**. At 10k timed-out calls per second, that is 10k leaked goroutines per second, each holding its stack and the fetched body.

**Fix:** `ch := make(chan string, 1)`. Exactly one send will ever happen, and a buffer of 1 lets it complete with no receiver. The goroutine exits, and the channel and value become garbage.

### Shape 2: consumer stops early, producer is stranded

```go
func contains(items []string, target string) bool {
    ch := make(chan string)
    go func() {
        for _, it := range items {
            ch <- it                     // ← parks forever after an early return
        }
        close(ch)
    }()
    for it := range ch {
        if it == target {
            return true                  // consumer LEAVES early
        }
    }
    return false
}
```

A buffer of 1 does **not** fix this. There is only **one** producer goroutine, but its loop sends **many** values, and a buffer only absorbs as many unreceived sends as its capacity. With `items = [a, b, c, d, e]` and `target = b`:

```text
producer                          buffer   consumer
─────────────────────────────────────────────────────────────
ch <- a   (consumer takes it)     [ ]      gets a, not target
ch <- b   (consumer takes it)     [ ]      gets b → MATCH → return true
                                           ── consumer is gone ──
ch <- c   buffer has room         [c]
ch <- d   buffer FULL, no receiver
          → parked forever  ← LEAK
```

The buffer only delays the leak by one send. The buffer trick works only when you can put a limit on the number of sends nobody will receive; in Shape 1 that number is exactly one.

Fixes that work but aren't great: a buffer of `len(items)` (O(n) memory, and the producer still does all the work), or draining the channel before returning (which defeats the early exit).

**The real problem: information only flows one way.** The producer has no way to learn that the consumer left. The fix is a second channel going the other direction, meaning only "stop":

```text
            ch   (data)
producer ──────────────▶ consumer
producer ◀────────────── consumer
            done (stop signal)
```

**Idiomatic fix: a `done` channel that the consumer closes.**

```go
func contains(items []string, target string) bool {
    ch := make(chan string)
    done := make(chan struct{})
    defer close(done)                    // on ANY return: broadcast "stop"

    go func() {
        defer close(ch)
        for _, it := range items {
            select {
            case ch <- it:
            case <-done:                 // closed → always ready → producer exits
                return
            }
        }
    }()

    for it := range ch {
        if it == target {
            return true
        }
    }
    return false
}
```

The producer's plain send becomes a choice. `select` blocks until at least one case can go ahead, then does that case:

| | `case ch <- it` | `case <-done` | select picks |
| --- | --- | --- | --- |
| **Consumer still looping** | ready (a receiver is waiting) | not ready (`done` is open, and nobody ever sends on it) | send the item |
| **Consumer returned** | never ready (no receiver) | **ready**: `done` is closed, and a closed channel is always ready | `return` |

```text
producer                                  consumer
──────────────────────────────────────────────────────────────
select: ch <- a ready → send a            gets a
select: ch <- b ready → send b            gets b → MATCH → return true
                                          defer close(done) runs
select: ch <- c NOT ready
        <-done READY (closed)
        → return
defer close(ch), goroutine exits ✓
```

If the producer is already parked inside the `select` when `done` is closed, it is registered on **both** channels (one `sudog` on each), so `close(done)` finds it in `done`'s wait queue and wakes it.

- **Why `defer`?** A deferred call runs when the function returns, on every way out: `return true`, `return false`, or a panic.
- **Why `chan struct{}`?** Nothing is ever sent on `done`; it only ever gets closed. `struct{}` takes zero bytes, which makes it clear the channel is a signal and carries no data.
- **Doesn't the consumer closing `done` break "the receiver never closes"?** No. That rule is about the data channel `ch`. On `done` the roles are reversed: the consumer is `done`'s only sender, so it is the one that knows no more signals are coming.

### Why signal by closing, not by sending

Replace `defer close(done)` with `defer func() { done <- struct{}{} }()`:

- **Target found early:** it works. The producer's `<-done` case receives the value.
- **Target never found:** `range ch` ends only after the producer closes `ch`, which it does only after its loop is finished. So by the time `return false` runs, the producer has **already exited**. The deferred send has no receiver and blocks forever. The consumer is `contains` itself, running on the caller's goroutine, so **the caller hangs** because `contains` never returns. If the caller is `main` with nothing else running, the runtime reports a deadlock; inside an HTTP handler, the request hangs silently.
- **With 3 producers:** a sent value reaches only one of them, and the other two leak.

> **Closing has three properties that sending doesn't:**
> 1. **It never blocks**, even if nobody is listening (the not-found case).
> 2. **It wakes every waiter**, not just one (multiple producers).
> 3. **It stays on**: a goroutine that reaches its `select` later still sees it. A sent value is received once and then it's gone.
>
> The same fact, **a closed channel is always ready**, causes the bug in the `merge` spin loop and is the whole mechanism here. `ctx.Done()` is exactly this pattern: `cancel()` closes the channel that `ctx.Done()` returns.

### Cancellation is cooperative

Go has **no API to kill a goroutine from outside**. To actually stop the work, not just stop waiting for its result, pass a `context` and have the work check it:

```go
func fetchWithTimeout(ctx context.Context, url string) (string, error) {
    ctx, cancel := context.WithTimeout(ctx, time.Second)
    defer cancel()
    return slowFetch(ctx, url) // e.g. http.NewRequestWithContext(ctx, ...)
}
```

With `context`, the hand-rolled goroutine, channel, and `time.After` all go away.

### Detecting leaks

- `runtime.NumGoroutine()` climbing over time
- pprof goroutine profile (`/debug/pprof/goroutine`), which shows where each goroutine is parked
- `go.uber.org/goleak` in tests

> The runtime's `fatal error: all goroutines are asleep - deadlock!` fires only when **every** goroutine is blocked. A **partial** deadlock, where some goroutines are stuck forever while others keep running (an HTTP server, for example), is never reported. It only shows up as a leak.

## Internals: `runtime.hchan`

A channel isn't owned by any goroutine and isn't managed by `main`. `make(chan T, n)` allocates an `hchan` on the **heap** and returns a pointer to it. Any goroutine holding that pointer can send or receive, and the send/receive code runs **on the calling goroutine itself**, inside the runtime.

```go
type hchan struct {
    // "store values in order" → fixed-capacity FIFO = ring buffer
    buf      unsafe.Pointer // array of dataqsiz elements (unused if unbuffered)
    dataqsiz uint           // capacity: the n in make(chan T, n)
    qcount   uint           // values currently in buf
    sendx    uint           // next slot to write
    recvx    uint           // next slot to read

    closed   uint32         // "know whether it's closed"

    // "remember who's waiting" → two queues of parked goroutines
    recvq    waitq          // parked receivers (linked list of sudog)
    sendq    waitq          // parked senders

    lock     mutex          // runtime-internal lock, not sync.Mutex
    elemtype *_type
    elemsize uint16
}
```

- **Ring buffer**: fixed capacity, O(1) push at one end and O(1) pop at the other, with no shifting.
- **`sudog`**: an entry meaning "goroutine G is waiting on *this* channel, and here is the address the value comes from or goes to." Why not put G into the queue directly? A `select` can make one G wait on **several** channels at once, so it needs one entry per channel.
- **Not lock-free.** Goroutines on different Ms (OS threads) can use the same channel at the same moment, so all real work happens under `lock`. A few fast-path checks skip the lock, for example a non-blocking `select` on an empty channel.

### Send algorithm (`ch <- v`)

```text
lock(ch)
if closed               → unlock, panic("send on closed channel")
if recvq has a waiter   → DIRECT HANDOFF: copy v straight into the receiver's stack,
                          goready(receiver), unlock            ← never touches buf
elif qcount < dataqsiz  → copy v into buf[sendx], sendx++, qcount++, unlock
else                    → wrap self in a sudog, enqueue on sendq,
                          gopark (the lock is released as part of parking)
```

Receive mirrors send:
- closed and empty: return the zero value.
- a sender is parked: take its value. For a full buffered channel, take from the head of `buf`, move the sender's value into the freed tail slot to keep FIFO order, then wake the sender.
- data in `buf`: take it.
- otherwise: park on `recvq`.

`close` takes the lock, sets `closed`, and then wakes **every** parked receiver (they get zero and `false`) and **every** parked sender (they panic).

### The unbuffered handoff, step by step

B is parked in `x := <-ch`, and A runs `ch <- 5`:

```text
A: lock(ch)
A: recvq has B's sudog → dequeue it
A: copy 5 directly into B's stack slot for x   ← one goroutine writing another's stack
A: unlock(ch)
A: goready(B): B goes _Gwaiting → _Grunnable and is placed in A's P.runnext
A: keeps running and never blocks
...later: B is scheduled, and 5 is already in x
```

"5 goes into the channel" is wrong for an unbuffered channel. There is no storage in it, so the value goes directly from one stack to the other.

### Connection to GMP

While B is parked it is on **no run queue**. The only reference to it is the channel's `recvq`, and its M just picks another G from the P and keeps running. So blocking on a channel **never blocks the OS thread**. A blocking syscall is different: it blocks the M and forces a P handoff. When B wakes, it goes into a **P's run queue** (`runnext`, so it runs soon, often on the same core with a warm cache), not directly onto a thread. See [[GMP Scheduler Internals]].

## Common misconceptions

- **"Receiving from a closed channel panics or blocks."** No. It drains the buffer, then returns zero and `ok == false` immediately, every time.
- **"`close(nil)` is a no-op."** No. It panics.
- **"The receiver can close the channel when it's done."** No. The receiver knows the least about pending sends. Use a coordinator, or a separate `done` channel.
- **"One of several senders can close it."** No. It can't know whether the others are done.
- **"A buffer of 1 fixes any send leak."** No. It absorbs one unreceived send. A loop that sends many values still leaks on the next send.
- **"Signal stop by sending a value on `done`."** No. A send blocks if nobody is receiving and wakes only one goroutine. A close never blocks, wakes all of them, and stays on.
- **"A goroutine leak is a data race."** No. A leak is a goroutine that never exits. A race is unsynchronized access to shared memory.
- **"In a timeout leak, the caller is stuck."** No. The caller returns; the **sender** is left stranded.
- **"A blocked receive keeps checking the channel."** No. It's parked: off every run queue and using zero CPU until another goroutine wakes it.
- **"You must close channels to free them."** No. The GC frees unreachable channels; closing is only a signal.
- **"A channel belongs to a goroutine, or to main."** No. It's a shared heap object, and each operation runs on the goroutine that calls it.

## Interview answer to "channel 的作用和使用注意事项"

**作用 (30 秒):** channel 是 goroutine 之间通信和同步的机制。一是传递数据，把数据的所有权从一个 goroutine 交给另一个（"不要通过共享内存来通信，而要通过通信来共享内存"）；二是同步：接收方没有数据时会挂起，发送前的写操作对接收后可见。常见用法：传递结果、用 `close` 广播结束信号、带缓冲的 channel 做信号量限流、配合 `select` 做超时和取消。

**注意事项 (30 秒):**
1. 三种 panic：向已关闭的 channel 发送、重复关闭、关闭 nil channel。
2. 谁来关闭：一般由发送方关闭；多个发送方时，由一个协调者在 `WaitGroup` 等所有发送方结束后关闭；接收方不要关闭数据 channel，想提前停止就用 done channel 或 `context` 通知发送方。
3. 从已关闭的 channel 接收不会阻塞：先读完缓冲区，然后返回零值和 `ok=false`，所以要用 `v, ok` 或 `for range` 判断；在 `select` 里可以把已关闭的 channel 置为 nil 来禁用这个 case。
4. nil channel 的收发会永久阻塞。
5. goroutine 泄漏：一方提前退出，另一方永远阻塞，而 goroutine 不会被 GC 回收。每个 goroutine 都要有退出路径（缓冲、done channel、`context`）。运行时只有在所有 goroutine 都阻塞时才报 deadlock，部分阻塞只会表现为泄漏。

**English version:**
- There are three panics: send on closed, close of closed, close of nil.
- The sender closes the channel. With many senders, a coordinator closes it after `wg.Wait()`. A receiver that wants to stop early closes a separate `done` channel or cancels a `context` instead.
- Receiving from a closed channel never blocks: it drains the buffer and then returns zero with `ok == false`. So use `v, ok` or `range`, and set a finished channel to `nil` inside `select`.
- Nil channels block forever.
- Every goroutine needs an exit path, or a stranded sender or receiver leaks. The runtime only reports a deadlock when *all* goroutines are asleep.

**Senior add-on:** a channel is a heap-allocated `hchan`: a ring buffer plus `sendq`/`recvq` wait queues of `sudog`s, guarded by a mutex, so it is not lock-free. When a receiver is already waiting, the sender copies the value directly into the receiver's stack and marks it runnable in the sender's P's `runnext`. A parked goroutine sits on no run queue, so channel blocking never blocks the OS thread.

## Interview summary

> A channel is a heap-allocated `hchan` (a ring buffer, sender and receiver wait queues, and a mutex) used for both communication and synchronization. On a nil channel, send and receive block forever and close panics. On a closed channel, send and close panic, and receive never blocks: it drains the buffer, then returns zero with `ok=false`. That makes a closed channel "always ready", which is the basis of `range`, the `done`-channel broadcast, and `ctx.Done()`, and also the cause of `select` spin bugs, fixed by setting the channel to nil. Closing is a signal, not cleanup (the GC frees channels). It must be done by whoever knows no more sends can happen: the only sender, or a `wg.Wait()` coordinator when there are N senders, and never the receiver, which closes a separate `done` channel instead. Goroutine leaks happen when one side leaves early and the other is parked forever. The GC never frees goroutines, so every goroutine needs an exit path: a buffer of 1 for a single abandoned send, or `done`/`context` for a stream. Parked goroutines sit on no run queue, so channel blocking never blocks an OS thread. An unbuffered send to a waiting receiver copies the value directly into the receiver's stack.

## Related notes

- [[Goroutines and Channels]]
- [[Worker Pool]]
- [[sync.WaitGroup]]
- [[GMP Scheduler Internals]]
- [[Go Scheduler]]
- [[Mutex]]
- [[Semaphore]]
- [[Process vs Thread vs Coroutine]]
- [[File Descriptors and Kernel IO Objects]]
