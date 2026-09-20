---
date: 2026-06-25
aliases:
  - LLM Inference Serving
  - Large Language Model Serving
  - Online LLM Inference
  - LLM Request Lifecycle
tags:
  - ai/llm/serving
  - ai/llm/inference
  - ai/systems
  - ai/kv-cache
status: "status: evergreen"
---
## Summary

[[LLM Serving]] is the system problem of running large language models for real users or applications.

It is not just “call the model once.” A serving system must handle:

```text
request routing
tokenization
batch scheduling
prefill
KV cache allocation
autoregressive decoding
sampling
streaming responses
cleanup
```

The central reason LLM serving is difficult is that [[Autoregressive Decoding]] is iterative and variable-length. Each active request generates tokens one at a time, while maintaining a growing [[KV Cache]].

A useful mental model:

```text
Long prompt → prefill-heavy → high TTFT
Long output → decode-heavy → high total latency / TPOT pressure
Many users → scheduling-heavy → continuous batching matters
Long context → KV-cache-heavy → PagedAttention, GQA, MLA, KV quantization matter
```

---

## 1. Core Request Lifecycle

Suppose a user sends this prompt:

```text
"Explain why KV cache grows linearly."
```

A typical LLM serving path looks like:

```text
1. User sends request
2. Server receives request
3. Prompt is tokenized
4. Request enters queue / scheduler
5. Request is assigned to a model worker
6. Worker runs prefill on the prompt
7. Prefill creates the initial KV cache
8. Model produces logits for the next token
9. Server samples the first generated token
10. If streaming is enabled, first token is sent immediately
11. Request enters decode loop
12. Each decode step generates one new token
13. New token's K/V are appended to KV cache
14. Tokens are streamed until stop condition
15. Request finishes
16. KV cache is freed or retained for prefix/session reuse
```

The key distinction:

```text
Prefill creates the initial KV cache.
Decode extends the KV cache one generated token at a time.
```

---

## 2. Prefill

[[Prefill]] is the phase where the model processes the full input prompt.

During prefill:

```text
the prompt tokens are already known
the model computes masked self-attention over the prompt
the model creates K/V tensors for each prompt token
the initial KV cache is stored
the model produces logits for the first generated token
```

Even though causal attention prevents each token from seeing future tokens, the whole prompt is available upfront. This means the model can process many prompt positions in parallel using a causal mask.

So prefill is usually more parallelizable than decode.

A long prompt mostly increases:

```text
time to first token
```

because the server must process the prompt before it can produce the first output token.

---

## 3. Decode

[[Decode]] is the iterative generation phase.

During decode, the model generates one token at a time:

```text
decode step 1 → sample token 1
decode step 2 → sample token 2
decode step 3 → sample token 3
...
```

At each step:

```text
1. take latest token
2. compute its Q/K/V
3. attend over cached K/V from previous tokens
4. sample next token from logits
5. append new K/V to cache
```

The KV cache length grows as:

$$  
T_{\text{cache}} = T_{\text{prompt}} + T_{\text{generated so far}}  
$$

This is why long outputs stress the decode phase.

A short prompt with a 2000-token answer is usually decode-heavy.

---

## 4. Time to First Token

[[Time to First Token]], or TTFT, is the time from request arrival until the first generated token appears.

Approximate components:

```text
TTFT =
  queueing delay
+ routing delay
+ tokenization
+ prefill scheduling
+ prefill compute
+ initial KV cache creation
+ first-token sampling
```

TTFT is especially affected by:

```text
long prompts
scheduler backlog
prefix-cache miss
slow prefill
routing overhead
cold model workers
```

User symptom:

```text
"The first token takes forever, but once it starts, the answer streams quickly."
```

Likely diagnosis:

```text
TTFT problem
prefill or pre-decode bottleneck
```

Possible fixes:

```text
prefix caching
better routing
prefill batching
chunked prefill
faster tokenizer / lower CPU overhead
more capacity for prefill-heavy workloads
```

---

## 5. Time Per Output Token

[[Time Per Output Token]], or TPOT, is the time between generated tokens after streaming begins.

It measures how fast the decode loop is.

Approximate components:

```text
TPOT =
  decode scheduling delay
+ one-token model forward pass
+ KV cache read/write cost
+ attention kernel cost
+ sampling overhead
+ streaming overhead
```

TPOT is especially affected by:

```text
KV cache size
memory bandwidth
batch size
attention kernels
continuous batching
quantization
sampling overhead
GPU utilization
```

User symptom:

```text
"The first token appears quickly, but the rest of the answer streams slowly."
```

Likely diagnosis:

```text
TPOT problem
decode bottleneck
```

Possible fixes:

```text
continuous batching
PagedAttention
KV-cache quantization
GQA / MQA / MLA
faster attention kernels
better sampling implementation
larger or better-shaped batches
```

---

## 6. End-to-End Latency

[[End-to-End Latency]] is the total time from request arrival to completed response.

