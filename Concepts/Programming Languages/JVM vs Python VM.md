---
date: 2026-06-27
tags:
  - jvm
  - python
  - cpython
  - virtual-machine
  - byte-code
  - jit
  - compiler
  - interpreter
---
## One-sentence meaning

The JVM is a standardized virtual machine platform that runs Java bytecode and heavily uses JIT optimization, while Python’s virtual machine usually refers to CPython’s internal bytecode interpreter that executes Python bytecode.

## Why I care

I hear a lot about the JVM but much less about the Python VM. This can make it feel like Java has a virtual machine but Python does not.

Actually, Python also has a virtual machine. The difference is that the JVM is treated as a major runtime platform, while CPython’s VM is usually treated as an implementation detail of the Python interpreter.

## Basic execution pipeline

### Java

```text
Java source code
  ↓ javac
JVM bytecode / .class files
  ↓ JVM
interpreted and/or JIT-compiled execution
```

### Python / CPython

```text
Python source code
  ↓ CPython parser/compiler
CPython bytecode / .pyc files
  ↓ CPython virtual machine / evaluation loop
interpreted execution
```

Both Java and Python can involve:

```text
source code
  ↓
AST or internal representation
  ↓
bytecode
  ↓
virtual machine execution
```

But the role and stability of the virtual machine are different.

## JVM

JVM means Java Virtual Machine.

It is a runtime that executes JVM bytecode.

The JVM is not only for Java. Other languages can compile to JVM bytecode too, such as:

- Kotlin
    
- Scala
    
- Clojure
    
- Groovy
    

This is one reason people talk about the JVM as a platform.

A Java project usually compiles source files into `.class` files:

```text
User.java
  ↓ javac
User.class
```

Then the JVM loads and runs those class files.

## Python VM

Python also has a virtual machine, especially in the default implementation called CPython.

CPython usually works like this:

```text
main.py
  ↓ parse / compile
Python bytecode
  ↓ CPython evaluation loop
program runs
```

The bytecode may be cached in `__pycache__` as `.pyc` files.

People usually do not say “Python VM” as often. They usually say:

- Python interpreter
    
- CPython
    
- Python runtime
    

But conceptually, CPython has a virtual machine because it executes Python bytecode.

## Core difference

The JVM is a stable runtime platform.

CPython bytecode is mostly an internal implementation detail.

This means:

```text
JVM bytecode
  = relatively stable platform target

CPython bytecode
  = internal execution format used by CPython
```

This is why Java/Kotlin/Scala/Clojure can all target the JVM as a shared platform, while Python bytecode is not usually used as a general cross-language platform.

## JIT difference

The JVM usually has a mature JIT compiler.

JIT means Just-In-Time compilation.

The JVM can start by interpreting bytecode, then detect hot methods and compile them into optimized native machine code.

```text
JVM bytecode
  ↓ interpreter starts running
  ↓ hot method detected
  ↓ JIT compilation
  ↓ optimized machine code
```

Traditional CPython mostly interprets Python bytecode.

```text
Python bytecode
  ↓ CPython evaluation loop
  ↓ interpreted execution
```

Modern CPython has been adding more optimization, such as a specializing adaptive interpreter and experimental JIT work, but JIT is still much more central to the JVM performance model than to normal Python execution.

## Why JVM performance is often better for backend

Java backend services are usually long-running.

This gives the JVM time to observe hot code paths and optimize them.

The JVM can optimize using information from:

- static types
    
- method signatures
    
- class layout
    
- runtime profiling
    
- hot method detection
    
- JIT compilation
    

Python is harder to optimize aggressively because Python is dynamically typed and late-bound.

Example:

```python
def add(a, b):
    return a + b
```

In Python, `a + b` could mean:

- integer addition
    
- float addition
    
- string concatenation
    
- list concatenation
    
- NumPy array addition
    
- custom `__add__` behavior
    

