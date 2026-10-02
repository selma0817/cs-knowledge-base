---
date: 2026-10-01
tags:
  - llm
  - inference
  - decoding
  - sampling
  - interview
aliases:
  - decoding
  - sampling parameters
  - temperature
  - top-k
  - top-p
  - nucleus sampling
  - repetition penalty
  - greedy decoding
  - 介绍一下 top-k 和 top-p 采样
---
At every generation step, an LLM outputs one **logit per vocabulary token**. **Decoding** turns that vector into the next token: either take the most likely token (**greedy**) or **sample** from the probability distribution, after optionally reshaping it with a **repetition penalty**, **temperature**, **top-k** and **top-p**. These settings apply **per step, over the whole vocabulary**, not to the sequence as a whole.

## The pipeline at each step

```text
logits [vocab_size]
   │  repetition penalty   tokens already in the text become less likely
   │  temperature          divide every logit by T
   │  top-k                keep the k most likely tokens
   │  top-p                keep the smallest set whose probabilities sum to ≥ p
   ▼
softmax → renormalized probabilities → SAMPLE one token      (greedy: take the argmax instead)
```

(Hugging Face applies them in this order: logits processors such as the repetition penalty, then temperature, top-k, top-p.)

## Each setting, on one example

Toy vocabulary of 5 tokens with probabilities `[0.50, 0.25, 0.15, 0.07, 0.03]`:

| Setting | What it does | Neutral value | Example |
| --- | --- | --- | --- |
| **Repetition penalty r** | logits of tokens already in the text are divided by r (multiplied by r if negative) | **1.0** | r = 1.1: a used token's logit 2.0 → 1.82 |
| **Temperature T** | logits ÷ T before softmax, i.e. probabilities ∝ p^(1/T). T < 1 sharpens, T > 1 flattens, T → 0 is greedy | **1.0** | T = 0.5 → `[0.73, 0.18, 0.07, 0.01, 0.00]`; T = 2 → `[0.35, 0.25, 0.19, 0.13, 0.09]` |
| **Top-k** | keep only the k most likely tokens, renormalize | **0** (disabled) | k = 2 → `[0.67, 0.33, 0, 0, 0]` |
| **Top-p (nucleus)** | keep the smallest set of most likely tokens whose probabilities sum to ≥ p, renormalize | **1.0** (keep all) | p = 0.8: 0.50 + 0.25 = 0.75 < 0.8, + 0.15 = 0.90 ≥ 0.8 → keep 3 → `[0.56, 0.28, 0.17, 0, 0]` |

- **Top-k vs top-p:** top-k keeps a fixed *number* of tokens; top-p keeps a variable number that adapts to how confident the model is (a peaked distribution keeps few tokens, a flat one keeps many). Used together, both filters apply.
- **Min-p**, a newer alternative: keep tokens whose probability is at least `min_p × (the top token's probability)`.

## Greedy vs sampling

| | Greedy | Sampling |
| --- | --- | --- |
| Output | deterministic: the same answer every time | varies between samples |
| Use for | reproducible benchmark numbers | diversity; **RL rollouts** (GRPO needs different answers within a group) |
| Failure mode | small models can get stuck repeating themselves | at high T, rambling or incoherent text |

## Model defaults are a trap

A model's `generation_config.json` supplies any setting you don't pass. `Qwen2.5-0.5B-Instruct` ships with temperature 0.7, top-p 0.8, top-k 20 and repetition penalty 1.1 (other sizes differ). Passing only `temperature=1.0, top_p=1.0` still samples with top-k 20 and a repetition penalty. **Set every parameter explicitly** and record the values actually used.

## Why RL rollouts sample with neutral settings

> The policy-gradient math assumes rollouts are **sampled from π_old**, the same distribution whose log-probs go into the ratio ([[Policy Ratio and Clipping]]). Rollouts sampled with top-k 20 come from a *truncated* distribution, while training computes log-probs from the *full* softmax, so samples and math no longer describe the same model. With T = 1 and no truncation, both use the model's own distribution. (Libraries that roll out at another temperature, such as TRL, divide the logits by that temperature when computing training log-probs too.)

