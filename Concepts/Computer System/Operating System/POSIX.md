---
date: 2026-08-15
aliases:
  - operating system
  - posix
---





**POSIX** stands for **Portable Operating System Interface**. It is a family of standards defining a portable common interface and behavior for Unix-like systems.

POSIX is:
- A written specification and behavioral contract
- A portability target for operating systems, libraries, utilities, and applications
- Broader than the kernel alone

POSIX is not:

- An operating system
- A program that runs alongside applications
- One module stored inside the kernel
- A runtime dictionary that maps commands to implementations

## Specification versus implementation

POSIX maps standardized names to required behavior, not to per-OS code:

```text
POSIX specifies: read() must have defined behavior
Linux provides:  Linux library and kernel implementation
macOS provides:  macOS library and kernel implementation
```

The operating system does not reread the POSIX document during every operation. Developers implement the contract ahead of time, just as browsers and servers implement HTTP without rereading its specification for every request.

The HTTP analogy has a limit: HTTP primarily standardizes messages exchanged over a network, whereas POSIX primarily standardizes APIs, shell behavior, utilities, and operating-system semantics.

## What POSIX specifies

```text
POSIX
â”œâ”€â”€ Programming APIs
â”‚   â”œâ”€â”€ open(), read(), write(), close()
â”‚   â”œâ”€â”€ process and signal APIs
â”‚   â”œâ”€â”€ pthread_mutex_lock()
â”‚   â””â”€â”€ semaphore APIs
â”œâ”€â”€ Shell language
â”‚   â”œâ”€â”€ variables and quoting
â”‚   â”œâ”€â”€ loops and conditionals
â”‚   â”œâ”€â”€ pipelines
â”‚   â””â”€â”€ redirection
â””â”€â”€ User-space utilities
    â”œâ”€â”€ cat
    â”œâ”€â”€ ls
    â”œâ”€â”€ rm
    â”œâ”€â”€ cp
    â””â”€â”€ grep
```

`cat`, `ls`, and `rm` are normally user-space executables, not special kernel commands. POSIX specifies their portable behavior; each system supplies its own executable implementation.

## Tracing `cat notes.txt`

```text
shell parses the command
        â†“
shell searches PATH for the cat executable
        â†“
shell starts the user-space cat process
        â†“
cat uses file APIs such as open, read, and write
        â†“
system libraries and the kernel perform file I/O
```

There is no special `cat` system call. `cat` is a program built from lower-level interfaces.

## Why POSIX is useful

Without a common standard, every Unix-like system could expose unrelated commands and function names. POSIX provides a portable common subset.

A POSIX-oriented shell script:

```sh
#!/bin/sh

for file in *.txt; do
    cat "$file"
done
```

can usually run across different Unix-like systems. A C program using POSIX interfaces can similarly be compiled separately for Linux and macOS.

This is generally **source-level portability**, not a guarantee that one compiled binary runs unchanged on every system.

## Standard subset and extensions

Operating systems may provide features beyond POSIX:

```text
system functionality
â”œâ”€â”€ portable POSIX subset
â””â”€â”€ OS- or implementation-specific extensions
```

For example, common options such as `ls -l` are portable, while GNU-specific long options may not exist in a BSD implementation. Bash and Zsh support much of the POSIX shell language but also add non-POSIX syntax.

Portable scripts should use the standardized subset when cross-system compatibility matters.

## POSIX API versus system call

A POSIX API name is not automatically a kernel system call.

```text
application
    â†“
POSIX-facing library API
    â†“ when needed
OS-specific system call
    â†“
kernel
```

Some APIs are implemented mostly in userspace. Others are library wrappers that enter the kernel. POSIX specifies observable behavior, while the operating system and libraries choose the mechanism.

Examples:

| Item | Classification |
| --- | --- |
| POSIX | Specification |
| `cat` executable | User-space utility |
| `pthread_mutex_lock()` | POSIX-standardized library API |
| Linux `futex` | Linux-specific system call/mechanism |

## POSIX mutex and Linux futex

`pthread_mutex_lock()` can often acquire an uncontended mutex entirely in userspace:

```text
atomic unlocked â†’ locked
        â†“
return without entering kernel
```

Under contention, an implementation may briefly spin and then ask the OS to park the calling thread. On Linux, the slow path may use `futex`; macOS can use a different platform-specific mechanism.

Therefore:

- POSIX standardizes `pthread_mutex_lock()` behavior.
- The library implements its fast and slow paths.
- Linux `futex` is one possible lower-level mechanism, not a POSIX API.
- POSIX does not mandate one identical mutex algorithm across operating systems.

With a POSIX thread mutex, a blocked execution context is an OS thread. With Go's [[Mutex]], the Go runtime can park a goroutine and let its OS thread run another goroutine.

## How to identify POSIX interfaces

Useful sources include:

- The published POSIX standard
- POSIX-oriented manual pages, when installed, such as `man 1p cat` or `man 3p pthread_mutex_lock`
- Headers such as `<unistd.h>`, `<pthread.h>`, and `<semaphore.h>`
- System conformance documentation

Header files declare callable interfaces, while system libraries, utilities, and kernels contain their implementations. Headers may also expose extensions, so the standard remains the definitive contract.

## Interview summary

> POSIX is a specification defining a portable common interface for Unix-like systems, including programming APIs, shell behavior, and user-space utilities. It is not an operating system or kernel module. Linux and macOS can expose the same POSIX contract through different libraries, executables, kernel code, and OS-specific mechanisms. This provides source portability while still allowing platform-specific extensions.

## Related notes

- [[Mutex]]
- [[Semaphore]]
- [[File Descriptors and Kernel IO Objects]]
- [[Interprocess Communication MOC]]
- [[Interprocess Communication Pipes and Sockets]]
- [[Unix Domain Sockets]]
- [[Concurrency MOC]]