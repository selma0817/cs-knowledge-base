---
date: 2026-06-24
aliases:
  - KV Cache Mathematics
  - Attention Cache Math
  - MQA GQA MLA
tags:
  - ai/llm/architecture
  - ai/llm/inference
  - ai/attention
  - ai/kv-cache
status: evergreen
---
## Summary

During [[Autoregressive Decoding]], a decoder-only [[Transformer]] repeatedly generates one token at a time. Recomputing all previous [[Key]] and [[Value]] tensors at every decoding step would be wasteful, so inference engines store them in the [[KV Cache]].

The core bottleneck is simple:

> The longer the context and the larger the batch, the larger the KV cache becomes.

Standard [[Multi-Head Attention]] stores separate K/V tensors for every attention head. [[Multi-Query Attention]] and [[Grouped-Query Attention]] reduce the number of KV heads. [[Multi-Head Latent Attention]] instead compresses K/V into a lower-dimensional latent representation.

---

## 1.  KV Cache vs Attention Matrix: Linear vs Quadratic Growth

A common confusion is to think the KV cache grows like:

$$  
T^2  
$$

because attention compares every token with every other token.

But this mixes up two different objects:

1. the **KV cache**
    
2. the **attention score matrix**
    

The KV cache stores token representations. For each token, each layer, and each KV head, the model stores one key vector and one value vector.

For one layer and one head, the cache looks like:

```text
K_1, K_2, K_3, ..., K_T
V_1, V_2, V_3, ..., V_T
```

So the cache stores:

$$  
2 \times T  
$$

vectors per layer per KV head.

If each vector has dimension $d_h$, then the KV cache size per layer per KV head is:

$$  
2 \times T \times d_h  
$$

This is **linear** in sequence length $T$.

The $T^2$ term appears somewhere else: the attention score matrix.

During full self-attention, the model computes:

$$  
QK^T  
$$

If:

$$  
Q \in \mathbb{R}^{T \times d_h}  
$$

and:

$$  
K \in \mathbb{R}^{T \times d_h}  
$$

then:

$$  
QK^T \in \mathbb{R}^{T \times T}  
$$

This matrix contains pairwise query-key scores between tokens.

So:

|Object|Shape|Growth|
|---|--:|--:|
|KV cache|$T \times d_h$ for K, plus $T \times d_h$ for V|linear in $T$|
|Attention scores|$T \times T$|quadratic in $T$|

In other words:

> The KV cache stores one K vector and one V vector per token.  
> The attention matrix stores pairwise token-token comparison scores.

This is why the KV cache formula contains $T$, not $T^2$.


## 2. The KV Cache Memory Formula

For a decoder-only LLM using standard MHA/GQA/MQA-style attention, the approximate KV cache memory is:

# $$  
\text{KV Cache Bytes}=

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
|$2$|one tensor for K and one tensor for V|
|$B$|batch size|
|$T$|sequence length / context length|
|$L$|number of transformer layers|
|$H_{kv}$|number of key-value heads|
|$d_h$|dimension per head|
|$b$|bytes per element, e.g. 2 for FP16/BF16|

The important term is:

$$  
H_{kv}  
$$

because different attention variants mainly reduce KV cache size by changing how many KV heads must be stored.

---

## 3. Why KV Cache Matters During Decoding

Transformer inference has two major phases:

### Prefill

The model processes the full prompt in parallel.

Example:

```text
User prompt: "Explain KV cache in transformers."
```

The model computes K/V tensors for every prompt token and stores them.

### Decode

The model generates one new token at a time.

At each decoding step, the new query attends to all previously cached keys and values:

# $$  
\text{Attention}(Q_t, K_{\le t}, V_{\le t})

\text{softmax}  
\left(  
\frac{Q_t K_{\le t}^T}{\sqrt{d_h}}  
\right)  
V_{\le t}  
$$

Without KV caching, the model would repeatedly recompute K and V for the whole prefix. With KV caching, it only computes K/V for the newest token and appends them to the cache.

So KV cache is a speed optimization, but it becomes a memory bottleneck.

---

## 4. Standard Multi-Head Attention

In [[Multi-Head Attention]], each token produces separate queries, keys, and values for every attention head.

Let:

- $x_t \in \mathbb{R}^d$ be the hidden state for token $t$
    
- $H_q$ be the number of query heads
    
- $H_{kv}$ be the number of key-value heads
    
- In standard MHA, $H_q = H_{kv}$
    

For each head $i$:

$$  
q_t^{(i)} = x_t W_Q^{(i)}  
$$

$$  
k_t^{(i)} = x_t W_K^{(i)}  
$$

$$  
v_t^{(i)} = x_t W_V^{(i)}  
$$

In standard MHA:

$$  
H_{kv} = H_q  
$$

So if a model has 32 attention heads, it stores 32 key heads and 32 value heads per token per layer.

This gives the model high attention-head diversity, but it makes the KV cache large.

---

## 5. Multi-Query Attention

[[Multi-Query Attention]] keeps many query heads but uses only one shared key head and one shared value head.[1](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-mqa)

