---
date: 2026-09-29
aliases:
  - llm training moc
  - post-training moc
  - fine-tuning moc
---
# LLM Training MOC

Post-training adapts a pretrained LLM: **SFT** imitates demonstrations, **parameter-efficient methods** (LoRA) make training cheap, and **RL fine-tuning** (PPO, GRPO, DAPO) optimizes the model's own outputs against a reward. The notes are organized around one idea: every RL fine-tuning algorithm is a **combination of building blocks**, so the blocks get their own notes, and each algorithm note describes only how it combines them and what it changes from its predecessor.

## The three questions every RL algorithm answers

| Question | Building block | Possible answers |
| --- | --- | --- |
| 1. Where does the score come from? | Reward | learned reward model · rule-based / verifiable rewards · LLM-as-judge |
| 2. How much credit does each answer get? | [[Advantage Estimation]] | critic + GAE (PPO) · group-relative (GRPO) · leave-one-out (RLOO) |
| 3. How far may one update move the model? | [[Policy Ratio and Clipping]], KL | ratio + clipping · KL penalty to a reference model |

| Algorithm | Reward | Advantage | Update rule | Models in memory |
| --- | --- | --- | --- | --- |
| PPO (classic RLHF) | reward model | critic + GAE | clip + KL penalty in the reward | 4: policy, reference, reward, critic |
| DPO | none (learns directly from preference pairs) | none | classification-style loss on pairs | 2: policy, reference |
| [[GRPO]] | any (DeepSeek-R1: rule-based) | group mean / std | clip + KL term in the loss | 2: policy, reference |
| DAPO | rule-based | group-relative | Clip-Higher, token-level loss, no KL | 1: policy |

## Learning map

1. [[Policy Gradient for LLMs]] ✅
   - Per-token log-probs; generating vs scoring (teacher forcing)
   - The update: raise tokens of better-than-average answers, lower worse ones
   - Credit assignment with outcome rewards; why RL is more fragile than SFT

2. [[Advantage Estimation]] ✅
   - Why a baseline; group-relative advantage replaces the critic
   - Closed form for 0/1 rewards; groups where every answer gets the same reward

3. [[Policy Ratio and Clipping]] ✅
   - Reusing rollouts; the per-token ratio; pushed vs stopped
   - The clipped objective piece by piece: 𝟙[not clipped] · ρ · Â · ∇log π
   - Worked example: one batch, three optimizer steps (no regeneration during the update)
   - One optimizer step per batch ⇒ ρ = 1 ⇒ plain policy gradient
   - Updates per rollout (mini-batches vs micro-batches); why Clip-Higher needs more than one
   - Clipping vs KL

4. [[GRPO]] ✅
   - The full objective, a worked group, why no critic, weak points

5. [[Rule-Based and Verifiable Rewards]] ✅
   - Extraction (last complete `\boxed{}`, one-pass brace stack), exact normalization, levels of equivalence
   - Strict format: why it teaches the format, and the cold-start risk
   - Partial credit; reward values don't matter under group normalization
   - [[Reward Hacking]] ✅: checker bugs, blind spots of outcome rewards, reward-model overoptimization

6. [[KL Regularization and Reference Models]]
   - Per-token KL estimators; the reference model for free with LoRA; why DAPO drops KL

7. [[LoRA and QLoRA]]
   - Low-rank adapters, memory accounting; connects to [[Quantization]]

8. [[RL Training Metrics]]
   - Entropy, KL, response length, fraction of groups with the same reward, clip fraction

9. [[DAPO]]
   - Clip-Higher, Dynamic Sampling, Token-level Loss, Overlong Reward Shaping, each tied to a GRPO failure

10. [[RLHF with PPO]], [[Reward Models]], [[DPO]], [[Supervised Fine-Tuning]]
    - The classic pipeline, for interview completeness

11. [[RL Training Systems]]
    - Generating rollouts with vLLM, memory, train–inference mismatch; connects to [[LLM Serving]] and [[PagedAttention]]

## Core mental model

- **RL fine-tuning is SFT on the model's own samples, weighted by advantage.** Everything else (ratio, clipping, KL) exists to keep that update stable.
- **The model generates its own training data**, so a bad step compounds. That is why RL needs limits on step size and SFT doesn't.
- **Algorithms differ mainly in how they answer the three questions**, so learn the blocks first and read each new algorithm as a set of changes to an earlier one.

## Related notes

- [[Interview MOC]]
- [[LLM Serving]]
- [[Quantization]]
