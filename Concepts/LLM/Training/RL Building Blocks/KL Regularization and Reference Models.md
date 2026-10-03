---
date: 2026-10-02
tags:
  - llm
  - post-training
  - reinforcement-learning
  - kl-divergence
  - grpo
  - interview
aliases:
  - KL penalty
  - KL divergence
  - k1 k2 k3 estimators
  - reference model
  - π_ref
  - KL 散度
  - 为什么 DAPO 去掉 KL
---
The **KL penalty** keeps the policy close to a frozen **reference model** π_ref (the model before RL) by subtracting β · KL(π_θ ‖ π_ref) from the objective. It is the "rubber band back to the start", as opposed to clipping, which limits each step relative to π_old ([[Policy Ratio and Clipping]]). In practice the KL is **estimated from the sampled tokens** with the **k3 estimator**, which is unbiased and never negative.

## The quantity

At one position, the KL between the two next-token distributions is

```text
KL(π_θ ‖ π_ref) = Σᵥ π_θ(v) · log( π_θ(v) / π_ref(v) )        sum over the whole vocabulary
               = average over v ~ π_θ of  log( π_θ(v) / π_ref(v) )
```

**The exact sum is avoided** because it needs both models' full distributions (151,936 entries for Qwen) at every position: two logits tensors of several GB per micro-batch ([[LoRA and QLoRA]]). The second form shows the way out: the rollout tokens were *sampled* from the policy, so **averaging a per-token quantity over them estimates the KL**, using one log-prob per token from each model.

## Three per-token estimators

Let r = π_ref(token) / π_θ(token) for the sampled token.

| Estimator | Formula | Average equals KL? | Never negative? | Noise |
| --- | --- | --- | --- | --- |
| **k1** | log(π_θ / π_ref) = −log r | yes | **no** | high |
| **k2** | ½ (log r)² | no (biased) | yes | low |
| **k3** | r − log r − 1 | **yes** | **yes** | low |

Why k3 works: the average of r under π_θ is Σᵥ π_θ(v) · π_ref(v)/π_θ(v) = Σᵥ π_ref(v) = 1, so (r − 1) averages to 0. Then k3 = (r − 1) + k1 has the same average as k1 (the KL), while f(r) = r − log r − 1 has slope 1 − 1/r and minimum f(1) = 0, so every term is ≥ 0. The names come from John Schulman's note *Approximating KL Divergence*.

| Sampled token | π_θ | π_ref | r | k1 | k3 |
| --- | --- | --- | --- | --- | --- |
| A | 0.4 | 0.2 | 0.5 | +0.693 | 0.193 |
| B | 0.2 | 0.4 | 2.0 | **−0.693** | 0.307 |
| C | 0.1 | 0.3 | 3.0 | **−1.099** | 0.901 |

k1 goes negative whenever the policy made the sampled token *less* likely than the reference; as a per-token penalty, that rewards those tokens, and only the average is meaningful. k3 stays positive and still records the disagreement.

(The tokens are sampled from π_old rather than π_θ; within one batch the two are close, so the estimate is fine in practice.)

## Where the penalty goes

| | Classic RLHF with PPO | GRPO |
| --- | --- | --- |
| How | subtract β · log(π_θ / π_ref) from the **reward** at each token | subtract β · k3 directly in the **loss**, per token |
| Typical β | tuned per run | 0.04 in DeepSeekMath; **0** in DAPO and TRL's default |

## Why reasoning RL often drops it (β = 0)

- **Long chain-of-thought is a new behavior**: the model has to move far from its starting distribution, and a leash back to the start mainly gets in the way (the DAPO authors' argument).
- **The risk:** KL also guards against reward hacking and degeneration (drift, unreadable text). Classic RLHF needs it because a learned reward model is easy to over-optimize ([[Reward Hacking]]); with a **rule-based checker** there is far less to exploit, so the leash matters less.
- **Keep logging KL even at β = 0:** it is the drift alarm.

## The reference model

- **Separate copy:** load the base model a second time and freeze it (1 GB at 0.5B, 14 GB at 7B).
- **With LoRA:** the base weights never change, so π_ref is the **same model with the adapter disabled** (`with model.disable_adapter():`): one extra forward pass, no extra memory. At step 0, B = 0 so π_θ = π_ref exactly and KL = 0.

## Common misconceptions

- **"The KL penalty and clipping do the same job."** No. Clipping compares against π_old and resets every batch; KL compares against the fixed π_ref and limits total drift.
- **"Compute the KL exactly over the vocabulary."** Usually not: it needs both models' full logits at every position. Estimate it from sampled tokens.
- **"`log π_θ − log π_ref` is a fine per-token KL."** Its average is right, but single tokens go negative and it's noisy. Use k3.
- **"k3 can be negative."** No: r − log r − 1 ≥ 0, with equality only at r = 1.
- **"β = 0 means you don't need the reference model."** You still want it to log KL as a drift alarm; with LoRA it costs no memory.

## Interview answer to "GRPO 里的 KL 怎么算 / 为什么 DAPO 去掉 KL"

**中文 (30 秒):** KL 惩罚让策略不要离参考模型（RL 之前的模型）太远。精确的 KL 要对整个词表求和，需要两个模型在每个位置的完整分布，太占显存，所以用采样到的 token 来估计。最简单的 k1 = log(π_θ/π_ref) 均值是对的，但单个 token 可能为负、方差大；GRPO 用 k3 = r − log r − 1，其中 r = π_ref/π_θ，它的期望等于 KL，而且每一项都不为负。GRPO 把 β·KL 直接加在 loss 里，PPO 一般加在 reward 里。DAPO 去掉 KL，是因为长链推理需要模型远离初始分布；风险是更容易 reward hacking，但规则奖励比奖励模型难被钻空子。即使 β=0 也应该记录 KL 作为偏移报警；用 LoRA 时关掉 adapter 就是参考模型，不需要第二份权重。

**English:** The KL penalty keeps the policy close to the reference model (the model before RL). The exact KL sums over the whole vocabulary and needs both models' full distributions at every position, so it's estimated from the sampled tokens. The simplest estimator, k1 = log(π_θ/π_ref), has the right average but goes negative per token and is noisy; GRPO uses k3 = r − log r − 1 with r = π_ref/π_θ, which is unbiased and never negative. GRPO adds β·KL to the loss; PPO-style RLHF adds it to the reward. DAPO drops it because long reasoning needs the model to move far from its start; the risk is reward hacking, which is lower with a rule-based reward than with a reward model. Keep logging KL even at β = 0; with LoRA the reference is the base model with the adapter disabled.

## Interview summary

> The KL penalty β·KL(π_θ ‖ π_ref) keeps the policy near the frozen pre-RL model, limiting total drift, unlike clipping, which limits each step against π_old. The exact KL needs both models' full vocabulary distributions at every position, so it is estimated per sampled token: k1 = log(π_θ/π_ref) is unbiased but noisy and can be negative; k3 = r − log r − 1 with r = π_ref/π_θ is unbiased (since E[r] = 1) and never negative, which is why GRPO uses it. GRPO subtracts β·k3 in the loss (DeepSeekMath β = 0.04); PPO-style RLHF subtracts it from the reward. DAPO and TRL's default use β = 0, because long reasoning must move far from the start and a rule-based reward is hard to hack; KL should still be logged as a drift alarm. With LoRA, π_ref is the same model with the adapter disabled, costing one forward pass and no memory.

## Related notes

- [[Policy Ratio and Clipping]]
- [[LoRA and QLoRA]]
- [[GRPO]]
- [[Reward Hacking]]
- [[DAPO]]
- [[LLM Training MOC]]
