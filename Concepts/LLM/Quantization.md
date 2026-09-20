---
date: 2026-06-25
aliases:
  - LLM Quantization
  - Weight Quantization
  - Activation Quantization
  - KV Cache Quantization
  - Low-Precision Inference
tags:
  - ai/llm/inference
  - ai/llm/serving
  - ai/quantization
  - ai/systems
  - ai/kv-cache
status: evergreen
---
## Summary

[[Quantization]] means representing numerical tensors with fewer bits.

In [[LLM Serving]], quantization is used to reduce memory footprint and sometimes improve inference speed. But quantization is not a single technique. Different tensors can be quantized:

```text
weights
activations
KV cache
optimizer states
```

For inference, the most important categories are:

```text
weight quantization
activation quantization
KV-cache quantization
```

The key rule:

> Quantize the tensor that is causing the bottleneck.

If model weights are too large, use [[Weight Quantization]].  
If long-context serving runs out of memory because of [[KV Cache]], use [[KV Cache Quantization]], [[Grouped-Query Attention]], [[Multi-Query Attention]], [[Multi-Head Latent Attention]], or [[PagedAttention]].  
If computation is bandwidth- or kernel-limited, activation/weight quantization may help if the hardware can exploit low-precision kernels.

Quantization is a tradeoff, not a free lunch.

---

## 1. What Quantization Means

A model tensor is a collection of numbers.

In normal training or inference, these numbers may be represented in formats like:

|Format|Approximate bits per number|Approximate bytes per number|
|---|--:|--:|
|FP32|32 bits|4 bytes|
|FP16 / BF16|16 bits|2 bytes|
|FP8|8 bits|1 byte|
|INT8|8 bits|1 byte|
|INT4|4 bits|0.5 byte|

Quantization stores or computes with fewer bits.

For example, moving from FP16 to INT4 changes:

```text
FP16: 16 bits per number
INT4: 4 bits per number
```

So the raw tensor storage can become roughly:

$$  
\frac{16}{4} = 4  
$$

times smaller.

This is why a 4-bit model can be much easier to fit into GPU memory.

---

## 2. Basic Quantization Formula

A simple affine quantization scheme maps a floating-point value $x$ to an integer $q$:

$$  
q = \text{round}\left(\frac{x}{s}\right) + z  
$$

where:

|Symbol|Meaning|
|---|---|
|$x$|original floating-point value|
|$q$|quantized integer value|
|$s$|scale|
|$z$|zero-point|

To recover an approximate floating-point value:

$$  
\hat{x} = s(q - z)  
$$

The recovered value $\hat{x}$ is not exactly equal to $x$.

That difference is the quantization error:

$$  
\epsilon = x - \hat{x}  
$$

Quantization is useful when the memory/speed benefit is worth the numerical error.

---

## 3. Weight Quantization

[[Weight Quantization]] stores model parameters using fewer bits.

Examples of quantized model weights include:

```text
FP16 weights
INT8 weights
INT4 weights
```

A 70B parameter model stored in FP16 needs roughly:

# $$  
70 \times 10^9 \times 2 \text{ bytes}

140 \text{ GB}  
$$

If stored in 4-bit precision, the raw weight storage becomes roughly:

# $$  
70 \times 10^9 \times 0.5 \text{ bytes}

35 \text{ GB}  
$$

ignoring metadata such as scales and zero-points.

So weight quantization answers the question:

> Can I fit the model weights into GPU memory?

Weight-only quantization is common because weights are fixed after training. Since they do not change from request to request, they can be calibrated and compressed offline.

Methods such as [[GPTQ]] and [[AWQ]] are examples of post-training weight quantization methods for LLMs.[1](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-gptq)[2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-awq)

---

## 4. Why Weight Quantization Does Not Automatically Solve KV Cache Bottlenecks

During inference, GPU memory does not only store model weights.

It also stores:

```text
model weights
KV cache
temporary activations
workspace buffers
runtime overhead
```

