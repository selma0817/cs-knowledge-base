---
date: 2026-06-25
aliases:
  - Continuous Batching
  - In-Flight Batching
  - Iteration-Level Scheduling
  - PagedAttention
  - KV Cache Paging
tags:
  - ai/llm/inference
  - ai/llm/serving
  - ai/kv-cache
  - ai/system
  - ai/vllm
status: evergreen
---
## Summary

[[Continuous Batching]] and [[PagedAttention]] are two complementary techniques for efficient [[LLM Serving]].

They solve different problems:

```text
Continuous batching = scheduling problem
PagedAttention = KV-cache memory-management problem
```

More precisely:

```text
Continuous batching asks:
  Which requests should run together at this decode step?

PagedAttention asks:
  Where should each request's KV cache live in GPU memory?
```

Continuous batching keeps the GPU busy by dynamically adding and removing requests between decoding iterations.

PagedAttention makes that dynamic serving workload practical by storing each request's [[KV Cache]] in small non-contiguous blocks, similar to virtual memory paging in operating systems.

---

## 1. Why LLM Serving Is Different from Normal Batching

For a normal classifier, batching is simple:

```text
batch of images → one forward pass → labels
```

Most requests in the batch finish at the same time.

For an autoregressive LLM, generation is iterative:

```text
prompt → prefill → decode → decode → decode → ...
```

Each decode step usually generates **one token per active request**.

Different requests may need very different numbers of output tokens:

```text
Request A: 20 output tokens
Request B: 500 output tokens
Request C: 40 output tokens
Request D: 300 output tokens
```

So the batch is naturally uneven. Some requests finish early, while others continue for hundreds of iterations.

This makes naive static batching inefficient.

---

## 2. Prefill vs Decode

LLM inference has two main phases:

|Phase|What happens|Parallelism|
|---|---|---|
|[[Prefill]]|process the whole prompt and create the initial [[KV Cache]]|highly parallelizable|
|[[Autoregressive Decoding]]|generate one new token at a time|sequential across output positions|

During prefill, all prompt tokens are known upfront. Even though causal attention prevents tokens from seeing future tokens, the model can compute masked attention for many prompt positions in parallel.

During decode, future tokens do not exist yet. The model must sample token $t$ before it can compute token $t+1$.

So:

```text
Prefill:
  many known input tokens can be processed in parallel

Decode:
  future generated tokens must be produced one step at a time
```

This is why serving systems need special scheduling logic during decoding.

---

## 3. Static Batching

In static batching, the server forms a batch of requests and keeps the batch mostly fixed until the batch is done.

Example:

```text
Initial batch:
A B C D
```

Suppose the output lengths are:

```text
A: 20 tokens
B: 500 tokens
C: 40 tokens
D: 300 tokens
```

After 40 decoding steps:

```text
A: finished
B: still running
C: finished
D: still running
```

A static batch may now look like:

```text
empty slot, B, empty slot, D
```

The GPU is still running, but part of the batch is empty. If many requests finish early, GPU utilization drops.

The system is effectively limited by the longest-running requests in the batch.

---

## 4. Continuous Batching

[[Continuous Batching]], also called [[Iteration-Level Scheduling]] or [[In-Flight Batching]], fixes this by changing the batch between decoding iterations.[1](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-orca)[2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-tensorrt)

Instead of waiting for the whole batch to finish, the scheduler repeatedly does this:

```text
1. Run one decode iteration for active requests.
2. Remove requests that finished.
3. Add new waiting requests if there is capacity.
4. Run the next decode iteration.
```

Example:

```text
Step 1:
A B C D

Step 20:
A finishes
E enters
E B C D

Step 40:
C finishes
F enters
E B F D
```

The batch stays dense over time.

The key idea:

> Continuous batching schedules work at the level of decode iterations, not whole requests.

---

## 5. What Continuous Batching Improves

Continuous batching mainly improves:

- GPU utilization
    
- serving throughput
    
- queueing latency under load
    
- ability to handle variable-length generations
    

It does **not** reduce the intrinsic compute or KV cache required by an individual request.

For one request, the KV cache size is still determined by:

$$  
T_{\text{cache}} = T_{\text{prompt}} + T_{\text{generated so far}}  
$$

So continuous batching does not change the per-request cache formula:

# $$  
\text{KV Cache Bytes}

2  
\times B  
\times T  
\times L  
\times H_{kv}  
\times d_h  
\times b  
$$

Instead, it improves how many active requests the system can serve efficiently over time.

---

## 6. Latency vs Throughput

Continuous batching is mainly a throughput optimization.

It does not make one request mathematically cheaper. A request that needs 500 decoding steps still needs about 500 sequential decoding steps.

However, continuous batching can reduce **queueing latency** because new requests do not have to wait for an entire static batch to finish before entering service.

|Latency / throughput concept|Effect of continuous batching|
|---|---|
|Per-token compute cost|not fundamentally reduced|
|Number of decode steps for one request|not reduced|
|Queueing latency under load|often reduced|
|GPU utilization|improved|
|System throughput|improved|

Clean mental model:

```text
Continuous batching does not make each request smaller.
It keeps the GPU doing useful work while many requests come and go.
```

---

## 7. Why Continuous Batching Creates a Memory Problem

Continuous batching makes the serving workload dynamic:

```text
requests enter
requests grow token by token
requests finish
new requests enter
```

Each active request owns a [[KV Cache]].

As the request generates tokens, its KV cache grows:

$$  
T_{\text{cache}} = T_{\text{prompt}} + T_{\text{generated so far}}  
$$

So the serving system has to manage many KV caches that:

- start at different lengths
    
- grow at different rates
    
- finish at unpredictable times
    
- free memory at different times
    
- may have very long contexts
    

If the system uses naive contiguous allocation, memory can be wasted badly.

---

## 8. Naive KV Cache Allocation

A naive serving system might allocate one large contiguous memory region for each request.

Example:

```text
Request A KV cache: [....................]
Request B KV cache: [........................................]
Request C KV cache: [..........]
```

This creates two major problems.

### Internal Fragmentation

Internal fragmentation happens when a request reserves more memory than it actually uses.

Example:

```text
Reserved capacity: 4096 tokens
Actually used:     200 tokens
Wasted:            3896 tokens
```

The unused space is inside the allocated region.

### External Fragmentation

External fragmentation happens when free memory exists, but it is scattered into pieces that are hard to reuse for large contiguous allocations.

Example:

```text
Free memory:
[free] [used] [free] [used] [free]
```

There may be enough total free memory, but not enough contiguous free memory.

Both types of fragmentation reduce the effective KV-cache capacity of the GPU.

---

## 9. PagedAttention

[[PagedAttention]] solves the KV-cache memory-management problem by borrowing the idea of paging from operating systems.[3](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-vllm)

Instead of storing each request's KV cache in one large contiguous chunk, PagedAttention splits the KV cache into fixed-size blocks or pages.

A request's logical KV cache may look continuous:

```text
logical KV blocks:
0 → 1 → 2 → 3 → 4
```

But the physical GPU memory blocks may be scattered:

```text
physical GPU blocks:
17 → 5 → 91 → 12 → 44
```

The serving engine maintains a mapping from logical blocks to physical blocks.

This is similar to a page table.

---

## 10. Operating System Analogy

|Operating system virtual memory|PagedAttention / LLM serving|
|---|---|
|process|request / sequence|
|virtual address space|logical KV cache of a request|
|physical memory page|physical GPU KV-cache block|
|page table|block table mapping logical KV blocks to physical blocks|
|allocating a new page|assigning a new KV block as the sequence grows|

The request can behave as if it owns a continuous KV cache, while the serving system can place the physical blocks wherever GPU memory is available.

This improves memory utilization.

---

## 11. Why PagedAttention Helps

PagedAttention helps because requests do not need to reserve maximum possible KV memory upfront.

Instead, they receive KV blocks as needed.

If a request stops early, the unused future blocks were never allocated.

If a request grows longer, it can be assigned additional blocks.

This reduces:

- over-allocation
    
- internal fragmentation
    
- external fragmentation
    
- wasted KV-cache memory
    
- pressure to reduce batch size because of memory limits
    

The result is that the same GPU memory can support more active tokens and more concurrent requests.

---

## 12. Continuous Batching vs PagedAttention

The distinction:

```text
Continuous batching:
  scheduling active requests over time

PagedAttention:
  allocating and addressing KV-cache blocks
```

