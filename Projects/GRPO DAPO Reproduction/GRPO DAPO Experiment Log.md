---
date: 2026-10-02
aliases:
  - grpo-dapo experiment log
---
Dated record of every run in [[GRPO DAPO Project Overview|grpo-dapo]]: what I expected, what ran, what happened, and what I decided. Résumé numbers and interview stories come from here.

## 2026-10-02 · Step 2 baseline: Qwen2.5-0.5B-Instruct on GSM8K test

**Setup.** All 1,319 test questions; system prompt "Please reason step by step, and put your final answer within \boxed{}."; greedy (1 per question) and sampled (8 per question, T 1.0, top-p 1.0, top-k off, repetition penalty 1.0); `max_new_tokens` 512; seed 0. Code at `031107e` plus a tqdm progress bar; RTX 4070 Ti, torch 2.14.1+cu130, transformers 5.18.0. Runtime 20.6 min (~0.1 s per completion with Hugging Face `generate`). Result: `results/m0/qwen2.5-0.5b-instruct_gsm8k-test.json`.

| | Greedy | Sampled (T = 1.0) |
| --- | --- | --- |
| Accuracy | 47.5% | 31.5% (pass@1) |
| pass@2 / 4 / 8 | | 44.6% / 57.0% / 68.1% |
| Format rate | 94.6% | 77.9% |
| Boxed but unparseable | 0.9% | 1.0% |
| Truncation (512 tokens) | 4.4% | 9.9% |
| Length mean / p90 | 306 / 440 | 320 / 511 |

Groups at step 0 (sampled, 8 per question): **mixed 64.5%**, all wrong 31.9%, all correct 3.6%; mean p(1−p) = 0.115.

**Observations.**
- **Pipeline sanity check passed:** greedy 47.5% matches nanogrpo's independent 47.8% (same model, test set and 512-token limit); Qwen reports roughly 50%.
- **Sampling at T = 1 costs 16 points** (47.5% → 31.5%): the tail of the full distribution derails a 0.5B model. This is the distribution GRPO trains.
- **pass@8 = 68% vs pass@1 = 31%:** the ability is often there but unreliable, which is what RL sharpens.
- **Healthy GRPO signal:** about two thirds of groups are mixed. The wasted third is mostly *all wrong* (too hard); expect it to shift toward *all correct* as the model improves (the trend Dynamic Sampling addresses).
- **Strict format (D2) is safe:** at 77.9% sampled format rate, P(no boxed answer in a group of 8) = 0.22⁸ ≈ 0.0005%. No cold start.
- **Truncation 9.9% (sampled) needed a decision**, see the next entry. Of 1,048 truncated completions, only 104 (10%) ended in an exact repetition loop; samples showed **incoherent drift** instead (invented words, wrong numbers in neat LaTeX, switching into nonsense Python).

## 2026-10-02 · Budget test: `max_new_tokens` 1024 on the first 200 test questions

**Question.** Are the 9.9% truncated answers correct reasoning that ran out of room (→ raise the budget), or drift (→ keep 512)?

**Setup.** Sampled run only, first 200 questions × 8, `max_new_tokens` 1024, otherwise as the baseline. Runtime 399 s. Result: `results/m0/qwen2.5-0.5b-instruct_gsm8k-test_first200_max-new-tokens-1024.json`.

| | 512 (full test) | 1024 (first 200) |
| --- | --- | --- |
| Accuracy | 31.5% | 32.1% |
| Format rate | 77.9% | 84.3% |
| Truncation | 9.9% | 0.3% |
| Length median / p90 | 306 / 511 | 299 / 520 |
| pass@8 | 68.1% | 70.0% |

**Result.** With more room, the drifting answers mostly *finish* (truncation 9.9% → 0.3%), but they finish **wrong**: format rate +6.4 points, accuracy only +0.6.

**Caveat.** The two columns cover different question sets (full test vs first 200); I did not compute the 512-token numbers on the same 200 questions. The first 200 look slightly easier (all-correct 4.5% vs 3.6%), so the true accuracy gain from 1024 is, if anything, smaller.

**Cost.** Hugging Face `generate` uses static batching: each batch runs until its longest row stops, and with 256 sampled rows per batch almost every batch has one that drifts to the limit. Doubling the budget roughly doubles generation time per training step (~25 s → ~50 s for 32 questions × 8). See [[Continuous Batching and PagedAttention]].

**Decision: keep `max_new_tokens` = 512 for training.** Drifting answers getting reward 0 is mostly the correct signal, not noise.

**Prediction to check in steps 3–4:** GRPO should push the model toward coherent, shorter answers, so the **truncation rate should fall below 9.9%** during training. Track it every step.

## 2026-10-06 · Mac smoke test of the training loop

Two steps (2 questions × 4 samples, 2 updates per rollout), real model on the Mac GPU, W&B off. Code at `35268ea` with no uncommitted changes. Everything ran end to end (evaluation at step 0, rollout, scoring, updates, final checkpoint, `summary.json`). 8,798,208 trainable parameters of 502,830,976, matching the ≈ 8.8M estimate for r = 16 on all 7 projections. Health metric `max |logp_new − logp_old|` at each rollout's first update: 6.5e-5 and 3.6e-5 (below the 1e-4 warning; not exactly 0 because the no-gradient and gradient passes use slightly different kernels). 1.5–2.5 min per step on the Mac, so real runs go on the 4070 Ti.

