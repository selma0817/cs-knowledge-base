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

## Next

Step 3: the GRPO core (`Policy` class with LoRA and the reference model via a disabled adapter, log-probs, group advantage, clipped loss, training loop, held-out evaluation every N steps, run metadata and per-step metrics).