They solve different layers of the serving problem.

|Technique|Main problem solved|What it changes|
|---|---|---|
|[[Continuous Batching]]|static batches become sparse when requests finish at different times|request scheduling|
|[[PagedAttention]]|KV cache memory is fragmented and over-allocated|KV-cache memory layout|
|[[MQA]] / [[GQA]] / [[MLA]]|each token's KV cache is too large|model architecture|

A compact mapping:

```text
MQA/GQA/MLA:
  reduce per-token KV cache size

Continuous batching:
  keeps the GPU batch full over time

PagedAttention:
  reduces KV-cache memory fragmentation
```

---

## 13. Relationship to GQA, MQA, and MLA

[[Grouped-Query Attention]], [[Multi-Query Attention]], and [[Multi-Head Latent Attention]] reduce the amount of KV data stored per token.

They act at the model architecture level.

For example, in GQA:

```text
num_query_heads = 32
num_kv_heads = 8
```

The model still has 32 query heads, but it stores only 8 KV heads.

So GQA reduces the $H_{kv}$ term in the KV-cache formula:

# $$  
\text{KV Cache Bytes}

2  
\times B  
\times T  
\times L  
\times H_{kv}  
\times d_h  
\times b  
$$

Continuous batching and PagedAttention do not directly change $H_{kv}$.

Instead:

```text
GQA/MQA/MLA:
  reduce how much KV each token needs

Continuous batching:
  schedules requests efficiently

PagedAttention:
  stores KV memory efficiently
```

---

## 14. Full Serving Story

A high-throughput LLM serving system often combines all three ideas:

```text
1. Model architecture reduces KV per token.
   Example: GQA, MQA, MLA

2. Scheduler keeps active batch full.
   Example: continuous batching

3. Memory manager stores KV cache efficiently.
   Example: PagedAttention
```

Together:

```text
GQA reduces how much memory each token needs.
Continuous batching keeps the GPU busy.
PagedAttention makes dynamic KV allocation efficient.
```

This is why modern LLM serving engines are not just “running a model.” They are scheduling systems and memory managers built around the constraints of [[Autoregressive Decoding]].

---

## 15. Key Takeaways

1. LLM generation is iterative and variable-length, so static batching wastes GPU capacity.
    
2. Continuous batching dynamically removes finished requests and admits new requests between decode iterations.
    
3. Continuous batching improves throughput and GPU utilization, but it does not reduce the KV cache size of an individual request.
    
4. Each request's KV cache grows with prompt length plus generated tokens so far.
    
5. Dynamic batching creates dynamic KV-cache allocation problems.
    
6. Naive contiguous KV allocation can cause internal fragmentation, external fragmentation, and over-allocation.
    
7. PagedAttention stores KV cache in fixed-size blocks/pages instead of one large contiguous region.
    
8. PagedAttention lets a request have a logical contiguous KV cache while using non-contiguous physical GPU memory.
    
9. GQA/MQA/MLA reduce per-token KV cache size; continuous batching improves scheduling; PagedAttention improves memory allocation.
    

---

## Related Concepts

- [[Transformer]]
    
- [[Self-Attention]]
    
- [[Multi-Head Attention]]
    
- [[Multi-Query Attention]]
    
- [[Grouped-Query Attention]]
    
- [[Multi-Head Latent Attention]]
    
- [[KV Cache]]
    
- [[Autoregressive Decoding]]
    
- [[Prefill]]
    
- [[Decode]]
    
- [[LLM Serving]]
    
- [[PagedAttention]]
    
- [[Continuous Batching]]
    
- [[Quantization]]
    
- [[vLLM]]
    
- [[TensorRT-LLM]]
    

---

## Footnotes

1. Gyeong-In Yu et al., “Orca: A Distributed Serving System for Transformer-Based Generative Models,” OSDI 2022. This paper introduced iteration-level scheduling for transformer serving. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-orca)
    
2. NVIDIA TensorRT-LLM documentation uses the term “in-flight batching” for continuous batching-style request scheduling in production inference systems. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-tensorrt)
    
3. Woosuk Kwon et al., “Efficient Memory Management for Large Language Model Serving with PagedAttention,” 2023. This paper introduced PagedAttention and the vLLM serving engine. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-vllm)