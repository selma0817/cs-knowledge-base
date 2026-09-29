---
date: 2026-09-29
tags:
  - llm
  - post-training
  - reinforcement-learning
  - grpo
  - deepseek
  - interview
aliases:
  - Group Relative Policy Optimization
  - 介绍一下GRPO
  - GRPO vs PPO
---
**GRPO (Group Relative Policy Optimization)** is PPO without a critic. For each question it samples a **group of G answers**, scores them, and uses each answer's reward relative to its group as the advantage. It then applies PPO's per-token clipped update plus a KL penalty to a reference model. It was introduced in DeepSeekMath (arXiv 2402.03300) and used to train DeepSeek-R1.

## How GRPO answers the three questions

Every RL fine-tuning algorithm makes three choices (see [[LLM Training MOC]]):

| Question | GRPO's answer | Note |
| --- | --- | --- |
| Where does the score come from? | any reward; DeepSeek-R1 used **rule-based** rewards (correct answer, correct format) | [[Rule-Based and Verifiable Rewards]] |
| How much credit does each answer get? | **group-relative advantage** Âᵢ = (Rᵢ − mean)/std, the same for every token of the answer | [[Advantage Estimation]] |
| How far may one update move the model? | **per-token ratio + clipping** (from PPO), plus a **KL term in the loss** | [[Policy Ratio and Clipping]] |

## The loop

```text
repeat:
  ROLLOUT   for each question q: sample G answers from π_old
            reward Rᵢ for each → Âᵢ = (Rᵢ − mean) / std within the group
            logp_old per token (and logp_ref per token, for KL)
  UPDATE    for each optimizer step on this batch:
              logp_new per token → ρ = exp(logp_new − logp_old)
              clipped term − β·KL per token → average (tokens → answers → questions) → loss
              backward, optimizer step
  π_old ← current model
```

## The objective

```text
J(θ) = mean over questions of
         (1/G) Σᵢ  (1/|oᵢ|) Σₜ  [ min( ρᵢ,ₜ·Âᵢ , clip(ρᵢ,ₜ, 1−ε, 1+ε)·Âᵢ )  −  β·KLᵢ,ₜ ]
          ↑          ↑                 ↑                                         ↑
      mean over   mean over      ratio + clipping                        drift from π_ref
       answers    the answer's   (how far per step)
                  tokens

ρᵢ,ₜ = π_θ(oᵢ,ₜ | q, oᵢ,<ₜ) / π_old(oᵢ,ₜ | q, oᵢ,<ₜ)          loss = −J
```

- **Log-probs** feed the ratio ([[Policy Gradient for LLMs]]).
- **Âᵢ** sets the direction and size of the push ([[Advantage Estimation]]).
- **Clipping** caps how far one step moves each token ([[Policy Ratio and Clipping]]).
- **KL** caps total drift from π_ref ([[KL Regularization and Reference Models]]). Unlike classic RLHF-PPO, which puts the KL penalty **into the reward**, GRPO adds it **directly to the loss**.
- The **1/|oᵢ|** averaging within each answer (average per answer, then across answers) is one of the things [[DAPO]] changes.

## Worked example: one group

Question "2+3=?", G = 2. Answer 1 says "5" (R = 1, Â = +1); answer 2 says "6" (R = 0, Â = −1). Illustrative numbers, at an optimizer step after the weights have already moved a little:

| Answer | Token | logp_old | logp_new | ρ | ρ·Â |
| --- | --- | --- | --- | --- | --- |
| 1 (Â = +1) | The | −0.10 | −0.10 | 1.000 | +1.000 |
| | answer | −0.50 | −0.48 | 1.020 | +1.020 |
| | is | −0.20 | −0.19 | 1.010 | +1.010 |
| | **5** | −1.20 | −1.05 | 1.162 | +1.162 |
| | | | | **mean** | **+1.048** |
| 2 (Â = −1) | The | −0.10 | −0.10 | 1.000 | −1.000 |
| | answer | −0.50 | −0.48 | 1.020 | −1.020 |
| | is | −0.20 | −0.19 | 1.010 | −1.010 |
| | **6** | −1.00 | −1.15 | 0.861 | −0.861 |
| | | | | **mean** | **−0.973** |

```text
J for this group = (1.048 + (−0.973)) / 2 = 0.038      loss = −J (then averaged over questions)
```

All ratios are inside [0.8, 1.2], so clipping changes nothing here.

> **The shared tokens "The answer is" cancel.** They appear in both answers with identical context, so they get the same gradient, pushed up in answer 1 and down in answer 2. Only "5" (up) and "6" (down) get a net push. This is how outcome-only rewards still assign credit to the tokens that made the difference. The cancellation is exact here partly because both answers have the same length (see the 1/|oᵢ| factor).