Top-k also makes rare tokens **impossible** to sample, an extreme version of the exploration problem that DAPO's Clip-Higher addresses ([[DAPO]]).

## Batched generation mechanics

- **Left padding.** Generation appends each new token at the end of every row in lockstep, so every prompt must end in the same column: `[pad pad Q Q Q]`, not `[Q Q Q pad pad]`. With right padding, the next token would be predicted after a pad. (For *scoring* fixed sequences, as in training, right padding is fine.)
- **New tokens** are `output_ids[:, prompt_length:]`, where `prompt_length` is the padded length: the same cut works for every row.
- **Several samples per prompt** (`num_return_sequences = n`) are laid out consecutively: rows `i·n … i·n + n − 1` belong to prompt `i` (counting from 0). With 3 prompts and n = 4, prompt index 2 is rows 8–11.
- **Stopping:** a completion ends at the first end-of-sequence token; finished rows are filled with the pad token. A completion that uses all `max_new_tokens` without one is **truncated**.

## Common misconceptions

- **"Top-p is a probability over the whole sequence."** No. It applies at each step, over the vocabulary.
- **"`top_p=1.0` and `temperature=1.0` mean plain sampling."** Only if top-k, repetition penalty and every other setting are neutral too. Unset parameters come from the model's defaults.
- **"Greedy gives the best answer."** It gives the single most likely continuation step by step, which isn't always the best full answer, and small models can loop.
- **"Pad on the right, as in training batches."** Not for generation. Prompts must be left-padded.
- **"Temperature 0 is just a very low temperature."** It would divide by zero. It means greedy: vLLM treats it as argmax, while Hugging Face rejects `temperature=0` when `do_sample=True` (use `do_sample=False`).

## Interview answer to "介绍一下 top-k 和 top-p 采样"

**中文 (30 秒):** 模型每一步输出整个词表上的 logits。贪心解码每步取概率最大的 token；采样则从概率分布中随机抽取，可以先调整分布：temperature 把 logits 除以 T，T 小于 1 分布更尖锐，大于 1 更平坦；top-k 只保留概率最高的 k 个 token；top-p（nucleus）保留累计概率达到 p 的最小 token 集合，个数随模型置信度变化；之后重新归一化再采样。repetition penalty 降低已出现 token 的概率。注意这些都是每一步、在词表上做的。做 RL rollout 时一般用 T=1、不截断，因为训练里的 log-prob 是按完整分布算的，采样分布必须和它一致。

**English:** At each step the model outputs logits over the vocabulary. Greedy takes the argmax; sampling draws from the distribution after optional reshaping: temperature divides the logits (below 1 sharpens, above 1 flattens), top-k keeps the k most likely tokens, top-p keeps the smallest set whose probabilities reach p (so its size adapts to the model's confidence), then the result is renormalized. A repetition penalty lowers tokens already used. All of this is per step, over the vocabulary. RL rollouts use T = 1 with no truncation, because training computes log-probs from the full distribution and the samples must come from that same distribution.

## Interview summary

> Decoding converts each step's vocabulary logits into a token. Greedy takes the argmax (reproducible, can loop); sampling draws from the softmax after a repetition penalty (divide used tokens' logits by r), temperature (logits ÷ T), top-k (keep k most likely) and top-p (keep the smallest set reaching cumulative probability p), each followed by renormalization, all applied per step over the vocabulary. Model `generation_config.json` defaults fill in unset parameters (Qwen2.5-0.5B-Instruct: T 0.7, top-p 0.8, top-k 20, repetition penalty 1.1), so set everything explicitly. RL rollouts should sample at T = 1 without truncation so that samples come from the same distribution whose log-probs are used in training; top-k would also make rare tokens unsampleable. Batched generation needs left padding, slices new tokens at the padded prompt length, and lays out n samples per prompt in consecutive rows.

## Related notes

- [[LLM Serving]]
- [[Continuous Batching and PagedAttention]]
- [[Policy Ratio and Clipping]]
- [[GRPO]]
- [[Rule-Based and Verifiable Rewards]]
- [[LLM Training MOC]]
