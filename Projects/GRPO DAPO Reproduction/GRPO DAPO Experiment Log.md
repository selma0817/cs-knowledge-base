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
| Sampled format rate | 77.9% | > 95%, mostly within ~30 steps | boxing gets the big push; shared tokens cancel | **96.7%** (final); 95% by step 30 ✅ |
| Sampled pass@1 (T = 1) | 31.5% | ~38–45% | RL sharpens the T = 1 distribution | **49.8%** ✅ (better than predicted) |
| Greedy accuracy | 47.5% | ~50–54% | smaller gain; nanogrpo got +4 to +6 points with similar completions | **51.6%** ✅ |
| Greedy − sampled gap | 16 points | shrinks | sharpening moves sampling toward greedy | **1.8 points** ✅ (far more than expected) |
| pass@8 (final) | 68.1% | about flat (66–72%) | RL mostly makes existing solutions reliable | **77.3%** ❌ (+9 points) |
| Truncation (sampled) | 9.9% | falls to ~2–5% | drifting answers get 0; the end token is trained | **3.5%** (training 6.6% → 1.3%) ✅ |
| Mixed / all-correct groups | 64.5% / 3.6% | mixed ~60%, all-correct ~10–15% | rising accuracy turns easy groups all-correct | mixed ~50–55%, **all-correct ~37–40%** ❌ (far higher) |
| Entropy | step 1 value | gradually falling | sharpening; whether it collapses is step 4 | **0.34 → 0.08** (−76%), still falling ⚠️ |
| KL to the start | 0 | small, rising (~1e-3–1e-2) | lr 1e-5, LoRA, 100 steps | **0.056** ❌ (higher) |
| Clip fractions | 0 | low (< ~2%), mostly in updates 2–4 | small learning rate | **~0.1%** ✅ |
| Health metric | | ≈ 0 every step | the invariant | **exactly 0 at every step** ✅ |
| Step time | | ~40–60 s; ~1.5–2 h total | M0 throughput | **53 s**; 2 h 22 m (micro-batch 4) ✅ |

**Uncertainties.** The learning rate (flat reward after ~30 steps → too low; plunging entropy and degrading outputs → too high). Noise: one seed and 200 evaluation questions give about ±3.5 points on the evaluation curve.

**Success criteria.** (1) Completes 100 steps without running out of memory, health metric ≈ 0. (2) Held-out sampled pass@1 improves by more than 5 points. (3) Format rate above 95%. (4) Truncation falls. (5) No sign of reward hacking: training reward and held-out accuracy rise together; unparseable rate stays ~1%.

**Before the long run:** see the GPU smoke test below. The first step of the real run doubles as the memory check: peak GPU memory should stay below ~15 GB (16 GB card); if it runs out of memory, use `--micro-batch-size 4`.

## 2026-10-06 · GPU smoke test (RTX 4070 Ti SUPER, 16 GB)

README smoke command (2 questions × 4 samples, 2 updates, micro-batches of 4, 2 steps), code at `dd3f832`, no uncommitted changes; torch 2.14.1+cu130. Result: `results/train/smoke/`. **Health metric exactly 0.0** at both steps (on CUDA the no-gradient and gradient scoring passes match exactly; the Mac gave 6.5e-5). Ratio range 0.78–1.39 with zero high-clip fraction (tokens above 1.2 had Â < 0, the harmful direction, which is never clipped; large ratios come from low-probability tokens). KL 2–3e-4. Peak GPU memory 6.4 GB at micro-batch 4; the logits-related part doubles at micro-batch 8, so ~11–12 GB is expected for the real run, within the 16 GB card. Speed: rollout 7–9 s for 8 completions, scoring 0.3 s, update 0.5 s; extrapolated ~40 s per step at full size and ~1.75–2 h for the 100-step run including evaluations.

## 2026-10-06 · Step 3 · `vanilla_s0`: results

**Run.** `scripts/train.py --preset vanilla --micro-batch-size 4` (micro-batches of 8 ran out of GPU memory: the fp32 log-softmax over the 151,936-entry vocabulary is kept for the backward pass). Code at `0a78f2a`, no uncommitted changes. 100 steps, 25,600 completions, 7.47M generated tokens, 2 h 22 m, peak 7.78 GiB. Results: `results/train/vanilla_s0_20261006_154502/`; plots: `results/plots/vanilla_s0/`. Predictions vs results are filled in above.