The [[KV Cache]] grows with active batch size and context length:

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
|$b$|bytes per KV-cache element|

Weight quantization reduces weight memory.

It does not directly change:

$$  
B  
$$

$$  
T  
$$

$$  
L  
$$

$$  
H_{kv}  
$$

$$  
d_h  
$$

or the precision of the KV cache unless KV cache itself is quantized.

So a model can have 4-bit weights and still run out of memory during long-context serving.

Example:

```text
GPU VRAM: 48 GB
4-bit weights: 35 GB
remaining VRAM: 13 GB
KV cache needed: 20 GB
```

Total memory needed:

$$  
35 + 20 = 55 \text{ GB}  
$$

The model still fails to fit at runtime.

The problem is not the weights anymore. The problem is the runtime state.

---

## 5. KV-Cache Quantization

[[KV Cache Quantization]] stores cached keys and values using fewer bits.

This directly reduces the $b$ term in the KV-cache formula:

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

If the KV cache moves from FP16 to INT8:

```text
FP16: 2 bytes per element
INT8: 1 byte per element
```

then the KV-cache memory is roughly halved.

This matters most for:

```text
long contexts
many concurrent users
large active batches
long generations
```

because the KV cache grows with:

$$  
B \times T  
$$

KV-cache quantization answers the question:

> Can I serve many long-context requests without KV cache dominating VRAM?

Methods such as [[KIVI]] specifically target KV-cache quantization.[3](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-kivi)

---

## 6. Why KV-Cache Quantization Is Tricky

KV cache is not just stored once and ignored.

During [[Autoregressive Decoding]], each new token attends over previous cached K/V:

$$  
q_t K_{\leq t}^T  
$$

then uses the attention weights to combine cached values:

$$  
\text{softmax}\left(q_t K_{\leq t}^T\right)V_{\leq t}  
$$

If K/V are quantized poorly, their numerical error affects future attention computations.

This matters because cached K/V are reused repeatedly across decoding steps.

So KV-cache quantization can save memory, but it may affect quality or stability.

The more a tensor is reused, the more careful we need to be about its quantization error.

---

## 7. Activation Quantization

[[Activation Quantization]] quantizes intermediate tensors produced during the forward pass.

Activations are harder to quantize than weights because they depend on the input prompt.

Weights are fixed:

```text
same model weights for every request
```

Activations are dynamic:

```text
prompt A → activation distribution A
prompt B → activation distribution B
```

This means activations may have outliers or changing ranges.

Activation quantization answers the question:

> Can I reduce memory bandwidth and accelerate computation during the forward pass?

Methods such as [[SmoothQuant]] target weight-and-activation quantization, often described as W8A8 quantization.[4](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-smoothquant)

---

## 8. Weight-Only vs Weight+Activation vs KV-Cache Quantization

Different quantization strategies target different bottlenecks.

|Strategy|What is quantized?|Main benefit|Main risk|
|---|---|---|---|
|Weight-only quantization|weights|reduce model memory|may not help KV-cache bottleneck|
|Weight + activation quantization|weights and activations|reduce compute/memory bandwidth|activation outliers; harder calibration|
|KV-cache quantization|cached K/V|reduce long-context serving memory|attention quality/stability risk|
|Weight + activation + KV-cache quantization|all major inference tensors|maximum memory reduction|most complex/stability-sensitive|

Clean mental model:

```text
Weight quantization:
  helps fit the model.

KV-cache quantization:
  helps serve long contexts and many users.

Activation quantization:
  helps reduce compute/memory bandwidth during forward passes.
```

---

## 9. Quantization and Speed

Quantization reliably reduces memory footprint.

It does **not** guarantee proportional speedup.

For example, a 4-bit weight model is not automatically 4× faster than an FP16 model.

Why?

The model still has:

```text
same layers
same attention blocks
same FFN blocks
same high-level matrix multiplications
same autoregressive decoding loop
```

Quantization may improve speed if:

```text
the bottleneck is memory bandwidth
the lower-precision format reduces data movement
the hardware has fast low-precision kernels
the inference engine uses those kernels efficiently
```

But speedup may be limited if:

```text
dequantization adds overhead
the GPU lacks efficient kernels for the chosen format
KV cache or sampling is the real bottleneck
batching/scheduling is poor
CPU/runtime overhead dominates
```

A common runtime pattern is:

```text
store weights in INT4
load compressed weights
dequantize or rescale them
multiply with FP16/BF16 activations
produce FP16/BF16 outputs
```

This saves memory, but dequantization can reduce the speed benefit.

Key distinction:

```text
Quantized storage is not always the same as fully quantized computation.
```

---

## 10. Quantization Is Bottleneck-Specific

The right quantization strategy depends on what is limiting the system.

|Bottleneck|More direct fix|
|---|---|
|weights too large to fit|weight quantization|
|KV cache too large|KV-cache quantization, [[GQA]], [[MQA]], [[MLA]]|
|KV cache fragmented/wasted|[[PagedAttention]]|
|GPU underutilized due to variable request lengths|[[Continuous Batching]]|
|memory bandwidth limited by K/V reads|KV-cache quantization, GQA/MQA/MLA|
|compute-bound matrix multiplication|low-precision compute kernels|
|quality loss from quantization|better calibration, mixed precision, QAT|

Simple rule:

> Quantize the thing that is causing the bottleneck.

---

## 11. Model Comparison Examples

### Example 1: 4-bit weights are not enough

```text
Model:
  4-bit weights
  FP16 KV cache

Workload:
  long-context
  high-concurrency
```

The model weights may fit, but the server can still run out of VRAM because the FP16 KV cache dominates runtime memory.

More direct solutions:

```text
KV-cache quantization
GQA/MQA/MLA
PagedAttention
smaller active batch
shorter context
```

---

### Example 2: MHA + 4-bit weights vs GQA + 8-bit weights

```text
Model A:
  MHA attention
  4-bit weights
  FP16 KV cache

Model B:
  GQA attention
  8-bit weights
  FP16 KV cache
```

For short-context, low-concurrency inference, Model A may use less VRAM because its weights are smaller.

For long-context, high-concurrency inference, Model B may use less total runtime VRAM because [[Grouped-Query Attention]] reduces the $H_{kv}$ term in the KV-cache formula.

So:

```text
short context → weight memory may dominate
long context → KV cache may dominate
```

---

### Example 3: 4-bit weights vs INT8 KV cache

```text
Model C:
  4-bit weights
  FP16 KV cache

Model D:
  8-bit weights
  INT8 KV cache
```

For long-context, high-concurrency serving, Model D may use less total VRAM because INT8 KV cache directly reduces the runtime memory that grows with:

$$  
B \times T  
$$

Model C saves more on weights, but Model D saves more on the cache.

---

## 12. Post-Training Quantization vs Quantization-Aware Training

There are two broad ways to make a model work at low precision.

### Post-Training Quantization

[[Post-Training Quantization]] compresses a trained model after training.

Advantages:

```text
no full retraining required
easier to apply to existing models
cheaper operationally
```

Risks:

```text
quality degradation
sensitivity to calibration data
harder for very low precision
```

GPTQ, AWQ, and SmoothQuant are examples of post-training quantization approaches.[1](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-gptq)[2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-awq)[4](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fn-smoothquant)

### Quantization-Aware Training

[[Quantization-Aware Training]] trains or fine-tunes the model while simulating or using low-precision behavior.

Advantages:

```text
model can adapt to quantization noise
often better quality at low precision
```

Risks:

```text
requires training or fine-tuning
more expensive
more complex
```

Clean distinction:

```text
PTQ:
  quantize after training

QAT:
  train/fine-tune with quantization in mind
```

---

## 13. Quantization Is Not Always a Pure Win

