---
date: 2026-10-02
tags:
  - llm
  - post-training
  - fine-tuning
  - lora
  - peft
  - memory
  - interview
aliases:
  - LoRA
  - QLoRA
  - low-rank adaptation
  - PEFT
  - 参数高效微调
  - LoRA 原理
  - training memory
---
**LoRA (Low-Rank Adaptation)** fine-tunes a model by freezing its weights W and learning a small low-rank correction ΔW = B·A for selected linear layers, so only a few percent of the parameters are trained. **QLoRA** additionally stores the frozen W in 4-bit. LoRA shrinks **gradient and optimizer memory**, not activation memory.

## Rank in one paragraph

The **rank** of a matrix is the number of independent columns, equivalently the dimension of the subspace its outputs live in. A rank-16 matrix of size 896 × 896 maps every input into a 16-dimensional subspace, and can always be written as the product of an 896 × 16 and a 16 × 896 matrix. "Low rank" and "product of two thin matrices" are the same thing.

## The mechanism

```text
W' = W + (α/r) · B · A          W: d_out × d_in, frozen
                                B: d_out × r,    trained, starts at 0
                                A: r × d_in,     trained, starts random

forward:  h = W·x + (α/r) · B · (A · x)        frozen path + small side branch
```

- Each targeted linear layer gets its own A, B pair (all 7 projections in 24 layers = 168 adapters in Qwen2.5-0.5B).
- **α/r scaling** keeps the size of the update roughly independent of the rank chosen, so the best learning rate doesn't depend much on r.
- **Backward pass:** gradients still flow *through* every frozen W to reach earlier adapters, so compute is not much lower. What's saved is storing gradients and optimizer state for 494M parameters.
- **Merging:** after training, W + (α/r)·B·A can be folded into one matrix (`merge_and_unload` in PEFT): no extra cost at inference.

## Counting parameters (Qwen2.5-0.5B, hidden size 896, 24 layers)

```text
per layer      attention:  q 896×896 (803K)  k 896×128 (115K)  v 896×128 (115K)  o 896×896 (803K)  → 1.8M
               MLP:        gate 896×4864 (4.36M)  up 896×4864 (4.36M)  down 4864×896 (4.36M) → 13.1M
LoRA r = 16 on one 896×896 matrix:   16 × (896 + 896) = 28,672 vs 802,816 (3.6%)
LoRA r = 16 on all 7, all 24 layers: ≈ 8.8M trainable ≈ 1.8% of 494M
```

## Why B = 0 and A random

Write u = A·x and let g be the gradient arriving at the layer's output:

```text
∂L/∂B = g · uᵀ = g · (A·x)ᵀ      → needs A ≠ 0
∂L/∂A = Bᵀ · g · xᵀ              → is 0 while B = 0
```

- **B = 0 ⇒ ΔW = 0:** training starts exactly at the pretrained model (for RL: π_θ = π_ref at step 0, KL = 0).
- **A random:** otherwise B's gradient is 0, A's too, and both stay at zero forever.
- The first step updates B; once B ≠ 0, A gets gradients as well.

## Design choices for RL fine-tuning

| Choice | Recommendation | Why |
| --- | --- | --- |
| Target modules | all linear layers (`q k v o gate up down`) | the MLP holds ~88% of each layer's weights; attention-only LoRA underperforms even at matched parameter count |
| Rank | small (8–32 is plenty) | a 0/1 reward carries ≤ 1 bit per answer, so RL has little to store; LoRA matched full fine-tuning on math RL even at rank 1 |
| Learning rate | ~10× the full-fine-tuning rate | consistent across SFT and RL (e.g. 1e-5 for LoRA vs ~1e-6 full) |
| Dropout | **0** | dropout changes the forward pass between scoring `logp_old` and `logp_new`, making ρ noisy (exception: the very first step, where B = 0 so the adapter outputs 0 for any mask) |
| Reference model | the same model with the adapter **disabled** (`with model.disable_adapter():`) | the base weights never change, so π_ref costs one forward pass and no extra memory, vs a second copy (1 GB at 0.5B, 14 GB at 7B) |

## Make sure only the adapter trains

If a bug leaves the base weights trainable (`requires_grad=True`), training still runs, but:
- **memory** grows by gradients + Adam state for every parameter (~5 GB extra at 0.5B), likely running out on a 12 GB GPU;
- **the reference model breaks:** disabling the adapter now returns the *updated* base, so KL measures only the adapter's share of the drift and under-reports it;
- **checkpoints lose training:** `save_pretrained` on a PEFT model saves only the adapter, so base-weight changes are silently discarded and the saved model isn't the one you trained.

Catch it before any GPU time with a CPU test on a tiny model: copy the base weights, run one training step, and assert they are bit-identical (`torch.equal`) while some LoRA weights changed; and assert every trainable parameter name contains `lora_`. (Passing all parameters to the optimizer is harmless only if the base weights have `requires_grad=False`: parameters without gradients are skipped.)

## QLoRA