## Why no critic

PPO learns a **value network** (critic) to estimate expected reward. It is usually as large as the policy and has to be trained alongside it. GRPO estimates expected reward from the group mean instead.

| | Models in memory during RL |
| --- | --- |
| PPO (classic RLHF) | policy, reference, reward model, **critic** (4) |
| GRPO with rule-based rewards | policy, reference (2) |
| GRPO + LoRA | effectively 1: the reference is the base model with the adapter turned off |

The price is **G generations per question**, and generation is already the most expensive part of RL training.

## Known weak points (the ones DAPO addresses)

To be observed in practice before studying the fixes in [[DAPO]]:
- **Groups where every answer gets the same reward** give Â = 0 and waste samples, and they become more common as the model improves.
- **Entropy collapse:** the model's output distribution becomes too sharp and it stops exploring.
- **Length effects** from averaging per answer (1/|oᵢ|).
- **Truncated answers** that hit the maximum length get noisy rewards.
- **With one optimizer step per rollout batch, ρ = 1 and clipping does nothing**, so GRPO reduces to REINFORCE with a group baseline plus KL.

## Interview answer to "介绍一下GRPO" / "GRPO 和 PPO 的区别"

**介绍一下 GRPO（30 秒）：** GRPO 是 DeepSeek 提出的强化学习算法，可以看作去掉 critic 的 PPO。对每个问题采样一组 G 个回答，用规则或奖励模型打分，再用组内奖励的均值和标准差做归一化，得到每个回答的优势值 Â = (R − mean)/std，同一回答的所有 token 共享这个优势。更新时沿用 PPO：对每个 token 计算新旧策略的概率比 ρ，用 clip 把 ρ 限制在 [1−ε, 1+ε]，防止一步更新过大，再在 loss 里加上和参考模型之间的 KL 惩罚，防止整体偏离太远。

**和 PPO 的区别：** 核心是优势估计。PPO 训练一个 critic 预测期望回报，用 GAE 算每个 token 的优势；GRPO 对同一问题采样多次，用组内相对奖励作为优势，不需要 critic，显存和训练复杂度都更低。另外 PPO 通常把 KL 惩罚加进奖励，GRPO 直接加在 loss 里。代价是每个问题要生成 G 个回答；如果一组回答奖励全部相同，优势全为 0，这个问题就不提供梯度。

**English version:** GRPO is PPO without a critic. For each question it samples G answers, scores them (DeepSeek-R1 used rule-based rewards), and normalizes each reward within the group, Â = (R − mean)/std, applied to every token of the answer. The update is PPO's per-token clipped objective on the ratio π_θ/π_old, plus a KL penalty to a reference model added directly to the loss. Versus PPO: no value network (the group mean is the baseline), which saves a model's worth of memory and a second training problem, at the cost of G generations per question. Groups where every answer gets the same reward give zero advantage and no gradient.

**Senior add-on:** with one optimizer step per rollout batch, ρ = 1, clipping never activates, and GRPO is effectively REINFORCE with a group baseline, so clip-based ablations need several optimizer steps per rollout. For 0/1 rewards, Â(correct) = √((1−p)/p), so rare successes get large pushes. Averaging per answer (1/|oᵢ|) introduces a length effect that DAPO's token-level loss and Dr. GRPO both change.

## Interview summary

> GRPO (DeepSeekMath, used for DeepSeek-R1) samples G answers per question, scores them, and uses the group-normalized reward Âᵢ = (Rᵢ − mean)/std as a per-answer advantage shared by all its tokens, replacing PPO's critic. It optimizes PPO's clipped per-token objective min(ρÂ, clip(ρ, 1−ε, 1+ε)Â) with ρ = π_θ/π_old, minus β·KL to a frozen reference model added directly to the loss, averaged over tokens within each answer, then over answers and questions. Tokens shared by good and bad answers cancel, so outcome rewards still assign credit. It needs only the policy and reference in memory (effectively one model with LoRA), but costs G generations per question. Its weak points are groups where every answer gets the same reward (zero gradient), entropy collapse, length effects from per-answer averaging, and noisy truncated answers, which DAPO addresses. With one optimizer step per rollout, clipping is inactive and it reduces to REINFORCE with a group baseline.

## Related notes

- [[Policy Gradient for LLMs]]
- [[Advantage Estimation]]
- [[Policy Ratio and Clipping]]
- [[KL Regularization and Reference Models]]
- [[Rule-Based and Verifiable Rewards]]
- [[DAPO]]
- [[RLHF with PPO]]
- [[LLM Training MOC]]