Quantization can reduce memory and sometimes speed up inference, but it can also introduce problems.

Main risks:

```text
loss of numerical precision
degraded model quality
worse long-context attention if K/V are poorly quantized
dequantization overhead
hardware/kernel mismatch
calibration sensitivity
```

A precise statement:

> Quantization reduces the number of bits used to represent tensors. It can lower memory footprint and sometimes improve speed. But it can also introduce numerical error, degrade quality, add dequantization overhead, and fail to improve speed if another bottleneck dominates.

---

## 14. Relationship to Other Serving Concepts

Quantization is one tool in the larger [[LLM Serving]] toolbox.

|Concept|What it solves|
|---|---|
|[[Weight Quantization]]|model weights too large|
|[[KV Cache Quantization]]|long-context runtime memory|
|[[Activation Quantization]]|compute/memory bandwidth|
|[[Grouped-Query Attention]]|per-token KV-cache size|
|[[Multi-Query Attention]]|per-token KV-cache size|
|[[Multi-Head Latent Attention]]|compressed KV representation|
|[[Continuous Batching]]|poor GPU utilization from variable-length requests|
|[[PagedAttention]]|KV-cache fragmentation and over-allocation|

Important distinction:

```text
Quantization:
  changes numerical representation

GQA/MQA/MLA:
  change model architecture

Continuous batching:
  changes request scheduling

PagedAttention:
  changes KV-cache memory allocation
```

---

## 15. Key Takeaways

1. Quantization means representing tensors with fewer bits.
    
2. Weight quantization reduces model parameter memory.
    
3. KV-cache quantization reduces runtime memory for long-context and high-concurrency serving.
    
4. Activation quantization targets temporary computation tensors and memory bandwidth.
    
5. Weight-only quantization does not directly solve a KV-cache bottleneck.
    
6. KV-cache quantization directly reduces the bytes-per-element term in the KV-cache formula.
    
7. Quantization can speed up inference, but only if the hardware, kernels, and bottleneck align.
    
8. Quantized storage does not always mean fully quantized computation.
    
9. More aggressive quantization can hurt model quality or stability.
    
10. The right rule is: quantize the bottleneck.
    

---

## Related Concepts

- [[Transformer]]
    
- [[Self-Attention]]
    
- [[Multi-Head Attention]]
    
- [[Grouped-Query Attention]]
    
- [[Multi-Query Attention]]
    
- [[Multi-Head Latent Attention]]
    
- [[KV Cache]]
    
- [[KV Cache Quantization]]
    
- [[Autoregressive Decoding]]
    
- [[Continuous Batching]]
    
- [[PagedAttention]]
    
- [[LLM Serving]]
    
- [[Post-Training Quantization]]
    
- [[Quantization-Aware Training]]
    
- [[GPTQ]]
    
- [[AWQ]]
    
- [[SmoothQuant]]
    
- [[KIVI]]
    

---

## Footnotes

## Footnotes

1. Elias Frantar et al., “GPTQ: Accurate Post-Training Quantization for Generative Pre-trained Transformers,” arXiv:2210.17323, 2022. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-gptq) [↩2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-gptq-2)
    
2. Ji Lin et al., “AWQ: Activation-aware Weight Quantization for LLM Compression and Acceleration,” arXiv:2306.00978, 2023. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-awq) [↩2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-awq-2)
    
3. Zirui Liu et al., “KIVI: A Tuning-Free Asymmetric 2bit Quantization for KV Cache,” arXiv:2402.02750, 2024. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-kivi)
    
4. Guangxuan Xiao et al., “SmoothQuant: Accurate and Efficient Post-Training Quantization for Large Language Models,” arXiv:2211.10438, 2022. [↩](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-smoothquant) [↩2](https://chatgpt.com/g/g-p-6a3c6f2c6af0819186762a3caba06daf-knowledge-graph-building/c/6a3c6f2e-23fc-83ea-b1b8-599b4e00861a#user-content-fnref-smoothquant-2)