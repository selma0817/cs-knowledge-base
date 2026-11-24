---
date: 2026-11-23
aliases:
  - closure
  - Go closure
  - function literal
  - captured variable
  - escape analysis
  - loop variable capture
  - defer argument evaluation
  - named result
  - 闭包
  - 变量捕获
  - 逃逸分析
  - defer 执行顺序
  - 循环变量捕获
tags:
  - topic/language-runtimes
  - topic/concurrency
  - topic/go
  - closure
  - escape-analysis
  - defer
  - shadowing
  - loop-variable
---
## One-sentence meaning

A **closure** is a function value together with the variables it captures from the function around it; it shares those variables (it doesn't copy their values), and they live as long as the closure can still reach them.

## Why I care

- Every `go func(){…}()` in my concurrency notes is a closure, and the classic bug (goroutines in a loop all printing the last value) is a closure bug.
- My Raft election code captures `electionTerm` on purpose: a goroutine that needs the term from when its campaign started can't read the shared `rf.currentTerm` later ([[Raft Leader Election and Voting]] › Delayed vote replies).
- `defer` looks like "run this later", but its arguments run now. That gives wrong timings and wrong logs if I don't know the rule.

Studied in a drill on 2026-11-18 and 2026-11-23. All demos ran on go1.25.2 darwin/arm64.

## A closure shares the variable, not a copy of its value

The Go spec, "Function literals": the captured variables "are then shared between the surrounding function and the function literal, and they survive as long as they are accessible."

```go
package main

import "fmt"

func makeTally() (func(int), func() int) {
	total := 0
	add := func(n int) { total += n }
	get := func() int { return total }
	return add, get
}

func main() {
	add, get := makeTally()
	add(5)
	add(10)
	fmt.Println(get())

	add2, get2 := makeTally()
	add2(1)
	fmt.Println(get(), get2())
}
```

```text
15
15 1
```

- `add` and `get` share one `total`, so `get` sees what `add` wrote. If each closure copied `total`'s value when it was created, `get` would print 0.
- Each call to `makeTally` creates a new `total`, so `add2`/`get2` have their own.

To get a copy on purpose, capture a separate variable:

```go
total := 0
snap := total                      // a copy, taken now
add := func(n int) { total += n }
get := func() int { return snap }  // captures snap, not total
add(5)
add(10)
fmt.Println(get(), total)          // 0 15
```

## Captured variables move to the heap when they outlive their function

`total` is a local of `makeTally`, but `get` reads it after `makeTally` returns. The compiler's **escape analysis** sees this at compile time and allocates `total` on the heap instead of in the stack frame:

```text
$ go build -gcflags='-m -l' .        (-l turns off inlining, so the output is easier to read)
./main.go:6:2: moved to heap: total
./main.go:7:9: func literal escapes to heap
./main.go:8:9: func literal escapes to heap
```

The Go FAQ ("How do I know whether a variable is allocated on the heap or the stack?"): when the compiler "cannot prove that the variable is not referenced after the function returns", it must allocate it "on the garbage-collected heap to avoid dangling pointer errors". The garbage collector then frees it once nothing refers to it.

The rule is "referenced after return", not "modified after return". A pointer that is only read still forces the heap:

```go
func e() *int { x := 5; return &x }   // the caller only reads *p
```
```text
./main.go:5:17: moved to heap: x
```

| Code returns | What ends up on the heap |
|---|---|
| `&x` | x itself; the caller holds a pointer to it |
| a closure that changes x | x, plus a closure object holding a pointer to x |
| a closure that only reads x (never reassigned) | only a closure object holding a copy of x (x never moves) |

### The compiler may copy a variable that is never reassigned

A closure is a small runtime object: a pointer to the code plus its captured data (`type funcval struct { fn uintptr; // variable-size, fn-specific data here }` in `src/runtime/runtime2.go`). For a captured variable that is small and never reassigned, the compiler copies its value into that object instead of moving the variable to the heap. The Go compiler source says so (`src/cmd/compile/internal/escape/escape.go`, line 261): "Capture by value for variables <= 128 bytes that are never reassigned."

```go
func c() func() int { x := 3; return func() int { x++; return x } }
func d() func() int { x := 4; return func() int { return x } }
```
```text
$ go build -gcflags='-m=2 -l' .
./main.go:6:2: c capturing by ref: x (addr=false assign=true width=8)
./main.go:11:2: d capturing by value: x (addr=false assign=false width=8)
```

Nobody can tell the difference, because `x` never changes: the spec fixes the behavior (sharing), not the mechanism.

### Why a stack variable can't outlive its function

A **stack frame** is a function call's scratch memory: claimed when the function is called, released the moment it returns, and reused by the next call. The garbage collector never manages it. C lets you return the address of a local anyway, and the pointer then **dangles**:

```text
$ cc -O0 dangle.c        (make_total returns &total, where total = 15 is a local)
dangle.c:5:13: warning: address of stack memory associated with local variable 'total' returned [-Wreturn-stack-address]
$ ./dangle
right after: 15
after another call: 999       ← another function's local, written into the same stack memory
```

Writing through the same kind of pointer inside a later call crashed with `Segmentation fault: 11`. This is undefined behavior in C, so any run can differ. Go never allows it: escape analysis moves the variable to the heap first.

A dangling pointer is the opposite of a memory leak. A leak is memory kept allocated forever although nothing will use it again (freed too late, or never). A dangling pointer is memory released and reused while something still points at it (freed too early).

## `:=` declares a new variable, `=` assigns, and an inner `:=` shadows

`:=` is a short variable declaration: it creates a new variable and infers its type from the value. It is shorthand for `var x = …` and works only inside functions (Go spec, "Short variable declarations"). `=` assigns to a variable that already exists.

In the same block, `:=` must declare at least one new variable:

```go
x := 1
x = 2
x := 3   // compile error
```
```text
./main.go:8:4: no new variables on left side of :=
```

In an inner block, `:=` creates a separate variable with the same name that hides the outer one until the block ends:

```go
x := 1
if true {
	x := 2
	x = 3
	fmt.Println("inside:", x)
}
fmt.Println("outside:", x)
```
```text
inside: 3
outside: 1
```

### Shadowing silently drops errors and values

```go
func parsePort(s string) (int, error) {
	port := 8080
	var err error
	if s != "" {
		port, err := strconv.Atoi(s)   // new port and err, shadowing the outer ones
		if err != nil {
			fmt.Println("  log: bad port:", err)
		}
		fmt.Println("  log: parsed", port)
	}
	return port, err
}

func start(userInput string) error {
	port, err := parsePort(userInput)
	if err != nil {
		return fmt.Errorf("bad port: %w", err)
	}
	fmt.Println("listening on", port)
	return nil
}
```

```text
  log: parsed 9090
listening on 8080
start("9090") returned <nil>
  log: bad port: strconv.Atoi: parsing "abc": invalid syntax
  log: parsed 0
listening on 8080
start("abc") returned <nil>
```

The user's port is silently ignored, and the bad input silently accepted: the outer `err` keeps its zero value, `nil` (the zero value of an interface type such as `error`, Go spec "The zero value"). `go vet` reports nothing. The fix is `=`: `port, err = strconv.Atoi(s)`.

## Before Go 1.22, every loop iteration shared one variable

The Go 1.22 release notes: "Previously, the variables declared by a "for" loop were created once and updated by each iteration. In Go 1.22, each iteration of the loop creates new variables, to avoid accidental sharing bugs." The behavior follows the `go` line in `go.mod`, not the installed Go version: both runs below used go1.25.2.

```go
var fs []func()
for i := 0; i < 3; i++ {
	fs = append(fs, func() { fmt.Print(i, " ") })
}
for _, f := range fs {
	f()
}
```
```text
go.mod "go 1.21":   3 3 3
go.mod "go 1.22":   0 1 2
```

Under 1.21 there is one `i`: set to 0, 1, 2, then 3 by the last `i++`, which makes `i < 3` fail. The closures run after the loop, so they all read 3. Pointers show the same sharing, without any closure:

```go
nums := []int{10, 20, 30}
var ptrs []*int
for _, v := range nums {
	ptrs = append(ptrs, &v)
}
```
```text
go.mod "go 1.21":   30 30 30     (one v, so &v is the same address three times)
go.mod "go 1.22":   10 20 30
```

### With goroutines, the shared loop variable is also a data race

```go
// go.mod: go 1.21
var wg sync.WaitGroup
for i := 0; i < 3; i++ {
	wg.Add(1)
	go func() {
		defer wg.Done()
		fmt.Print(i, " ")
	}()
}
wg.Wait()
```

Five runs all printed `3 3 3`, but that isn't guaranteed: a goroutine may run while the loop is still changing `i`. The race detector reports the loop's write against the goroutines' read:

```text
$ go run -race .
WARNING: DATA RACE
Read at 0x00c000010198 by goroutine 8:      …main.go:14   (the Print)
Previous write at 0x00c000010198 by main goroutine:   …main.go:10   (the for line's i++)
```

Two fixes under go 1.21, both clean under `-race`:

```go
i := i                         // 1. a new variable per iteration, holding a copy
go func() { … fmt.Print(i, " ") … }()

go func(n int) {               // 2. pass i as an argument
	defer wg.Done()
	fmt.Print(n, " ")
}(i)
```

The second works because a `go` statement's arguments "are evaluated as usual in the calling goroutine" (Go spec, "Go statements"), so `n` is a copy made when the `go` line runs.

### Race-free is not the same as correct

Protecting `i` with a mutex removes the race but not the bug. A version that locks around the loop's `i++` and around each goroutine's read ran clean under `-race`, five times, and printed `3 3 3` every time. The lock makes the write and the reads take turns. It doesn't control their order, and every goroutine still reads the one shared `i`, usually after the loop. A data race is about accesses overlapping; correctness is about each goroutine getting the value we meant. Here that takes a copy per goroutine.

## Taking a snapshot on purpose

When a closure or goroutine needs a value from the moment it was created, and the variable will keep changing, copy it into a new variable (`i := i`, `saved := msg`) or pass it as an argument. Raft's vote-request goroutines copy `electionTerm` when the campaign starts for exactly this reason: `rf.currentTerm` is shared and moves on when a new election starts.

## A deferred call evaluates its arguments now and runs at return

The Go spec, "Defer statements": each time a `defer` statement executes, "the function value and parameters to the call are evaluated as usual and saved anew but the actual function is not invoked". Deferred functions run "immediately before the surrounding function returns, in the reverse order they were deferred".

```go
func tick(n int) int {
	fmt.Println("tick", n)
	return n
}

func main() {
	defer fmt.Println("A", tick(1))
	defer fmt.Println("B", tick(2))
	fmt.Println("body")
}
```
```text
tick 1
tick 2
body
B 2
A 1
```

A deferred **closure** with no arguments computes nothing early: its body reads the variables when it runs.

```go
x := "a"
defer fmt.Println("1:", x)                  // saves "a" now
x = "b"
defer func() { fmt.Println("2:", x) }()     // reads x at return
x = "c"
defer fmt.Println("3:", x)                  // saves "c" now
fmt.Println("returning")
```
```text
returning
3: c
2: c
1: a
```

To make line 2 print `b`, snapshot first (`xb := x`, then print `xb`) or pass it as an argument (`defer func(v string) { fmt.Println("2:", v) }(x)`). `x := x` doesn't work there, since `x` already exists in that block.

### Timing with `defer` needs a closure

```go
func work() {
	start := time.Now()
	defer fmt.Println("work took", time.Since(start))
	time.Sleep(100 * time.Millisecond)
}
```
```text
work took 8.208µs        (three runs: 8.208µs, 1.291µs, 1.25µs)
```

`time.Since(start)` is an argument, so it runs at the `defer` line, before the sleep. Passing it to a closure as an argument has the same problem (15.125µs). Calling it inside the closure's body moves it to the end:

```go
defer func() { fmt.Println("work took", time.Since(start)) }()
```
```text
work took 101.049583ms
```

The two directions of the same rule:

```text
value from now     →  pass it as an argument, or snapshot it
value from the end →  read it inside a deferred closure's body
```

## A deferred closure can change a named result

In `func f() (n int)`, the empty `()` is the parameter list and `(n int)` is a **named result**: a variable created when the function starts (with its zero value) and returned at the end. The Go spec: deferred functions run "after any result parameters are set by that return statement but before the function returns to its caller", and a deferred function literal "may access and modify the result parameters before they are returned".

```go
package main

import "fmt"

func f() (n int) {
	defer func() { n *= 2 }()
	return 3
}

func g() int {
	n := 3
	defer func() { n *= 2 }()
	return n
}

func main() {
	fmt.Println("f() =", f())
	fmt.Println("g() =", g())
}
```
```text
f() = 6
g() = 3
```

- `f`: `return 3` sets `n` to 3, the deferred closure doubles it, then `f` returns `n`.
- `g`: the result has no name. `return n` copies 3 out first; the closure then doubles a local that is no longer the result.

The same holds for strings: with `func h() (result string)`, a deferred `result = result + "!"` turns `return "done"` into `done!`, and without the name it stays `done`.

Named functions like `f` must be declared at the top level of the file. Declaring `func f()` inside `main` fails with `syntax error: unexpected name f, expected (`; inside a function, use a function literal: `f := func() (n int) { … }`.

## My definitions

- **Closure:** a closure is a function along with the variables it captures. The variables can come from outside its function body. The closure holds the variables themselves, not copies of their values.
- **Escape analysis:** it happens at compile time. It decides whether a variable can still be referenced after its function returns; if so, the variable goes on the heap. Otherwise it stays in the stack frame and is freed when the function returns. We do it to avoid dangling pointers: handing out the address of a variable whose memory is then reused by another function's call.
- **`defer`:** a deferred call's arguments are evaluated eagerly, when the `defer` line runs. The call itself runs when the surrounding function returns, last deferred first, like a stack. To postpone evaluating something, put it inside a deferred closure's body, not in the deferred call's arguments.
- **`:=` vs `=`, shadowing:** `:=` declares a new variable and infers its type from its value; `=` assigns a value to a variable that's already declared. Shadowing: using `:=` in an inner block (like an `if` or `for` body) on a name declared outside creates a new inner variable that hides the outer one; after the inner block ends, the name refers to the outer variable again, which the inner block never changed.
- **Loop variables in Go 1.22:** a `for` loop creates a new variable for each iteration; in Go 1.21, every iteration reuses the same `i`, so closures or goroutines in the loop that use `i` all access the same variable. The change (chosen by the `go` line in `go.mod`) prevents that accidental sharing, the race on `i` and every goroutine seeing the final value, so each one gets its own copy of `i`.
- **Named result:** a named result gives a name to a function's return value: a variable created when the function starts and returned at the end. `return v` assigns it first, then deferred functions run, so a deferred closure can change the return value through that name.

## How I'd answer in an interview

**"What's a closure in Go?"** A function value plus the variables it captures from the surrounding function. It shares those variables, it doesn't copy them, so two closures from the same call see each other's writes, and a closure sees later changes. If a captured variable can be reached after its function returns, escape analysis puts it on the heap, and the GC frees it when nothing refers to it.

**"What does this loop with goroutines print?"** Before Go 1.22 the loop had one variable for all iterations, so every goroutine reads the same `i`, usually the final value, and it's a data race because the loop writes `i` while the goroutines read it. Fixes: `i := i` in the body, pass `i` as an argument, or set `go 1.22` or later in `go.mod`, where each iteration gets its own variable. A mutex alone removes the race but not the wrong value.

**"Any `defer` pitfalls?"** Deferred calls run at return in reverse order, but their arguments are evaluated at the `defer` line. So `defer fmt.Println("took", time.Since(start))` measures almost nothing; wrap it in a closure. A deferred closure can also change named results, which is how you adjust a returned error after the fact.

## Still to learn

- The cost of closures in hot paths: every escaping closure is a heap allocation.
- `recover()` inside a deferred closure, and how it interacts with named results.
- Method values (`f := obj.Method`): what gets captured, the receiver or a copy of it.

## Common mistakes

From the drill on 2026-11-18 and 2026-11-23.

### Mistake 1: thinking a closure copies a variable's value when it's created (mine)

It shares the variable. I fell back on this belief three times: I couldn't say what `get` would print if closures copied, I predicted the 1.21 loop closures print `0 1 2` ("i is evaluated in the for loop"), and I predicted a deferred closure prints `2: b`. See "A closure shares the variable, not a copy of its value".

### Mistake 2: thinking the garbage collector cleans up a function's stack frame (mine)

Stack frames are released on return and reused by the next call, with no GC involved. The GC only manages the heap.

### Mistake 3: thinking a variable left on the stack would just become inaccessible, or leak (mine)

It would still be accessible, and that's the danger: a dangling pointer reads another call's data and corrupts it on write. A leak is the opposite failure: memory never freed.

### Mistake 4: thinking a variable escapes because it can be modified after return (mine)

It escapes because it can be referenced after return. A pointer that is only read still forces the heap. (For closures, a never-reassigned variable may be copied into the closure instead.)

### Mistake 5: thinking each function has its own heap (mine)

There is one heap for the whole program, managed by the GC. Escape analysis decides, at compile time, which variables go there.

### Mistake 6: thinking a shadowed `err` still reaches the caller (mine)

`_, err :=` inside an `if` declares a new `err`. The outer one stays `nil`, and the caller concludes the call succeeded. See "Shadowing silently drops errors and values".

### Mistake 7: thinking a `for i := 0; i < 3; i++` loop variable never reaches 3 (mine)

The last `i++` makes it 3, and that's why the 1.21 closures and goroutines usually print `3 3 3`.

### Mistake 8: thinking a mutex fixes the loop-variable goroutine bug (mine)

It removes the data race but not the sharing: every goroutine still reads the one `i`, usually after the loop. Give each goroutine its own copy.

### Mistake 9: thinking a deferred call's arguments are evaluated at return (mine)

They're evaluated when the `defer` line runs, function calls included (`time.Since(start)`, `label()`, `tick(1)`). Only the call waits. Passing the value into a deferred closure as an argument has the same effect.

### Mistake 10: thinking deferred calls run in the order they're written (mine)

They run in reverse: last deferred, first run.

### Mistake 11: reading `func f() (n int)` as a function that takes an input (mine)

The first `()` is the empty parameter list; `(n int)` is a named result.

### Mistake 12: writing Go parameters TypeScript-style, `func(x: int)` (mine)

Go writes the name, then the type, with no colon: `func(v string)`. The colon is a compile error: `syntax error: unexpected : in parameter list`.

### Mistake 13: declaring a named function inside `main` (mine)

Named functions are declared only at the top level of a file. Inside a function, use a function literal: `f := func() (n int) { … }`.

## Related notes

- [[Goroutines and Channels]]
- [[Go Channel Pitfalls and Internals]]
- [[Worker Pool]]
- [[sync.WaitGroup]]
- [[Value Pointer and Ownership]]
- [[Raft Leader Election and Voting]]
- [[React Rendering and State]] (closures in JavaScript: "Snapshots and closures")
- [[Interview MOC]]
