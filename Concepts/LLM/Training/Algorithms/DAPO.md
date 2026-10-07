---
date: 2026-10-07
tags:
  - llm
  - post-training
  - reinforcement-learning
  - dapo
  - grpo
  - interview
aliases:
  - Decoupled Clip and Dynamic Sampling Policy Optimization
  - DAPO vs GRPO
  - Clip-Higher
  - Dynamic Sampling
  - Token-level loss
  - Overlong Reward Shaping
---
**DAPO (Decoupled Clip and Dynamic sAmpling Policy Optimization)** is [[GRPO]] with four fixes, each for a failure that shows up in long-reasoning RL: **Clip-Higher**, **Dynamic Sampling**, **Token-level Loss** and **Overlong Reward Shaping**. It also drops the KL penalty and uses a plain correctness reward (±1). It comes from ByteDance Seed and Tsinghua AIR (arXiv 2503.14476, 2025): Qwen2.5-32B base reached 50 on AIME 2024, beating DeepSeek-R1-Zero-Qwen-32B's 47 with half the training steps.

## What DAPO changes from GRPO

| Technique | GRPO failure | Fix | In our code |
| --- | --- | --- | --- |
| Clip-Higher | the upper clip mainly limits rare tokens, so entropy collapses | ε_high 0.2 → 0.28; ε_low stays 0.2 | `--preset clip_higher` |
| Dynamic Sampling | all-correct and all-wrong groups give Â = 0, and there are more of them as the model improves | generate extra groups, keep only informative ones until the batch is full | to build |
| Token-level Loss | averaging within each answer gives long answers, good and bad, less weight per token | average over every token in the batch | `--preset token_level` |
| Overlong Reward Shaping | a truncated answer scores 0 like a wrong one, punishing sound reasoning | drop truncated answers from the loss, or a gradual length penalty | to build |
| No KL | the reasoning policy is supposed to move far from the start | β = 0 | our default |
| ±1 reward | | correct +1, wrong −1 | our 0/1 gives the same advantages |

## The objective

```text
J_DAPO(θ) = mean over batches of
    1/Σᵢ|oᵢ|  Σᵢ Σₜ  min( ρᵢ,ₜ·Âᵢ , clip(ρᵢ,ₜ, 1−ε_low, 1+ε_high)·Âᵢ )
    ↑                                        ↑
    token-level: one average over          decoupled clip:
    every token of every answer            ε_low = 0.2, ε_high = 0.28

subject to  0 < #correct answers in the group < G        ← dynamic sampling
Rᵢ = ±1 correctness + overlong penalty                   ← overlong reward shaping
(no −β·KL term)
```

Compare [[GRPO]]: there the average is (1/G) Σᵢ (1/|oᵢ|) Σₜ (per answer, then across answers), the clip is symmetric, every group is kept, and a KL term is subtracted.

## 1. Clip-Higher

**The ratio caps relative change, and only rare tokens can change a lot in relative terms.** Give three tokens in good answers the same push (logit +0.5, the rest of the distribution held fixed):

| p_old | p_new | ρ | Clipped at 1.2? |
| --- | --- | --- | --- |
| 0.9 | 0.937 | 1.04 | no |
| 0.6 | 0.712 | 1.19 | no (barely) |
| 0.01 | 0.0164 | **1.64** | **yes**: capped at 0.012 per rollout |

A common token can't be clipped from above at all (0.9 × 1.2 = 1.08 is impossible). The upper clip binds almost only on **rare tokens, the alternatives the model is exploring**. Common tokens keep growing while rare ones are capped, so probability concentrates and **entropy collapses**. In our `vanilla_s0` run, entropy fell from 0.34 to 0.08 in 100 steps.

**The fix: raise only ε_high** (0.28), so a rare token in a good answer can reach 0.0128 instead of 0.012 per rollout.

**Why not ε_low too.** The bound that applies depends on the advantage's sign:

| | The advantage wants | Clipped (no gradient) when | Never clipped |
| --- | --- | --- | --- |
| Â > 0 | ρ up | ρ > 1 + ε_high | ρ < 1 (moved the wrong way: keep correcting) |
| Â < 0 | ρ down | ρ < 1 − ε_low | ρ > 1 (moved the wrong way: keep correcting) |

