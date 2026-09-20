---
date: 2026-06-02
tags:
  - go
  - pointer
  - value
  - ownership
  - concurrency
  - data-race
---
## One-sentence meaning

In Go, passing values usually copies data, passing pointers copies an address to shared data, and ownership in Go concurrency is an informal design rule about which goroutine is allowed to mutate a piece of data.

## Go does not have Rust-style ownership

Go does not enforce ownership through the type system like Rust.

In Go, ownership is usually a programmer discipline.

When Go programmers say “ownership,” they often mean:

```text
Which goroutine is responsible for this data now?
Which goroutine is allowed to mutate it?
Who closes this channel?
Who owns the lifecycle of this resource?
```

## Value semantics

When passing a struct value to a function, Go copies the struct.

```go
type User struct {
    Name string
}

func update(u User) {
    u.Name = "new"
}
```

Calling this:

```go
user := User{Name: "old"}
update(user)
fmt.Println(user.Name)
```

The original `user.Name` is still:

```text
old
```

Why?

```text
update received a copy of the User value.
```

## Pointer semantics

A pointer is an address to a value.

```go
func update(u *User) {
    u.Name = "new"
}
```

Calling this:

```go
user := User{Name: "old"}
update(&user)
fmt.Println(user.Name)
```

Now the original `user.Name` becomes:

```text
new
```

Why?

```text
update received a copy of the pointer,
but the pointer points to the original User.
```

Important detail:

```text
Go still passes the pointer value by copy.
But the copied pointer points to shared data.
```

## Method receivers

Value receiver:

```go
func (u User) Rename(name string) {
    u.Name = name
}
```

This modifies a copy.

Pointer receiver:

```go
func (u *User) Rename(name string) {
    u.Name = name
}
```

This modifies the original value.

Use pointer receiver when:

- the method should mutate the receiver
    
- copying the receiver is expensive
    
- the type contains synchronization primitives like `sync.Mutex`
    

Use value receiver when:

- the type is small
    
- the method does not mutate the receiver
    
- copying is safe and clear
    

## Sending values through channels

```go
ch <- user
```

If `user` is a struct value, the channel send copies the value into the channel.

Conceptually:

```text
sender has original User
receiver gets a copy of User
```

This is safer for concurrency because the receiver cannot accidentally mutate the sender’s original struct.

## Sending pointers through channels

```go
ch <- &user
```

This sends a copy of the pointer.

Conceptually:

```text
sender and receiver now both have addresses to the same User
```

This can be efficient but dangerous.

If both goroutines mutate the pointed-to data at the same time, there may be a data race.

## Data race

A data race happens when:

```text
two or more goroutines access the same variable concurrently
and at least one access is a write
and there is no synchronization
```

Example:

```go
var counter int

go func() {
    counter++
}()

go func() {
    counter++
}()
```

Both goroutines modify the same variable without synchronization.

This is unsafe.

## Shared memory design

```go
var counter int

go func() {
    counter++
}()

go func() {
    counter++
}()
```

Problem:

```text
multiple goroutines mutate the same memory
without coordination
```

Possible fix:

```go
var mu sync.Mutex
var counter int

go func() {
    mu.Lock()
    counter++
    mu.Unlock()
}()
```

The mutex protects the shared state.

## Channel ownership design

Instead of letting many goroutines mutate shared memory, we can send updates to one owner goroutine.

```go
updates := make(chan int)

go func() {
    updates <- 1
}()

go func() {
    updates <- 1
}()

counter := 0
for i := 0; i < 2; i++ {
    counter += <-updates
}
```

Here, only one goroutine updates `counter`.

The worker goroutines do not mutate shared memory directly. They communicate updates through a channel.

## Share memory by communicating

Go’s slogan:

```text
Do not communicate by sharing memory; share memory by communicating.
```

My interpretation:

```text
Instead of many goroutines touching the same mutable variable,
send messages or ownership through channels,
so one goroutine clearly owns mutation at a time.
```

But this is not magic.

If I send a pointer through a channel, I may still be sharing memory.

```go
ch <- &user
```

After this, both sender and receiver may still access the same `user`.

To use pointer passing safely, I need an ownership rule:

```text
After sender sends the pointer, sender should stop mutating it.
Receiver now owns it.
```

Go does not enforce this automatically.

## Mutex vs channel

Use a `sync.Mutex` when:

- there is shared state
    
- multiple goroutines need access to that state
    
- the state has a clear shared-memory identity
    
- locking is simpler than message passing
    

Example:

```go
type Cache struct {
    mu sync.Mutex
    data map[string]string
}
```

Use a channel when:

- goroutines need to communicate events
    
- work needs to be distributed
    
- ownership should be transferred
    
- one goroutine should coordinate state changes
    
- building pipelines or worker pools
    

Example:

```go
jobs := make(chan Job)
results := make(chan Result)
```

## Backend implication

In a Go HTTP server, requests are often handled concurrently.

This means shared variables must be treated carefully.

Dangerous:

```go
var sessions = map[string]Session{}

func handler(w http.ResponseWriter, r *http.Request) {
    sessions["abc"] = Session{}
}
```

If multiple requests access the map concurrently, there can be a data race or runtime panic.

Safer options:

- protect the map with `sync.Mutex`
    
- use `sync.Map`
    
- avoid shared mutable state
    
- store state in database/Redis
    
- use a single owner goroutine and communicate through channels
    

## Safe mental model

```text
Sending value:
  safer, makes a copy, less shared mutable state

Sending pointer:
  faster for large data, but may share mutable state

Mutex:
  protects shared memory

Channel:
  communicates values, events, or ownership
```

## Related notes

- [[Goroutines and Channels]]
    
- [[Concurrency vs Parallelism]]
    
- [[Data Race]]
    
- [[sync.Mutex]]
    
- [[sync.WaitGroup]]
    
- [[Worker Pool]]
    
- [[Go Context]]
    
- [[Go HTTP Server]]