| Final evaluation (all 1,319 test questions) | Baseline | Step 100 | Change |
| --- | --- | --- | --- |
| Greedy accuracy | 47.5% | 51.6% | +4.1 |
| Sampled pass@1 | 31.5% | 49.8% | +18.3 |
| pass@8 | 68.1% | 77.3% | +9.2 |
| Sampled format rate | 77.9% | 96.7% | +18.8 |
| Sampled truncation | 9.9% | 3.5% | −6.4 |

**Success criteria: all met.** (1) 100 steps, health metric exactly 0. (2) Sampled pass@1 +18 points. (3) Format 96.7%. (4) Truncation 9.9% → 3.5%. (5) Training reward (0.45 → 0.68) and held-out pass@1 (0.32 → 0.52) rose together; unparseable rate averaged 0.8%.

**Lessons.**
1. **Most of the gain is sharpening, not new ability.** Greedy +4, sampled +18; the greedy–sampled gap fell from 16 to 2 points while entropy fell 76%. GRPO mainly made T = 1 sampling behave like the model's best guess (fewer drifting, unboxed and truncated answers).
2. **pass@8 rose because the base model lost answers to format and drift** (22% unboxed, 10% truncated at T = 1). The "RL doesn't raise pass@k" result concerns large k on cleanly formatted models; testing it would need something like pass@64.
3. **Zero-variance groups took over faster than predicted.** By steps 90–100, ~37% of groups were all correct and ~10% all wrong, so nearly half of each batch gave no gradient (mixed 72% → ~50%). Every question was new (first epoch), so this is real improvement. This is the problem Dynamic Sampling targets.
4. **Entropy is still falling, and greedy accuracy on the 200-question curve peaked at 57.5% (step 70) and ended at 52%.** With one seed and 200 questions this may be noise, but "does entropy collapse and accuracy then degrade?" is step 4's question.
5. **Clipping is rare here (~0.1% of tokens),** so a Clip-Higher run at these settings (lr 1e-5, 4 updates per rollout) would likely look identical to vanilla. Clip-Higher's effect should grow with more updates per rollout: the planned Clip-Higher × updates-per-rollout experiment tests exactly this.

**Compared with rayyy's GRPO baseline (32% on 100 questions at 256 tokens):** 51.6% greedy / 49.8% pass@1 on the full test set at 512 tokens. The gap is large enough to check before continuing (next entry).

## 2026-10-06 · Replication of rayyy's setup: plan and predictions (written before the run)

**Why.** Our numbers differ a lot from rayyy's (base 21% / format 34%; GRPO 32%). The hypothesis is that their 256-token budget (training and evaluation) truncates most answers (this model's greedy median is 296 tokens). If our pipeline reproduces their numbers under their settings, our pipeline is consistent and the difference is the setup, not a bug.

**Setup (matching their config.py).** `--preset vanilla --run-name rayyy_repo_s0 --max-new-tokens 256 --questions-per-step 2 --samples-per-question 8 --num-minibatches 1 --micro-batch-size 8 --lora-r 32 --lora-alpha 32 --lora-dropout 0.05 --eval-questions 100 --eval-samples 4`: 16 completions per step, one update per rollout, learning rate 1e-5, β 0, 100 steps. Differences that remain: system prompt wording; their 100 evaluation questions vs our random 100 from the test set; their near-greedy T = 0.01 vs our greedy; their answer checker; T4 fp16/fp32 vs our bf16.

All predictions are for `rayyy_repo_s0` (none come from `vanilla_s0`, which trained at 512 tokens). Table reorganized after writing to separate the two models; the predicted values are unchanged.

**A. The untrained model under a 256-token budget** (step 0 of the replication run). Checkable two ways: the replication run's step-0 evaluation (100 questions), and a 256-token cut applied to the existing baseline completions (all 1,319 questions, no GPU needed).

