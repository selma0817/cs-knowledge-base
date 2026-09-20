---
tags: [prompt-engineering, latency, cost-optimization, prompt-caching]
date: 2026-06-24
aliases: [Statelessness, Cache Hits, KV Tensors]
---
LLMs have no memory; they are fundamentally stateless. You must send the entire conversation state (system prompt + history + new input) every single time you make an API call.

## The Stateless Paradox
To avoid paying for the same massive system prompt over and over, providers use **Prompt Caching**. The servers save the heavy mathematical computations (Key-Value or KV tensors) in short-term memory.

* **The Golden Rule (Prefix Matching):** Caching only works if the text matches *byte-for-byte* from the very beginning of the prompt. Even a single altered space breaks the cache.
* **Dynamic Variables:** Never put dynamic variables (like `{{current_time}}`) at the top of a prompt. Always append them at the very end (or inject them into the final user input) to maximize the prefix match and trigger a cache hit.

**Related:** * How context size limits work: [[LLM Context Management]]
* How caching works across multiple servers: [[Distributed AI Architecture]]