In MHA:

$$  
H_{kv} = H_q  
$$

In MQA:

$$  
H_{kv} = 1  
$$

So each token still has many query heads:

$$  
q_t^{(1)}, q_t^{(2)}, ..., q_t^{(H_q)}  
$$

but only one shared key and value:

$$  
k_t = x_t W_K  
$$

$$  
v_t = x_t W_V  
$$

Each query head attends to the same cached K/V tensors.

### Intuition

MHA says:

> Every query head gets its own K/V memory.

MQA says:

> Query heads can stay separate, but they all read from the same K/V memory.

### Memory effect

If $H_q = 32$, then moving from MHA to MQA changes:

$$  
H_{kv}: 32 \rightarrow 1  
$$

So the KV cache can become roughly 32× smaller for the attention cache component.

### Tradeoff

MQA improves decoding efficiency, but sharing one KV head across all query heads can reduce model quality compared with full MHA in some settings.[2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-gqa)

---

## 6. Grouped-Query Attention

[[Grouped-Query Attention]] is the compromise between MHA and MQA.[2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-gqa)

Instead of using one KV head for all query heads, GQA divides query heads into groups. Each group shares one KV head.

If:

$$  
H_q = 32  
$$

and:

$$  
H_{kv} = 8  
$$

then each KV head is shared by:

$$  
\frac{H_q}{H_{kv}} = \frac{32}{8} = 4  
$$

query heads.

### Attention variants as a spectrum

|Mechanism|Query heads|KV heads|Cache size|Expressivity|
|---|--:|--:|--:|---|
|MHA|many|many|largest|high|
|GQA|many|some|medium|near-MHA in many settings|
|MQA|many|one|smallest among head-sharing methods|may lose quality|

The key idea is:

> Tokens do not share keys and values. Attention heads share keys and values.

Each token still contributes its own K/V information to the cache. What changes is how many separate KV head projections are stored per token.

---

## 7. Multi-Head Latent Attention

[[Multi-Head Latent Attention]] was introduced in [[DeepSeek-V2]] and reused in [[DeepSeek-V3]].[3](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-deepseek-v2)[4](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-deepseek-v3)

MQA and GQA reduce KV cache by sharing K/V heads.

MLA takes a different path:

> Instead of storing full keys and values, store a compressed latent representation from which the attention computation can be recovered.

---

## 8. MLA Step A: Low-Rank Joint Compression of K and V

In standard attention, keys and values are projected separately:

$$  
k_t = x_t W_K  
$$

$$  
v_t = x_t W_V  
$$

MLA first projects the token hidden state into a smaller latent vector:

$$  
c_t^{KV} = x_t W_{DKV}  
$$

where:

- $c_t^{KV}$ is the compressed KV latent
    
- $W_{DKV}$ is a down-projection matrix
    
- the latent dimension is much smaller than the full K/V representation
    

Then the model can conceptually reconstruct content keys and values:

$$  
k_t^C = c_t^{KV} W_{UK}  
$$

$$  
v_t^C = c_t^{KV} W_{UV}  
$$

where:

- $W_{UK}$ is the key up-projection
    
- $W_{UV}$ is the value up-projection
    
- superscript $C$ means “content” component
    

### Storage win

During inference, MLA does not need to store full $k_t^C$ and $v_t^C$ for every token.

It stores:

$$  
c_t^{KV}  
$$

This is why MLA reduces KV cache: the cache stores a compressed latent vector instead of full K/V tensors.

For DeepSeek-V2 specifically, the paper reports that MLA reduces KV cache by 93.3% compared with DeepSeek 67B.[3](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-deepseek-v2)

---

## 9. MLA Step B: Decoupled RoPE

[[Rotary Position Embedding]] applies position-dependent rotations to queries and keys.[5](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-rope)

This creates a problem for MLA.

The low-rank content pathway wants to use matrix associativity to avoid explicitly reconstructing full keys and values. But RoPE inserts a position-dependent operation into the middle of the attention calculation.

Roughly:

$$  
\text{RoPE}(k_t)  
$$

depends on token position $t$.

Because RoPE is position-dependent, it prevents the key up-projection from being cleanly absorbed into other matrices during inference.

DeepSeek's solution is [[Decoupled RoPE]].

MLA separates attention into:

1. a compressed content pathway
    
2. a small positional RoPE pathway
    

The cache stores:

```text
[compressed content latent, small positional key]
```

or mathematically:

$$  
[c_t^{KV}, k_t^R]  
$$

where:

- $c_t^{KV}$ stores compressed content information
    
- $k_t^R$ stores the small RoPE positional component
    

This preserves position information without forcing the model to cache full K/V tensors.

---

## 10. MLA Step C: The Absorption Trick

At first, MLA looks like it saves memory but adds computation.

If the model stores only:

$$  
c_t^{KV}  
$$

then it seems like it must reconstruct:

$$  
k_t^C = c_t^{KV} W_{UK}  
$$

and:

$$  
v_t^C = c_t^{KV} W_{UV}  
$$

during every decoding step.

That would be expensive.

MLA avoids this using matrix associativity.