| Metric | rayyy | Predicted | Reasoning | Result |
| --- | --- | --- | --- | --- |
| Greedy accuracy | 21% | ~20–25% | most greedy answers exceed 256 tokens and lose their box | **23.0%** ✅ (256-token cut on all 1,319 baseline completions) |
| Greedy format rate | 34% | ~30–40% | same | **33.5%** ✅ |

**Part A confirmed (2026-10-06).** Applying a 256-token cut to the baseline completions: **67.3% of greedy answers exceed 256 tokens**; greedy accuracy 23.0% and format 33.5% (rayyy: 21% / 34%, on 100 questions with about ±4 points of noise); sampled pass@1 16.1%, pass@8 39.5%. Our pipeline reproduces their baseline: the gap to our 47.5% is the token budget, not a bug. Under a 256-token budget, two thirds of answers get reward 0 for length alone, so GRPO's strongest signal there is to finish sooner, consistent with their format rate rising 34% → 76% and average length 189. *(Correction, 2026-10-07: their 76% / 189 are not like-for-like. Their reward adds +0.2 for any box; see the results entry below.)*

**B. After 100 steps of GRPO trained at 256 tokens with rayyy's settings** (step 100 of the replication run). Only the replication run can check these.

| Metric | rayyy | Predicted | Reasoning | Result |
| --- | --- | --- | --- | --- |
| Greedy accuracy | 32% | ~28–36% | GRPO learns to finish within 256 tokens; ±5 points of noise on 100 questions | **33%** ✅ (26% at step 0 on the same 100; full test 28.3%) |
| Format rate | 76% | ~70–85% | same | **47%** ❌ (full test 43.2%) |
| Mean length | 189 | ~180–210 tokens | the 256 budget pushes length down | **222** ❌ (last step's training rollouts, which is what rayyy's 189 also is; 237 over the last 10 steps) |
| Health metric | — | **> 0** (not exactly 0) | LoRA dropout 0.05 changes the forward pass between scoring passes (as predicted in the LoRA session) | **> 0** ✅ on 99 of 100 steps: median 0.35, max 0.84; step 1 exactly 0 |
| Runtime | ~40 min (T4) | ~30–40 min | 16 completions per step at ≤ 256 tokens | **29 min** ✅ |
| Clip fraction | — | **> 0, entirely from dropout noise** (added before the run) | with one update per rollout ρ would be exactly 1 and nothing could be clipped; `logp_old` is scored with dropout off, `logp_new` with dropout on | **> 0** ✅ on 60 of 100 steps, mean 0.06% of tokens |

A cheaper check first: applying a 256-token cut to the existing baseline completions (counting answers longer than 256 tokens as wrong and unboxed) should already give roughly 21% / 34% for greedy.

## 2026-10-07 · Replication of rayyy's setup: results

**Run.** The command above, code at `d8d5373`, no uncommitted changes. 100 steps, 1,600 completions, 29 min. Results: `results/train/rayyy_repo_s0/`. Predictions vs results are filled in above.

| Final evaluation (all 1,319 test questions, 256-token budget) | Untrained (256-token cut) | Step 100 | Change |
| --- | --- | --- | --- |
| Greedy accuracy | 23.0% | 28.3% | +5.3 |
| Greedy format rate | 33.5% | 43.2% | +9.7 |
| Greedy truncation | 67.3% | 59.1% | −8.2 |
| Sampled pass@1 | 16.1% | 24.8% | +8.7 |
| pass@8 | 39.5% | 51.3% | +11.8 |

**Verdict: accuracy replicates (33% vs 32%), format rate (47% vs 76%) and length (222 vs 189) do not.** It's not a bug in our code. Rereading rayyy's code found three differences my first audit missed:

