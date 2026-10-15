---
date: 2026-10-06
tags:
  - llm
  - post-training
  - fine-tuning
  - memory
  - activations
  - systems
  - interview
aliases:
  - gradient checkpointing
  - activation checkpointing
  - activation recomputation
  - recompute
  - checkpointing
---
**Gradient (activation) checkpointing** trades compute for memory: during the forward pass it stores only a subset of activations, and during the backward pass it **re-runs** the forward for each segment to regenerate the activations it dropped. It attacks **activation memory**, the bucket [[LoRA and QLoRA|LoRA]] does *not* touch.

## Why activations must be kept at all

Backprop needs each layer's **input activation** to compute its gradient. For a linear layer `y = Wx`:

```
dL/dW = dL/dy · xᵀ      ← needs x, the input activation
dL/dx = Wᵀ · dL/dy      ← propagates gradient to the previous layer
```

So the forward pass's activations must survive until the backward pass consumes them. Keeping *all* of them is what makes activation memory grow with **batch × sequence length × layers** — often the dominant training cost for deep models or long sequences.

## The core trick

Store only a few activations (**checkpoints**); drop the rest. In the backward pass, when a dropped activation is needed, **recompute it** by re-running the forward from the nearest stored checkpoint, then differentiate. The fundamental resource traded away is **compute** (extra forward work) to buy back **memory**.

> "Gradient checkpointing" does **not** checkpoint gradients. It checkpoints (saves) a *subset of activations* and recomputes the rest. Clearer names: **activation checkpointing** / **activation recomputation**.

## The tradeoff, quantified

A training step is **1 forward + 1 backward**, and backward ≈ **2× forward FLOPs**, so a step ≈ **3 forward-units**. Checkpointing adds **~1 extra forward-unit** (the recomputation) → ~4 units → **≈ 30% slower**. The key fact: **recompute ≈ one extra forward pass.**

Two regimes:

- **√N checkpointing** (Chen et al. 2016, theoretical optimum): checkpoint every √N layers → **O(√N)** activation memory with one extra forward pass.
- **Per-layer / per-block checkpointing** (what frameworks actually do, e.g. HF `model.gradient_checkpointing_enable()`): checkpoint each transformer block's **input**, and recompute everything *inside* the block during backward. The practical win is dropping the large **intra-block** activations (attention matrices, softmax, MLP hidden) and keeping only block boundaries.

```
Normal:          store every activation            O(all)      step ≈ 3 forward-units
Checkpointing:   store block inputs only,          O(boundaries)  step ≈ 4 forward-units
                 recompute block internals in bwd               (~30% slower)
```

## Correctness: preserve the RNG state

If a checkpointed block has **dropout** (or any randomness), the recomputed forward would draw a **different mask** → different activations → **wrong gradients**. The fix is **not** a fixed seed (that would make every step identical); the framework **snapshots the RNG state** (CPU + CUDA) at the first forward and **restores** it before recomputation, so the same dropout mask is redrawn. In PyTorch: `torch.utils.checkpoint(fn, *args, preserve_rng_state=True)` (default).

## Framework mechanics

- `torch.utils.checkpoint.checkpoint` / `checkpoint_sequential` wrap a module so its forward does not retain intermediate activations; it re-runs forward during backward.
- HF: `model.gradient_checkpointing_enable()`.
- Prefer **`use_reentrant=False`** in recent PyTorch — the old reentrant implementation has gotchas (requires inputs to require grad, awkward with some graph structures).
- **Selective activation recomputation** (Megatron / FSDP): recompute only the cheap-to-recompute, memory-heavy ops (e.g. attention) and *keep* the rest — a finer tradeoff than all-or-nothing.

## Where it fits among memory techniques

| Memory bucket | Reduced by | Not reduced by |
| --- | --- | --- |
| Gradients + optimizer state (Adam's 2 fp32/param) | [[LoRA and QLoRA\|LoRA]] | checkpointing |
| **Activations** (batch × seq × layers; logits are the giant) | **activation checkpointing** + micro-batching | LoRA |
| Frozen weights | QLoRA (4-bit NF4), see [[Quantization]] | LoRA, checkpointing |

So checkpointing is **orthogonal and complementary** to LoRA — different buckets. Training RL on a small GPU often needs all of: LoRA (optimizer), checkpointing + micro-batching (activations), QLoRA (weights). Micro-batching also cuts activation memory (only one micro-batch's activations alive at once) along a different axis, and the two stack.

**RL context:** the dominant activation in LLM RL is the logits `[batch, tokens, vocab]`. Checkpointing re-runs block forwards during the policy-gradient backward; it stacks with the trick of gathering each token's log-prob immediately (`logit[token] − logsumexp`) rather than keeping full logits — both are activation-memory tactics. See [[Policy Gradient for LLMs]] and [[LoRA and QLoRA]].

## When not to use it

If activation memory is **not** the bottleneck (short sequences, small batch, and the optimizer/weights are what overflow), the ~30% time cost buys nothing — reach for LoRA/QLoRA or micro-batching instead. Checkpointing is the lever specifically for **activation-bound** training (long context, deep models, large batch).

## Interview summary

> Backprop needs each layer's input activation (e.g. dL/dW = dL/dy·xᵀ), so the forward pass's activations are normally all kept, making activation memory scale with batch × sequence × layers. Gradient (activation) checkpointing stores only a subset — typically each transformer block's input — and recomputes the dropped intra-block activations by re-running the forward during backward: ~one extra forward pass, about 30% slower, for a large drop in activation memory (O(√N) with √N-spacing in theory; per-block in practice). The name is a misnomer — it checkpoints activations, not gradients. Dropout correctness is handled by snapshotting and restoring the RNG state, not a fixed seed. It is orthogonal to LoRA (which cuts gradient/optimizer memory, not activations) and to QLoRA (frozen weights), so large-model/long-context training on limited GPUs combines all of them; skip it when training isn't activation-bound.

## Related notes

- [[LoRA and QLoRA]]
- [[Quantization]]
- [[Policy Gradient for LLMs]]
- [[LLM Training MOC]]
- [[Attention Mechanisms and KV Cache Mathematics]]