---

### 10.1 Absorbing Keys into Queries

Ignore RoPE for a moment.

The content attention score between a query token $i$ and cached token $j$ is:

$$  
q_i^C (k_j^C)^T  
$$

Substitute the compressed forms:

$$  
q_i^C = c_i^Q W_{UQ}  
$$

$$  
k_j^C = c_j^{KV} W_{UK}  
$$

Then:

# $$  
q_i^C (k_j^C)^T

(c_i^Q W_{UQ})(c_j^{KV} W_{UK})^T  
$$

Transpose the second term:

# $$

(c_i^Q W_{UQ})(W_{UK}^T (c_j^{KV})^T)  
$$

Regroup by associativity:

# $$

c_i^Q (W_{UQ} W_{UK}^T) (c_j^{KV})^T  
$$

The middle matrix can be fused:

$$  
W_{QK}^{fused} = W_{UQ} W_{UK}^T  
$$

So attention scores can be computed against the compressed latent cache without explicitly materializing full keys.

---

### 10.2 Absorbing Values into the Output Projection

The output side has a similar trick.

Normally, attention output uses values:

$$  
\text{Attn} \cdot v^C \cdot W_O  
$$

Substitute the compressed value:

$$  
v^C = c^{KV} W_{UV}  
$$

Then:

$$  
\text{Attn} \cdot (c^{KV} W_{UV}) \cdot W_O  
$$

Regroup:

$$  
\text{Attn} \cdot c^{KV} \cdot (W_{UV} W_O)  
$$

Fuse the value up-projection with the output projection:

$$  
W_{VO}^{fused} = W_{UV} W_O  
$$

So the model avoids explicitly expanding full values during inference.

---

## 11. Comparing MHA, MQA, GQA, and MLA

|Mechanism|Main idea|What is cached per token?|KV cache reduction strategy|
|---|---|---|---|
|MHA|Separate K/V for every head|Full K and V for all heads|none|
|MQA|All query heads share one K/V head|One K and one V|reduce $H_{kv}$ to 1|
|GQA|Groups of query heads share K/V heads|Several K/V heads|reduce $H_{kv}$ to an intermediate number|
|MLA|Compress K/V into latent vector|compressed latent + small RoPE key|low-rank compression|

The clean mental model:

```text
MHA: store many K/V heads
MQA: store one K/V head
GQA: store a few K/V heads
MLA: store compressed K/V latent
```

---

## 12. Why This Connects to Inference Systems

KV cache is not just an architecture detail. It directly affects [[LLM Serving]].

A larger KV cache means:

- fewer simultaneous requests fit on GPU
    
- lower maximum batch size
    
- shorter feasible context length
    
- more memory bandwidth pressure during decoding
    
- harder scheduling for [[Continuous Batching]]
    
- more need for [[PagedAttention]] or KV-cache paging
    

This is why attention architecture, cache layout, and inference engine design are connected.

[[MQA]], [[GQA]], and [[MLA]] reduce the cache at the model architecture level.

[[PagedAttention]] and [[vLLM]] manage the cache at the serving-system level.

[[Quantization]] reduces weight memory, and sometimes activation/cache memory if KV-cache quantization is used, but ordinary weight-only quantization does not directly solve the KV-cache bottleneck.

---

## 13. Key Takeaways

1. The KV cache grows linearly with batch size, sequence length, number of layers, number of KV heads, and head dimension.
    
2. Standard MHA has the largest KV cache because every query head has its own K/V head.
    
3. MQA reduces KV cache aggressively by using one shared KV head.
    
4. GQA is a middle ground: multiple query heads share each KV head.
    
5. MLA reduces KV cache by storing a compressed latent representation instead of full K/V tensors.
    
6. Decoupled RoPE is needed because ordinary RoPE interferes with the linear-algebra absorption trick.
    
7. The absorption trick uses matrix associativity to avoid explicitly decompressing full keys and values during inference.
    
8. Architecture-level cache reduction and system-level cache management are complementary.
    

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
    
- [[Rotary Position Embedding]]
    
- [[PagedAttention]]
    
- [[Continuous Batching]]
    
- [[Quantization]]
    
- [[LLM Serving]]
    

---

## Footnotes

## Footnotes

1. Noam Shazeer, “Fast Transformer Decoding: One Write-Head is All You Need,” 2019, arXiv:1911.02150. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-mqa)
    
2. Joshua Ainslie et al., “GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints,” EMNLP 2023, arXiv:2305.13245. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-gqa) [↩2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-gqa-2)
    
3. DeepSeek-AI, “DeepSeek-V2: A Strong, Economical, and Efficient Mixture-of-Experts Language Model,” 2024, arXiv:2405.04434. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-deepseek-v2) [↩2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-deepseek-v2-2)
    
4. DeepSeek-AI, “DeepSeek-V3 Technical Report,” 2024/2025, arXiv:2412.19437. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-deepseek-v3)
    
5. Jianlin Su et al., “RoFormer: Enhanced Transformer with Rotary Position Embedding,” 2021, arXiv:2104.09864. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-rope)