1. **Their reward includes a format bonus.** `score_answer` returns correctness + 0.2 for any well-formed `\boxed{}` (`format_weight = 0.2`, on in every preset). Their reward curve confirms it: values like 0.0125 = 0.2 / 16 (one boxed wrong answer out of 16) and 1.2. Under a 0/1 reward a boxed wrong answer and a truncated one both score 0, so nothing directly says "finish and box". Under theirs, boxing beats truncation, which pushes format up and length down. Their "GRPO" row is GRPO plus format shaping.
2. **Two optimizer steps per training step.** Their loop calls `optimizer.step()` once per question group (2 groups of 8), so they took 200 Adam steps to our 100. Adam moves each weight by about the learning rate per step whatever the gradient's size, so their adapter moved about twice as far. Each group's `logp_old` is recomputed right before its own step, so ρ is still 1 apart from dropout.
3. **Qwen's sampling defaults leak into their generation.** They pass `temperature=1.0, top_k=50` but not `top_p` or `repetition_penalty`, so the model's `generation_config` (top-p 0.8, repetition penalty 1.1) still applies: the trap from [[Decoding and Sampling Parameters]]. Their samples are shorter and loop less, so they produce more boxed answers to learn from. It's also slightly off-policy: samples come from the filtered distribution, log-probs from the unfiltered one. Their evaluation has the same leak, but at baseline it didn't matter (34% vs our 33.5%).

Also, **their "average length 189" is the last training step's rollout mean** over 16 samples under that filtered sampler, not an evaluation number. Their reported clip fraction (0.0) and final reward come from that same last step.

**Lessons.**
1. **Read the code that computes the reward before comparing numbers.** The same algorithm name hid a different reward. The config table I audited first didn't show it.
2. **A format bonus can buy format with wrong answers.** Accuracy among boxed answers (accuracy ÷ format rate): untrained 69% (full test), ours after training 70% (33 / 47), rayyy 42% (32 / 76, down from 62% at their baseline). Their extra boxes were mostly wrong answers, consistent with the bonus paying for boxing a guess: a mild form of [[Reward Hacking]].
3. **The policy barely moved.** Entropy 0.28 → 0.25, KL at most 0.008, training-sample length flat around 235. 100 updates × 16 completions is little training; `vanilla_s0` had 400 updates × 256 completions and its entropy fell 0.34 → 0.08.
4. **Dropout moves ρ a lot but rarely enough to clip.** The health metric (each step's largest |log ρ|) has a median of 0.35 and a maximum of 0.84, so dropout alone changed one token's probability by up to e^0.84 ≈ 2.3×. Yet only 0.06% of tokens were clipped.

## 2026-10-07 · Format-bonus run: plan and predictions (written before the run)

**Why.** To test whether the +0.2 format bonus explains the format and length gap. Code: `format_weight` option added at `18f3adc` (default 0, so earlier runs are unchanged); the bonus counts any complete box, and accuracy and the group shares stay correctness-based. New metric `groups/nonzero_variance`: the share of groups whose rewards differ, i.e. that produce a gradient.

**Setup.** The `rayyy_repo_s0` command plus `--format-weight 0.2`, run name `rayyy_repo_fmt02_s0`. Same seed, so the first rollout draws the same questions and, up to GPU nondeterminism, the same samples; only the reward differs. The other two differences (2 optimizer steps per training step, the leaked sampler) stay unmatched on purpose: one change at a time.

| Metric | `rayyy_repo_s0` (no bonus) | rayyy | Predicted | Reasoning | Result |
| --- | --- | --- | --- | --- | --- |
| Greedy format rate (100 questions, step 100) | 47% | 76% | ~60–80% | all-wrong groups with mixed boxing now give a gradient toward finishing and boxing | |
| Greedy accuracy | 33% | 32% | ~28–38% | the bonus doesn't reward correctness; finishing in time rescues a few correct answers | |
| Accuracy among boxed answers | 70% | 42% | ~45–60% | most of the extra boxes are wrong answers | |
| Training-sample length (last 10 steps) | 237 | 189 (last step) | ~200–225 | a box requires stopping before 256 tokens | |
| `groups/nonzero_variance` (steps 1–10) | ~0.6 (equal to mixed) | — | ~0.8–0.9 | an all-wrong group now has signal whenever some answers box and some don't | |
| Runtime | 29 min | ~40 min (T4) | ~30 min | same work per step | |

**Decision rule.** Format ≥ ~65%: the bonus explains most of the gap, and the replication is done. Format below ~55%: the other differences matter more; next, match two optimizer steps per training step (`--num-minibatches 2`).

## Next

Run `rayyy_repo_fmt02_s0` and fill in its Result column; then step 4 (run vanilla GRPO longer, at 512 tokens, until it fails).