A Python optimizer can still specialize based on runtime behavior, but it needs guards and fallback paths.

In Java:

```java
int add(int a, int b) {
    return a + b;
}
```

The JVM knows:

- `a` is an `int`
    
- `b` is an `int`
    
- `+` is integer addition
    
- the return type is `int`
    

This makes optimization easier.

## Why Python version matters

Python version matters because it can affect many layers:

```text
Python source grammar
AST shape
bytecode instructions
interpreter optimization behavior
standard library
C API / ABI
package wheel compatibility
runtime performance
```

For example, code that runs on Python 3.12 may not run on Python 3.8 if it uses newer syntax or newer standard library APIs.

Python package compatibility also often depends on the Python version, especially for packages with native extensions.

This is why I often see constraints like:

```text
requires-python >=3.10
cp311 wheel
cp312 wheel
```

The `cp311` or `cp312` part means the wheel targets a specific CPython version.

## Why Java version seems to matter less

Java version does matter, especially in backend. People talk about:

- Java 8
    
- Java 11
    
- Java 17
    
- Java 21
    
- Java 25
    

But Java has a strong culture of bytecode compatibility and long-term supported releases.

Java code can be compiled to target a specific release:

```text
Java source
  ↓ javac --release 17
class files targeting Java 17
  ↓ run on compatible JVM
```

So Java version matters, but it is often managed through:

- JDK version
    
- language source level
    
- target class-file version
    
- JVM version
    
- framework baseline
    
- LTS release choice
    

In Python, the interpreter version is usually directly what runs the code:

```bash
python3.10 app.py
python3.11 app.py
python3.12 app.py
```

So Python version feels more directly visible.

## Important distinction

A language and its runtime are not the same thing.

```text
Java language
  = syntax and semantics of Java

JVM
  = runtime platform that executes JVM bytecode
```

```text
Python language
  = syntax and semantics of Python

CPython
  = default Python implementation

CPython VM
  = internal bytecode execution engine inside CPython
```

Other Python implementations exist, such as PyPy. PyPy has a JIT and can run some pure Python code faster than CPython, but CPython remains the dominant implementation because of ecosystem compatibility.

## Comparison table

|Aspect|JVM|Python VM / CPython VM|
|---|---|---|
|Main role|General runtime platform|Internal execution engine for CPython|
|Input|JVM bytecode / `.class` files|CPython bytecode / `.pyc` files|
|Common languages|Java, Kotlin, Scala, Clojure|Python|
|Bytecode stability|More platform-like|Implementation detail|
|JIT|Mature and central|Experimental / less central in CPython|
|Performance model|Long-running JIT-optimized services|Interpreted bytecode plus native extensions|
|Version concern|JDK/JVM/source/target compatibility|Interpreter version, syntax, bytecode, packages, ABI|
|Ecosystem identity|“Runs on the JVM”|“Runs on Python/CPython”|

## Mental model

The JVM is like a public runtime target.

```text
Java / Kotlin / Scala / Clojure
  ↓
JVM bytecode
  ↓
JVM
```

CPython’s VM is more like the engine inside the Python interpreter.

```text
Python source
  ↓
CPython bytecode
  ↓
CPython evaluation loop
```

## Common misunderstanding

It is not true that Java has a VM and Python does not.

More accurate:

```text
Both Java and Python can run through virtual machines.

The JVM is a standardized, visible, multi-language runtime platform.

CPython’s VM is mostly an internal implementation detail of the Python interpreter.
```

## Related notes

- [[Compiler vs Interpreter]]
    
- [[AST]]
    
- [[Bytecode]]
    
- [[Virtual Machine]]
    
- [[JIT Compilation]]
    
- [[CPython]]
    
- [[JVM]]
    
- [[Static vs Dynamic Typing]]
    
- [[Strong vs Weak Typing]]
    
- [[Python Interpreter]]
    
- [[Java Compiler]]