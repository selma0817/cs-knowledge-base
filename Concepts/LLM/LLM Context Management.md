---
tags: [memory, agents, context-window]
date: 2026-06-24
aliases: [Message Compaction, Context Limits, Sliding Window]
---
LLM sequence lengths are hard-capped by their training architecture. The mathematical input tensor shape during training is [batch_size, seq_len, embed_dim]. 

Compaction is not natively handled by the LLM in the background; it must be explicitly built into the application layer. 

## Strategies for Exceeding the Window
* **The Sliding Window:** The application simply chops off the oldest messages. Fast, but the AI suffers amnesia.
* **Active Summarization:** The application makes a hidden, separate API call to summarize old messages, then injects that summary into the new payload.

## Handling Summarization Latency
If a user messages you while a background autocompaction summary is "in flight," you hit a race condition.
* **Best Practice (The Optimistic Strategy):** Send the *old summary* + *raw messages* + *new user input*. This guarantees zero latency for the user while maintaining perfect context, at the cost of a temporarily bloated token payload. [^1]

**Related:**
* Structuring payloads for these limits: [[LLM API Standards]]

---
[^1]: This temporary cost increase is considered the industry standard tradeoff to avoid latency degradation in conversational AI.