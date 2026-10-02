---
date: 2026-10-02
aliases:
  - grpo-dapo project
  - GRPO DAPO reproduction
---
**grpo-dapo** reproduces GRPO and DAPO for math reasoning on Qwen2.5-Instruct (0.5B, then 1.5B) with LoRA, in my own PyTorch + Transformers + PEFT code, and ablates DAPO's four techniques (Clip-Higher, Dynamic Sampling, Token-level Loss, Overlong Reward Shaping) on GSM8K and later MATH. Code: `~/Desktop/grpo-dapo`, GitHub `selma0817/grpo-dapo` (private until results are in).

## Setup

| | |
| --- | --- |
| Models | `Qwen/Qwen2.5-0.5B-Instruct` (1.5B later) |
| Data | GSM8K (`openai/gsm8k`); later MATH: `EleutherAI/hendrycks_math` train, `HuggingFaceH4/MATH-500` eval |
| Hardware | RTX 4070 Ti (12 GB, Linux) for runs; Mac for code and CPU tests; Azure GPUs for 1.5B / multi-seed |
| Workflow | edit code on the Mac → push → `git pull` on Linux; Linux commits results only (`results/`) |
| References | DeepSeekMath (GRPO, arXiv 2402.03300), DAPO (arXiv 2503.14476), TRL `GRPOTrainer` (numerical checks), verl `core_algos.py` |

## Milestones

| | Milestone | Status |
| --- | --- | --- |
| M1 | Rule-based reward (`reward.py`, 87 tests) | ✅ 2026-10-01 |
| M0 | Baseline evaluation on GSM8K test | ✅ 2026-10-02 |
| M3 | GRPO core: `Policy` (LoRA, reference via disabled adapter), log-probs, advantage, loss, training loop, held-out eval every N steps | next |
| M4 | Diagnostics; run vanilla GRPO until it fails | |
| M2 | Difficulty buckets from per-question solve rates | |
| R5 | MATH: dataset-specific gold extraction; `is_equivalent` = string → exact numeric → `math-verify` | |
| M5 | DAPO switches: Clip-Higher, Dynamic Sampling, Token-level Loss, Overlong Reward Shaping | |
| M6 | Ablations across seeds | |

## Design decisions

- **Reward:** answer in `\boxed{}`; no box → 0; last complete box counts; exact numeric equality (`Fraction`); fail closed on model output; gold answers validated at load time. Spec: `docs/reward-spec.md`. See [[Rule-Based and Verifiable Rewards]].
- **Sampling:** temperature 1.0, top-p 1.0, top-k off, repetition penalty 1.0, all set explicitly (the model's defaults differ). See [[Decoding and Sampling Parameters]].
- **Generation budget:** `max_new_tokens = 512` (decided from the M0 budget test, see [[GRPO DAPO Experiment Log]]).
- **Updates per rollout > 1** (mini-batches), so clipping and Clip-Higher actually act. See [[Policy Ratio and Clipping]].

## My own experiments (beyond the reproduction)

- **Clip-Higher's gain as a function of updates per rollout** (1, 2, 4, 8): predicted zero at 1, growing with more updates.
- **Dynamic Sampling at equal compute:** compare by samples and tokens generated, not by steps.
- Multiple seeds with confidence intervals; full test-set evaluation.

## Related notes

- [[GRPO DAPO Experiment Log]]
- [[LLM Training MOC]]
- [[GRPO]]
- [[Policy Ratio and Clipping]]
- [[Rule-Based and Verifiable Rewards]]
- [[Reward Hacking]]
- [[Decoding and Sampling Parameters]]