- The frozen base weights are stored in **4-bit NF4** ("NormalFloat4", a format designed for bell-curve-distributed weights), with the quantization constants themselves quantized ("double quantization").
- During each matrix multiplication the 4-bit weights are **converted back to bf16** on the fly; A and B stay in bf16/fp32 and are trained normally.
- **Use it when the bf16 model doesn't fit** (a 7B model is ~14 GB in bf16, more than a 12 GB GPU). Costs: slower matrix multiplications and quantization noise in log-probs (which then shows up in ρ and KL). See [[Quantization]].

## Where training memory goes

| Item | Full fine-tuning, 0.5B | LoRA (≈ 9M trainable) | Shrunk by |
| --- | --- | --- | --- |
| Weights | 1 GB bf16 (+ 2 GB fp32 master copy in mixed precision) | 1 GB frozen bf16 + ~35 MB adapters | QLoRA (4-bit) |
| Gradients | 1 GB | ~35 MB | LoRA |
| Adam state (2 fp32 values per trained param) | 4 GB | ~72 MB | LoRA |
| **Activations** (incl. logits) | grows with batch × sequence length × layers | **same** | micro-batching, gradient checkpointing |
| KV cache (generation) | grows with sequences × length | same | shorter budgets, paged attention |

**Logits are often the largest single activation.** Shape `[batch, tokens, vocab]` with Qwen's vocabulary of 151,936: one micro-batch of 8 × 800 tokens is 972M numbers ≈ 1.9 GB in bf16, 3.9 GB in fp32, i.e. 25–55× the LoRA optimizer state. Keep only the log-prob of the actual token (`logit[token] − logsumexp(logits)`), one micro-batch at a time: `[8, 800]` = 26 KB.

- **Micro-batching (gradient accumulation):** process a mini-batch in pieces, add up gradients, one optimizer step; only one piece's activations are alive at a time.
- **Gradient checkpointing:** the forward pass keeps only each layer's *input*; the backward pass re-runs each layer's forward pass before differentiating it. Trades about one extra forward pass (~30% more time) for much less activation memory.

## Common misconceptions

- **"LoRA reduces activation memory."** No. Activations depend on batch × length × layers, not on trainable parameters.
- **"LoRA makes the backward pass much cheaper."** Not much: gradients still flow through every frozen layer. It saves *storing* gradients and optimizer state.
- **"Initialize both A and B to zero."** Then both gradients are zero forever.
- **"Higher rank is always better."** Not for RL: the reward carries too little information to need it.
- **"Use the full-fine-tuning learning rate."** LoRA's optimum is about 10× higher.
- **"QLoRA quantizes the adapters."** No. Only the frozen base weights; A and B are trained in bf16/fp32.
- **"A reference model needs a second copy."** Not with LoRA: disable the adapter.

## Interview answer to "LoRA 原理 / 为什么 LoRA 省显存"

**中文 (30 秒):** LoRA 冻结原始权重 W，对选定的线性层学习一个低秩增量 ΔW = B·A，前向是 W·x 加上 (α/r)·B·A·x，只训练 A 和 B，参数量通常只有百分之一到几。B 初始化为 0、A 随机，所以训练从原模型开始，又能让梯度流动。省显存是因为梯度和 Adam 状态只需要为少量参数存储；但冻结权重仍要加载，激活值也不会减少，激活要靠 micro-batch 和梯度检查点来省。QLoRA 再把冻结权重量化成 4-bit NF4，计算时临时反量化。做 RL 时，LoRA 用很小的秩就够（每个回答的奖励只有不到 1 bit 信息），学习率约为全量微调的 10 倍，dropout 设为 0，参考模型直接关掉 adapter 得到，不需要第二份权重。

**English:** LoRA freezes W and learns a low-rank update ΔW = B·A for selected linear layers, computing W·x + (α/r)·B·A·x and training only A and B (a few percent of the parameters). B starts at zero and A random, so training starts from the original model while gradients still flow. It saves memory because gradients and Adam state are kept only for the adapter; the frozen weights still have to be loaded, and activations are unchanged (micro-batching and gradient checkpointing address those). QLoRA additionally stores the frozen weights in 4-bit NF4. For RL: a small rank is enough (≤ 1 bit of reward per answer), the learning rate is about 10× full fine-tuning, dropout should be 0, and the reference model is the base with the adapter disabled.

## Interview summary

> LoRA freezes the pretrained weights and learns, for chosen linear layers, a low-rank update ΔW = (α/r)·B·A (B: d_out × r, A: r × d_in), training ~1–4% of the parameters; B = 0 and A random so training starts at the base model yet B receives gradient. It cuts gradient and optimizer memory (Adam's two fp32 states per trained parameter), not the frozen weights and not activations; logits ([batch, tokens, 151,936] for Qwen) are often the largest activation, handled by gathering each token's log-prob immediately, micro-batching and gradient checkpointing. QLoRA stores the frozen base in 4-bit NF4 and dequantizes on the fly. For RL, apply LoRA to all layers (MLP matters most), use a small rank (RL carries ≤ 1 bit per answer; rank 1 matched full fine-tuning on math RL), a ~10× higher learning rate, dropout 0 (otherwise ρ is noisy), and get the reference model by disabling the adapter.

## Related notes

- [[Quantization]]
- [[KL Regularization and Reference Models]]
- [[Policy Ratio and Clipping]]
- [[GRPO]]
- [[Attention Mechanisms and KV Cache Mathematics]]
- [[LLM Training MOC]]