Roughly:

# $$  
\text{E2E Latency}

\text{TTFT}  
+  
N_{\text{output tokens}} \times \text{TPOT}  
$$

This is simplified, but useful.

For a long prompt and short answer:

```text
TTFT dominates
```

For a short prompt and long answer:

```text
decode time dominates
```

For many users:

```text
queueing and scheduling dominate
```

---

## 7. KV Cache in Serving

The [[KV Cache]] stores previous keys and values so the model does not recompute them at every decoding step.

The approximate KV cache memory is:

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

where:

|Symbol|Meaning|
|---|---|
|$2$|K and V|
|$B$|active batch size / concurrent sequences|
|$T$|prompt tokens plus generated tokens so far|
|$L$|number of transformer layers|
|$H_{kv}$|number of KV heads|
|$d_h$|head dimension|
|$b$|bytes per KV element|

In serving, KV cache is both:

```text
a memory capacity problem
```

and:

```text
a memory bandwidth problem
```

Capacity problem:

```text
Can the GPU store all active requests' KV caches?
```

Bandwidth problem:

```text
Can the GPU read the needed K/V fast enough every decode step?
```

---

## 8. Continuous Batching

[[Continuous Batching]] keeps the GPU busy by dynamically changing the batch between decode iterations.

Instead of:

```text
form batch
wait for entire batch to finish
start next batch
```

continuous batching does:

```text
run one decode step
remove finished requests
add new waiting requests
run next decode step
```

This is also called:

```text
iteration-level scheduling
in-flight batching
```

The key idea:

> LLM serving should schedule active sequences at each decode iteration, not only at the request level.

Continuous batching mostly improves:

```text
GPU utilization
throughput
queueing latency under load
decode scheduling efficiency
```

It does not directly reduce the KV cache size of an individual request.

Orca is a major serving-system paper associated with iteration-level scheduling for transformer serving.[1](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-orca)

TensorRT-LLM uses the production term “in-flight batching” for this style of dynamic request execution.[2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-tensorrt)

---

## 9. PagedAttention

[[PagedAttention]] addresses KV-cache memory management.

Naive KV-cache allocation may require large contiguous memory blocks for each request. This can cause:

```text
internal fragmentation
external fragmentation
over-allocation
wasted KV-cache memory
```

PagedAttention splits each request's KV cache into fixed-size blocks/pages.

Logical view:

```text
request KV blocks:
0 → 1 → 2 → 3 → 4
```

Physical GPU memory:

```text
GPU blocks:
17 → 5 → 91 → 12 → 44
```

The request behaves as if its KV cache is continuous, but the physical GPU memory does not need to be contiguous.

This is analogous to virtual memory paging in operating systems.

PagedAttention was introduced with vLLM to reduce KV-cache memory waste and improve throughput.[3](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-vllm)

---

## 10. Prefix Caching and Cache-Aware Routing

[[Prefix Caching]] reuses previously computed KV cache for repeated prompt prefixes.

It helps most when many requests share a long prefix, such as:

```text
same system prompt
same few-shot examples
same long document prefix
same retrieved context prefix
same conversation history prefix
```

Prefix caching mostly reduces:

```text
prefill cost
TTFT
```

It does not remove the need to decode new output tokens.

In distributed serving, a router may use cache metadata to send a request to a worker that already has the longest matching prefix.

Basic serving:

```text
request → scheduler → worker
```

Cache-aware serving:

```text
request
→ tokenize / hash prefix blocks
→ check prefix-cache metadata
→ route to worker with best prefix reuse
→ prefill uncached suffix
→ decode
```

This connects to the distinction between:

```text
control plane:
  routing, scheduling, metadata, policy

data plane:
  model forward passes, KV cache reads/writes, token streaming
```

---

## 11. Quantization in Serving

[[Quantization]] reduces the number of bits used to represent tensors.

Different quantization targets solve different serving problems:

|Target|Helps with|
|---|---|
|[[Weight Quantization]]|model weights too large|
|[[KV Cache Quantization]]|long-context / high-concurrency runtime memory|
|[[Activation Quantization]]|compute and memory bandwidth|

Weight-only quantization may help a model fit on GPU, but it does not directly shrink the KV cache.

KV-cache quantization directly reduces the bytes-per-element term:

$$  
b  
$$

in the KV-cache formula.

KIVI is an example of a method designed specifically for KV-cache quantization.[4](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-kivi)

Clean rule:

> Quantize the thing that is causing the bottleneck.

---

## 12. Architecture-Level KV Reduction

Some model architectures reduce KV cache pressure directly.

Examples:

```text
MQA
GQA
MLA
```

[[Multi-Query Attention]] reduces KV heads to one.

[[Grouped-Query Attention]] uses fewer KV heads than query heads.

[[Multi-Head Latent Attention]] stores compressed latent KV representations.

These reduce the per-token KV burden at the model architecture level.

In contrast:

```text
Continuous batching changes scheduling.
PagedAttention changes memory allocation.
Quantization changes numerical representation.
```

---

## 13. Serving Bottleneck Diagnosis

A useful diagnostic map:

|User/system symptom|Likely bottleneck|Relevant concepts|
|---|---|---|
|First token is slow, stream is fast|TTFT / prefill|prefill, prefix caching, routing|
|First token is fast, stream is slow|TPOT / decode|KV cache, continuous batching, kernels|
|Model does not fit on GPU|weight memory|weight quantization, tensor parallelism|
|Long-context requests run out of memory|KV cache capacity|GQA, MLA, KV quantization, PagedAttention|
|GPU utilization is low|scheduling|continuous batching|
|Memory exists but cannot be used efficiently|fragmentation|PagedAttention|
|Many shared prompts repeat|redundant prefill|prefix caching|
|Tokens/sec is poor despite enough VRAM|bandwidth/kernel/scheduling|attention kernels, batching, quantization|

---

## 14. Request Types and Dominant Costs

### Long Prompt, Short Answer

Example:

```text
Summarize this 100-page document in 3 bullet points.
```

Dominant cost:

```text
prefill
TTFT
```

Useful techniques:

```text
prefix caching
chunked prefill
fast attention kernels
cache-aware routing
```

---

### Short Prompt, Long Answer

Example:

```text
Write a 2000-token essay about LLM serving.
```

Dominant cost:

```text
decode
TPOT
end-to-end latency
```

Useful techniques:

```text
continuous batching
KV-cache optimization
faster decode kernels
sampling optimization
```

---

### Many Concurrent Users

Dominant cost:

```text
scheduling
batch utilization
KV-cache capacity
```

Useful techniques:

```text
continuous batching
PagedAttention
KV-cache quantization
request admission control
```

---

### Long Context and Many Users

Dominant cost:

```text
KV cache memory
KV cache bandwidth
```

Useful techniques:

```text
GQA / MQA / MLA
KV-cache quantization
PagedAttention
prefix caching
```

---

## 15. The Full Mental Model

A modern LLM serving engine is both:

```text
a scheduler
```

and:

```text
a memory manager
```

It must decide:

```text
which requests run now
which requests wait
which requests share a batch
where each request's KV cache lives
when to allocate new KV blocks
when to free memory
how to stream tokens back
```

The serving stack can be summarized as:

```text
User request
→ tokenization
→ routing / scheduling
→ prefill
→ initial KV cache
→ first token
→ decode loop
→ continuous batching
→ KV cache growth
→ PagedAttention / memory management
→ sampling
→ streaming
→ cleanup
```

---

## 16. Key Takeaways

1. LLM serving is the system problem of turning user requests into streamed model outputs efficiently.
    
2. Prefill processes the known prompt and creates the initial KV cache.
    
3. Decode generates one token at a time and extends the KV cache.
    
4. TTFT measures how long the user waits for the first token.
    
5. TPOT measures how fast tokens stream after generation begins.
    
6. Long prompts mostly stress prefill and TTFT.
    
7. Long outputs mostly stress decode and TPOT.
    
8. Continuous batching improves scheduling and GPU utilization.
    
9. PagedAttention improves KV-cache memory allocation.
    
10. Quantization reduces numerical precision to save memory or bandwidth.
    
11. GQA/MQA/MLA reduce KV cache pressure at the model architecture level.
    
12. Prefix caching reduces redundant prefill for repeated prompt prefixes.
    
13. Good LLM serving requires diagnosing the actual bottleneck before choosing an optimization.
    

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
    
- [[Time to First Token]]
    
- [[Time Per Output Token]]
    
- [[Continuous Batching]]
    
- [[PagedAttention]]
    
- [[Quantization]]
    
- [[KV Cache Quantization]]
    
- [[Prefix Caching]]
    
- [[Cache-Aware Routing]]
    
- [[Control Plane]]
    
- [[Data Plane]]
    
- [[Throughput]]
    
- [[Latency]]
    
- [[vLLM]]
    
- [[TensorRT-LLM]]
    

---

## Footnotes

## Footnotes

1. Gyeong-In Yu et al., “Orca: A Distributed Serving System for Transformer-Based Generative Models,” OSDI 2022. The paper introduced iteration-level scheduling and selective batching ideas for transformer serving. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-orca)
    
2. NVIDIA TensorRT-LLM documentation uses “in-flight batching” for dynamic request execution that mixes context and generation phases to improve GPU utilization. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-tensorrt)
    
3. Woosuk Kwon et al., “Efficient Memory Management for Large Language Model Serving with PagedAttention,” 2023. The paper introduced PagedAttention and the vLLM serving engine. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-vllm)
    
4. Zirui Liu et al., “KIVI: A Tuning-Free Asymmetric 2bit Quantization for KV Cache,” 2024. The paper studies KV-cache quantization and proposes asymmetric low-bit quantization for cached keys and values. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-kivi)