Also verified that `top_k=0` really disables top-k in transformers 5.18: with `output_scores`, all vocabulary entries stay finite, while omitting `top_k` leaves only 20 (Qwen's default). The "generation flags may be ignored" warning is harmless.

## 2026-10-06 · Step 3 · `vanilla_s0`: plan and predictions (written before the run)

**What it tests.** One configuration, `vanilla` (GRPO, no DAPO techniques, β = 0), against the untrained model (the baseline, and the run's own step-0 evaluation, identical to it since LoRA starts with B = 0). It establishes that training works and gives the reference curve for steps 4–7. It is **not** an ablation: one configuration, one seed.

**Setup.** `uv run python scripts/train.py --preset vanilla --run-name vanilla_s0` on the RTX 4070 Ti: Qwen2.5-0.5B-Instruct + LoRA (all 7 projections, r 16, α 32, dropout 0), 32 questions × 8 samples per step, 4 updates per rollout (micro-batches of 8), learning rate 1e-5, ε 0.2/0.2, β 0 (KL logged), `sample` averaging, T = 1, 512 tokens, 100 steps (3,200 GSM8K train questions). Evaluation at step 0 and every 10 steps on 200 fixed test questions (greedy + 4 samples); final evaluation on all 1,319 (greedy + 8 samples).

**Compared with rayyy's "GRPO baseline" row (32%):** 16× more completions per step (256 vs 16), 4 updates per rollout instead of 1 (so clipping acts), LoRA dropout 0 instead of 0.05, 512 tokens instead of 256, held-out evaluation every 10 steps and on the full test set instead of once on 100 questions.

| Metric | Start | Predicted at step 100 | Reasoning | Result |
| --- | --- | --- | --- | --- |
| Sampled format rate | 77.9% | > 95%, mostly within ~30 steps | boxing gets the big push; shared tokens cancel | |
| Sampled pass@1 (T = 1) | 31.5% | ~38–45% | RL sharpens the T = 1 distribution | |
| Greedy accuracy | 47.5% | ~50–54% | smaller gain; nanogrpo got +4 to +6 points with similar completions | |
| Greedy − sampled gap | 16 points | shrinks | sharpening moves sampling toward greedy | |
| pass@8 (final) | 68.1% | about flat (66–72%) | RL mostly makes existing solutions reliable | |
| Truncation (sampled) | 9.9% | falls to ~2–5% | drifting answers get 0; the end token is trained | |
| Mixed / all-correct groups | 64.5% / 3.6% | mixed ~60%, all-correct ~10–15% | rising accuracy turns easy groups all-correct | |
| Entropy | step 1 value | gradually falling | sharpening; whether it collapses is step 4 | |
| KL to the start | 0 | small, rising (~1e-3–1e-2) | lr 1e-5, LoRA, 100 steps | |
| Clip fractions | 0 | low (< ~2%), mostly in updates 2–4 | small learning rate | |
| Health metric | | ≈ 0 every step | the invariant | |
| Step time | | ~40–60 s; ~1.5–2 h total | M0 throughput | |

**Uncertainties.** The learning rate (flat reward after ~30 steps → too low; plunging entropy and degrading outputs → too high). Noise: one seed and 200 evaluation questions give about ±3.5 points on the evaluation curve.

**Success criteria.** (1) Completes 100 steps without running out of memory, health metric ≈ 0. (2) Held-out sampled pass@1 improves by more than 5 points. (3) Format rate above 95%. (4) Truncation falls. (5) No sign of reward hacking: training reward and held-out accuracy rise together; unparseable rate stays ~1%.

**Before the long run:** see the GPU smoke test below. The first step of the real run doubles as the memory check: peak GPU memory should stay below ~15 GB (16 GB card); if it runs out of memory, use `--micro-batch-size 4`.

## 2026-10-06 · GPU smoke test (RTX 4070 Ti SUPER, 16 GB)

README smoke command (2 questions × 4 samples, 2 updates, micro-batches of 4, 2 steps), code at `dd3f832`, no uncommitted changes; torch 2.14.1+cu130. Result: `results/train/smoke/`. **Health metric exactly 0.0** at both steps (on CUDA the no-gradient and gradient scoring passes match exactly; the Mac gave 6.5e-5). Ratio range 0.78–1.39 with zero high-clip fraction (tokens above 1.2 had Â < 0, the harmful direction, which is never clipped; large ratios come from low-probability tokens). KL 2–3e-4. Peak GPU memory 6.4 GB at micro-batch 4; the logits-related part doubles at micro-batch 8, so ~11–12 GB is expected for the real run, within the 16 GB card. Speed: rollout 7–9 s for 8 completions, scoring 0.3 s, update 0.5 s; extrapolated ~40 s per step at full size and ~1.75–2 h for the 100-step run including evaluations.

## Next

Run `shape_check`, then `vanilla_s0`; fill in the Result column; then step 4 (run vanilla GRPO longer until it fails).
