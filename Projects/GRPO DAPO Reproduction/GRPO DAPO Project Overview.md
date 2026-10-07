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
| Hardware | RTX 4070 Ti SUPER (16 GB, Linux) for runs; Mac for code and CPU tests; Azure GPUs for 1.5B / multi-seed |
| Workflow | edit code on the Mac → push → `git pull` on Linux; Linux commits results only (`results/`) |
| References | DeepSeekMath (GRPO, arXiv 2402.03300), DAPO (arXiv 2503.14476), TRL `GRPOTrainer` (numerical checks), verl `core_algos.py` |

## Steps

| Step | What | Status |
| --- | --- | --- |
| 1 | Rule-based reward (`reward.py`, 87 tests) | ✅ 2026-10-01 |
| 2 | Baseline evaluation on GSM8K test | ✅ 2026-10-02 |
| 3 | GRPO core and first training run: `Policy` (LoRA, reference via disabled adapter), log-probs, advantage, loss, training loop, held-out evaluation every N steps | ✅ 2026-10-06 (`vanilla_s0`; replication of rayyy's setup 2026-10-07) |
| 4 | Diagnostics; run vanilla GRPO until it fails | next |
| 5 | Difficulty-graded data: per-question solve rates on the train split; MATH support (dataset-specific gold extraction; `is_equivalent` = string → exact numeric → `math-verify`) | |
| 6 | DAPO switches: Clip-Higher, Dynamic Sampling, Token-level Loss, Overlong Reward Shaping | |
| 7 | Ablations across seeds | |

Step 5 comes after GRPO works on plain GSM8K, so a failing first run has one cause to investigate, and before the DAPO ablations, which run on the final dataset. (Earlier notes and file names use the original labels: M1 = step 1, M0 = step 2, M3 = step 3, M4 = step 4, M2 and R5 = step 5, M5 = step 6, M6 = step 7.)

## Design decisions

- **Reward:** answer in `\boxed{}`; no box → 0; last complete box counts; exact numeric equality (`Fraction`); fail closed on model output; gold answers validated at load time. Spec: `docs/reward-spec.md`. See [[Rule-Based and Verifiable Rewards]].
- **Sampling:** temperature 1.0, top-p 1.0, top-k off, repetition penalty 1.0, all set explicitly (the model's defaults differ). See [[Decoding and Sampling Parameters]].
- **Generation budget:** `max_new_tokens = 512` (decided from the step 2 budget test, see [[GRPO DAPO Experiment Log]]).
- **Updates per rollout > 1** (mini-batches), so clipping and Clip-Higher actually act. See [[Policy Ratio and Clipping]].
- **KL: β = 0 in every ablation run** (vanilla GRPO included), so the ablations isolate DAPO's four techniques; KL is still logged as a drift alarm. **One extra run at β = 0.04** (DeepSeekMath's value) shows what the KL term does. See [[KL Regularization and Reference Models]].
- **LoRA:** all 7 projection layers, r = 16, α = 32, dropout 0, learning rate 1e-5 to start; reference model = the same model with the adapter disabled. See [[LoRA and QLoRA]].

## Notes on the reference repo (rayyy032/qwen-math-grpo-dapo)

Read for ideas only; my code is my own. What auditing it found:

- **Config shared by every ablation preset:** LoRA r = 32, alpha = 32, dropout 0.05 on all seven projection layers (`q, k, v, o, gate, up, down`); no 8-bit; learning rate 1e-5 (Adam); group size 8 with **2 questions per step** (16 completions); 100 steps; β = 0 (no KL); `ppo_epochs = 1`. The reference model is a **separately loaded** base model, a second copy of the weights.
- **Found when replicating (2026-10-07), missed in the first audit:**
  - **The reward adds +0.2 for any `\boxed{}`** (`format_weight = 0.2`), even when the answer is wrong. Their "GRPO" is GRPO plus format shaping, which likely explains most of their format rate (76%) and shorter outputs.
  - **One optimizer step per question group**, so 2 steps per training step (200 in total).
  - **Qwen's `generation_config` leaks into sampling:** top-p 0.8 and repetition penalty 1.1 stay on, in training and in evaluation.
  - **The reported average length, clip fraction and final reward are the last training step's values,** not evaluation numbers.
- **One update per rollout means Clip-Higher has nothing to act on** (ρ = 1). Their reported +8 points for Clip-Higher can't come from the clipping mechanism; with one seed and 100 evaluation questions, noise is the likely explanation. LoRA dropout 0.05 may also make ρ noisy, since dropout changes the forward pass between scoring and training.
- **MATH gold answers are broken:** `_extract_gt` only looks for `####`, so for MATH it returns the whole solution text as the "gold answer".
- **Their MATH dataset is gone:** `hendrycks/competition_math` was disabled by a DMCA takedown.
- **Evaluation only at the end of training;** a single clip fraction; no compute accounting; surprisal instead of true entropy.

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