The lower bound limits how fast tokens in **bad** answers are pushed down. With ε_low = 0.9 the floor would be 0.1, so a single bad answer could push a token from 0.01 to 0.001 in one rollout. At 0.001 it's almost never sampled again: **one unlucky answer deletes an alternative.** That speeds up entropy collapse instead of preventing it.

> **Clip-Higher needs more than one optimizer step per rollout.** At the first step ρ = 1 exactly, so nothing can be clipped. With one update per rollout (rayyy's setup), Clip-Higher can't change anything; any measured gain is noise. See [[Policy Ratio and Clipping]].

## 2. Dynamic Sampling

**The problem: the batch shrinks as training succeeds.** A group where every answer is correct, or every answer is wrong, has zero reward variance, so Â = 0 for all its answers. These groups are already "dropped" in the sense that they add nothing to the gradient. But the gradient is now an average over fewer informative answers, and their share falls as the model improves. In `vanilla_s0`, the share of mixed groups fell from 72% to about 50% (37–40% all correct by the end). So late-training updates average over about 128 informative answers instead of 256, and the gradient gets noisier exactly when the model is working on its hardest remaining cases.

**The fix:** keep generating groups for new questions, discard those whose **accuracy** is 0 or 1, and stop once the batch has the target number of informative groups. The batch size stays constant.

**The cost is generation, not gradient computation.** The gradient is computed once, on the filled batch. Worked example with `vanilla_s0`'s late numbers: 32 questions per step, about 47% zero-variance groups, generation 38 s of a 53 s step.

```text
informative groups without the fix   32 × 0.53 ≈ 17
questions needed with the fix        32 / 0.53 ≈ 60   (480 completions)
generation                           38 s × 60/32 ≈ 71 s
scoring + update (kept groups only)  ≈ 25 s
step time                            53 s → ≈ 97 s
```

This needs filtering **before** scoring `logp_old` and `logp_ref`, otherwise the discarded groups cost scoring time too.

> **Compare Dynamic Sampling at equal generation cost, not equal steps.** Per step it uses up to about 2× the samples, so a gain "after 100 steps" may just be the extra data.

**Filter on accuracy or on reward variance?** These differ once the reward has shaping terms. With an overlong penalty, an all-wrong group whose answers differ in length has nonzero reward variance. The DAPO paper filters on **accuracy**.

## 3. Token-level Loss

**Sample-level (GRPO) averages within each answer first, so every answer has the same total weight, whatever its length.** Two wrong answers in one batch, both Â = −1, of 50 and 250 tokens:

| | Weight per token, 50-token answer | Weight per token, 250-token answer | Total weight of the long answer |
| --- | --- | --- | --- |
| Sample-level | 1/(2·50) = 1/100 | 1/(2·250) = 1/500 | 1/2 |
| Token-level | 1/300 | 1/300 | 5/6 |

Under sample-level, each token of the long answer gets 5× less push. A long rambling or repetitive bad answer is penalized lightly per token.

**Token-level loss treats every token equally, which cuts both ways:**
- long **wrong** answers get pushed down harder (rambling, repetition), which tends to make answers shorter
- long **correct** answers get pushed up harder (long reasoning is learned from more), which tends to make them longer

DAPO wants both. Which effect wins depends on the setup: with a tight token budget, most long answers are truncated and therefore wrong.

**A test with hand-computed numbers** (`test_unequal_lengths_distinguish_sample_and_token_aggregation`): a 1-token good answer (ρ = 1.1, Â = +1) and a 3-token bad answer (ρ = 0.9, 0.8, 1.0, Â = −1).

```text
sample-level = ( −1.1  +  (0.9 + 0.8 + 1.0)/3 ) / 2  = −0.1
token-level  = ( −1.1  +   0.9 + 0.8 + 1.0     ) / 4  =  0.4
```

> **Gradient accumulation gotcha.** When a mini-batch is split into micro-batches for memory, each micro-batch must divide by the **whole mini-batch's** token count. Dividing by its own count makes it a "mean of means" again: micro-batches of 400 and 1,600 tokens would give their tokens weights of 1/800 and 1/3,200, a 4× gap instead of equal weights.

Dr. GRPO (2025) removes the same 1/|oᵢ| factor, and also the division by the group's std.

## 4. Overlong Reward Shaping

**The problem: a truncated answer has no answer to grade.** The checker reads the last `\boxed{}`, and a truncated answer is cut off before writing one. It scores 0, the same as a wrong answer, so every token of possibly sound reasoning gets a negative advantage. The model can't tell "wrong" from "too long".

**Fix 1: overlong filtering.** Mask truncated answers out of the loss. The misleading signal disappears, but nothing teaches the model to finish sooner.

**Fix 2: soft overlong punishment.** A length penalty added to the correctness reward, growing linearly over the last L_cache tokens before the limit:

```text
penalty(L) =  0                                   L ≤ L_max − L_cache
           =  −(L − (L_max − L_cache)) / L_cache   L_max − L_cache < L ≤ L_max
           =  −1                                  truncated

penalty
   0 ┤━━━━━━━━━━━━━━━━━━━━━━━┓
     │                        ╲
-0.5 ┤                         ╲
     │                          ╲
  -1 ┤                           ●  truncated
     └───────────────────────────┬─────┬──→ length L
                     L_max − L_cache   L_max
                     (192 here)        (256 here)
```

Worked example, L_max = 256, L_cache = 64:

| Answer | Correctness | Penalty | Reward |
| --- | --- | --- | --- |
| correct, 224 tokens | 1 | −32/64 = −0.5 | **0.5** |
| wrong, 224 tokens | 0 | −0.5 | **−0.5** |
| truncated | 0 | −1 | **−1** |

The DAPO paper used L_cache = 4,096 of a 20,480-token budget (20%); the reference repo used 128 of 256 (50%), which starts penalizing at half the budget.

> **A length penalty creates gradient in all-wrong groups.** Lengths 100, 150, 224 and truncated give rewards 0, 0, −0.5, −1: nonzero variance, so the model is pushed toward shorter answers even though none is correct. That isn't always good: on a hard question, the cheapest way to raise this reward is to cut the reasoning short and guess. Watch accuracy and the length of **correct** answers together. Our format-bonus run showed the same mechanism with a box bonus (see [[GRPO DAPO Experiment Log]]).

## Why no KL

In long chain-of-thought RL the policy is expected to move far from the initial model, so a KL penalty mainly holds back learning. DAPO sets β = 0 and relies on clipping for step size. KL is still worth logging as a drift alarm. See [[KL Regularization and Reference Models]].

## The paper's ablation, and other designs

The DAPO paper added the techniques **cumulatively** (Qwen2.5-32B, AIME 2024, avg@32):

| Configuration | AIME 2024 |
| --- | --- |
| Naive GRPO | 30 |
| + Overlong Filtering | 36 |
| + Clip-Higher | 38 |
| + Soft Overlong Punishment | 41 |
| + Token-level Loss | 42 |
| + Dynamic Sampling (= DAPO) | 50 |

Each gain is measured on top of the earlier ones, so the order matters. Three common ablation designs:

| Design | Runs | Answers |
| --- | --- | --- |
| Add one | baseline + X, for each X; plus all | does X help on its own? |
| Cumulative | add X₁, then X₂, … | how much does each add given the earlier ones? |
| Leave one out | all − X, for each X | does X still matter inside the full system? |

This project uses add-one plus all four ([[GRPO DAPO Project Overview]]).

## Common misconceptions

1. **"Clip-Higher widens the clip range."** Only the upper side: [0.8, 1.2] → [0.8, 1.28]. Widening the lower side would let bad answers delete rare tokens.
2. **"With Â < 0, a token at ρ = 0.5 isn't clipped."** It is. Â < 0 wants ρ down, and past 0.8 the `min` picks the clipped term (0.8 × (−1) = −0.8 < −0.5), whose gradient is 0. What is never clipped is the wrong-way move: ρ > 1 with Â < 0, even ρ = 1.3.
3. **"Clip-Higher helps with one update per rollout."** ρ = 1 at the first update, so there is nothing to clip.
4. **"Token-level loss down-weights long good answers."** The opposite: every long answer, good or bad, gets more total weight than under sample-level.
5. **"Dynamic Sampling costs extra gradient computation."** It costs extra generation; the gradient is computed once on the filled batch.
6. **"Zero-variance groups need to be dropped to stop them giving a wrong gradient."** They already give zero gradient. The problem is that fewer answers carry signal, so the gradient is noisier.
7. **"Soft overlong punishment still rewards a truncated answer's reasoning."** A truncated answer has no `\boxed{}`, so it scores 0 − 1 = −1. The penalty only softens the cliff for answers that **finish** close to the limit.
8. **"A length penalty can't help when every answer is wrong."** Any shaping term that varies within a group creates gradient; group normalization sees only differences.

## Interview answer to "DAPO 相比 GRPO 改了什么"

**DAPO 相比 GRPO 改了什么（30 秒）：** DAPO 是字节 Seed 在 GRPO 基础上针对长推理 RL 提出的改进，共四点。第一，Clip-Higher：把 clip 上界从 0.2 放宽到 0.28，下界不变。比例裁剪限制的是相对变化，低概率 token 最容易被上界卡住，导致熵坍塌、探索不足；下界不放宽，是为了避免一次坏样本就把低概率 token 压到接近 0。第二，Dynamic Sampling：全对或全错的组优势为 0，不提供梯度，而且训练越成功这种组越多，所以多采样并过滤掉这些组，保持每个 batch 的有效样本数，代价是额外的生成开销。第三，Token-level loss：GRPO 先在回答内平均再在回答间平均，长回答每个 token 的权重更小，冗长重复的错误回答惩罚不够，长的正确推理也学得不够；改为对所有 token 统一平均。第四，Overlong Reward Shaping：被截断的回答没有最终答案，记 0 分会惩罚可能正确的推理，所以要么把截断样本从 loss 中去掉，要么在接近长度上限时加线性递增的长度惩罚。另外 DAPO 去掉了 KL 惩罚，奖励只用 ±1 的正确性。

**English version:** DAPO keeps GRPO's group-relative advantage and fixes four failures of long-reasoning RL. Clip-Higher raises only the upper clip bound (0.2 → 0.28): the ratio limits relative change, which binds mostly on rare tokens, so entropy collapses; the lower bound stays at 0.2 so a single bad answer can't push a rare token toward zero. Dynamic Sampling over-samples and discards groups whose accuracy is 0 or 1, since they give zero advantage and their share grows as training succeeds; this keeps the number of informative answers per batch constant at the cost of extra generation. Token-level loss averages over every token in the batch instead of within each answer first, so long answers, good and bad, get weight in proportion to their length. Overlong Reward Shaping stops truncated answers being scored like wrong ones: either mask them out of the loss or add a penalty that grows linearly over the last stretch before the length limit. DAPO also drops the KL term and uses a ±1 correctness reward.

**Senior add-on:** Clip-Higher only acts with more than one optimizer step per rollout, since ρ = 1 at the first step. Dynamic Sampling should be compared at equal generation cost, and the filter (accuracy vs reward variance) interacts with length shaping. Any shaping term that ignores correctness, such as a length penalty or a format bonus, creates gradient even in all-wrong groups and can trade correctness for brevity, so track accuracy and the length of correct answers together. Token-level averaging must use the whole mini-batch's token count under gradient accumulation.

## Interview summary

> DAPO (ByteDance Seed, 2025) is GRPO plus four fixes for long-reasoning RL, with no KL term and a ±1 correctness reward. **Clip-Higher** raises only the upper clip bound (ε_high 0.28, ε_low 0.2), because the ratio limits relative change and so mainly caps rare tokens, causing entropy collapse; it only acts with more than one update per rollout. **Dynamic Sampling** discards all-correct and all-wrong groups (Â = 0) and refills the batch, keeping the number of informative answers constant as training succeeds, at the cost of extra generation. **Token-level loss** averages over all tokens instead of per answer, so long answers, good and bad, count in proportion to their length. **Overlong Reward Shaping** stops truncated answers being scored like wrong ones, by masking them or by a length penalty that grows linearly over the last L_cache tokens. On Qwen2.5-32B the four took AIME 2024 from 30 to 50.

## Related notes

- [[GRPO]]
- [[Policy Ratio and Clipping]]
- [[Advantage Estimation]]
- [[KL Regularization and Reference Models]]
- [[Rule-Based and Verifiable Rewards]]
- [[Reward Hacking]]
- [[Decoding and Sampling Parameters]]
- [[RL Training Metrics]]
- [[GRPO DAPO Project Overview]]
- [[GRPO DAPO Experiment Log]]
- [[LLM Training MOC]]
