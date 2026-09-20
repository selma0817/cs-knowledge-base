---
date: 2026-06-27
tags:
  - compiler
  - interpreter
  - bytecode
  - infrastructure
  - runtime
  - java
  - python
---
# Compiler vs Interpreter

## One-sentence meaning

A compiler translates code into another representation before execution, while an interpreter executes code directly or executes an intermediate representation such as bytecode.

## Core mental model

Source code is plain text.

Before a programming language runtime can execute it, the text usually goes through several stages:

```text
source code
  ↓
tokens
  ↓
AST / syntax tree
  ↓
bytecode or machine code
  ↓
execution
```

The AST, or Abstract Syntax Tree, is a tree-shaped representation of the program structure.

Bytecode is not the same thing as the AST. The AST is tree-shaped. Bytecode is usually a flatter instruction sequence for a virtual machine.

## Compiler

A compiler translates code from one representation into another representation.

Examples:

```text
Go source code
  ↓ go build
native executable
```

```text
Java source code
  ↓ javac
JVM bytecode class files
```

```text
.proto file
  ↓ protoc
generated Go / Java / Python code
```

So a compiler does not always compile directly to machine code. Sometimes it compiles to bytecode or another programming language.

## Interpreter

An interpreter executes code directly, or executes a lower-level intermediate representation.

A simple interpreter might walk the AST directly:

```text
AST
  ↓ tree-walking interpreter
program behavior
```

But many real interpreters first compile source code into bytecode and then interpret the bytecode:

```text
source code
  ↓
bytecode
  ↓
virtual machine executes bytecode
```

## Python runtime model

In traditional CPython:

```text
Python source code
  ↓
AST / internal compiler representation
  ↓
Python bytecode
  ↓
Python virtual machine executes bytecode
```

Python is often called an interpreted language because users usually run it like this:

```bash
python script.py
```

But internally, Python still has a compilation step into bytecode.

So “interpreted” does not mean “no compilation happens.”

## Java runtime model

Java usually works like this:

```text
Java source code
  ↓ javac
.class bytecode files
  ↓ JVM
interpreted and/or JIT-compiled execution
```

The JVM can initially interpret bytecode, but hot code paths can be JIT-compiled into optimized native machine code at runtime.

This is one reason Java can perform very well for long-running backend services.

## Why Java can be faster than Python even though both use bytecode

Both Java and Python can use bytecode, but the runtime behavior is different.

### Java

```text
Java bytecode
  ↓ JVM interpreter first
  ↓ hot methods JIT-compiled
  ↓ optimized native machine code
```

Java also has static types, mature JVM optimization, efficient multi-threading, and a large backend ecosystem.

For long-running backend services, the JVM can observe which code paths are hot and optimize them aggressively.

### Python / CPython

```text
Python bytecode
  ↓ Python virtual machine
  ↓ interpreted execution
```

Traditional CPython is optimized for flexibility and simplicity, but it usually does not optimize hot code into native machine code in the same way HotSpot JVM does.

CPython also has the GIL, which means only one thread executes Python bytecode at a time in the traditional runtime. This limits CPU-bound multi-threaded performance.

## Why Java is common in backend

Java is common in backend systems because of:

- strong runtime performance after JVM warm-up
    
- mature JIT optimization
    
- strong typing
    
- good multi-threading model
    
- mature frameworks like Spring Boot
    
- mature observability and deployment ecosystem
    
- stable enterprise usage
    
- good fit for large long-running services
    

Python is still common in backend too, especially when developer speed, scripting, data science integration, or machine learning ecosystem matters more than raw throughput.

## Important distinction

“Compiled language” and “interpreted language” are simplified labels.

A more precise view:

```text
Language = syntax and semantics
Implementation/runtime = how the language is executed
```

For example:

```text
Java language
  → javac + JVM implementation

Python language
  → CPython implementation

JavaScript language
  → V8 / SpiderMonkey / JavaScriptCore implementations
```

Different implementations can choose different combinations of parsing, compiling, interpreting, bytecode execution, and JIT compilation.


Python is harder to optimize with JIT because its runtime semantics are highly dynamic: variable types, method lookup, object attributes, and operator behavior are often only known at runtime. Java is easier to optimize because static types and stable method signatures give the JVM stronger assumptions, especially for hot code in long-running backend services.
## Related notes

- [[AST]]
    
- [[Bytecode]]
    
- [[Virtual Machine]]
    
- [[JIT Compilation]]
    
- [[Go Compiler]]
    
- [[Python Interpreter]]
    
- [[JVM]]
