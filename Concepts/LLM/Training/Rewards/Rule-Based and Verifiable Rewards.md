---
date: 2026-10-01
tags:
  - llm
  - post-training
  - reinforcement-learning
  - reward
  - rlvr
  - interview
aliases:
  - rule-based reward
  - verifiable reward
  - RLVR
  - 规则奖励
  - answer extraction
  - format reward
---
A **rule-based (verifiable) reward** scores a completion with code that checks it against ground truth, for math "does the final answer equal the gold answer?", instead of with a learned reward model. RL with such rewards is called **RLVR** (reinforcement learning with verifiable rewards). Every advantage in [[GRPO]] comes from this number, so **anything the checker gets wrong, the model learns.**

## The pipeline

```text
dataset answer ──extract gold──▶ "72" ──────────┐
                                                ├─▶ is_equivalent ─▶ 1.0 / 0.0
completion ──extract answer──▶ "72" or None ────┘
              (last complete \boxed{})      (normalize, compare exactly)
```

Split into small functions so a failing test points at one step. Implemented in the grpo-dapo project as `extract_gold`, `extract_answer`, `parse_number`, `is_equivalent`, `compute_reward`.

## Design decisions (GSM8K)

| Decision | Choice | Why |
| --- | --- | --- |
| Answer format | final answer in `\boxed{...}`, requested in the prompt | Free text forces the checker to *guess* which number is the answer ("4 × 3 = 12 … 12 − 5 = 7 … 7 + 5 = 12": the last number is 12, the answer is 7). Guesses add noise and invite hacking |
| Correct number, no box | reward 0 (strict) | unambiguous; the model learns the format quickly (see below) |
| Several boxes | the last *complete* one counts | the model's final decision; spamming boxes doesn't help |
| Equality | the same exact number (`Fraction`, never `float`) | `18 = 18.0 = 1,000/1000`; `float("12345678901234567891") == float("12345678901234567890")` is True |
| Malformed model output | fail closed: `None` / `0.0`, never raise | a crash inside the reward stops the training run |
| Malformed gold answer | validate every gold once at load time | otherwise it silently scores every completion 0, giving that question Â = 0 with no warning |

## Extracting the last `\boxed{}` in one pass

Nested braces need a stack, not a regex. Scan left to right; push each `{` with a **tag**: the start of its `\boxed` if the text there is exactly `\boxed{`, otherwise `None`. A `}` pops the most recent open `{`. If the popped entry has a tag, a box just closed and is a candidate; keep the candidate whose box *started* latest. `{` entries left open at the end (a cut-off box) are ignored.

```text
\boxed{\text{18}}
index 6  "{" after \boxed  push (6, box@0)      stack [(6, box@0)]
index 12 "{" after \text   push (12, None)      stack [(6, box@0), (12, None)]
index 15 "}"               pop (12, None) → plain, ignored
index 16 "}"               pop (6, box@0) → box closed → content [7:16] = "\text{18}"
```

- Scanning forward from *every* `\boxed{` is quadratic: 10,000 unclosed braces take minutes instead of milliseconds.
- A recursive matcher hits Python's recursion limit on deeply nested input.

## Normalizing and comparing numbers

- Remove `\$`, `$`, `%`; turn LaTeX separators (`1,\!000` is the MATH dataset's convention, also `1{,}000`, `1\,000`) into commas; remove commas **between digits**; map the Unicode minus `−` (U+2212) to `-`.
- Match digits with `[0-9]`, not `\d` (which also matches `٣` and other non-ASCII digits).
- Require **exactly one number**, so hedging (`\boxed{12 or 72}`) gets `None`.
- Python refuses to convert decimal strings longer than **4,300 digits** to `int` (a security limit, CVE-2020-10735), so a degenerate "1111…" answer raises `ValueError`; catch it and fail closed.

**Levels of equivalence.** Robust checkers try cheap levels first:

| Level | Catches | Example |
| --- | --- | --- |
| String equality (after cleanup) | identical non-numeric answers | `\frac{1}{2}` vs `\frac{1}{2}`, `(1, 2)` |
| Exact numeric | the same number written differently | `18` vs `18.00`, `1,000` vs `1000` |
| Symbolic (`math-verify`) | the same value in different forms | `\frac{1}{2}` vs `0.5`, `\frac{\sqrt2}{2}` vs `\sqrt{2}/2` |

GSM8K gold answers are integers by design, so the numeric level alone gives identical results there; MATH needs all three.

## What strict format does to training

A question solved correctly by all 8 answers, but only 3 boxed: rewards `[1,1,1,0,0,0,0,0]`, p = 3/8:

```text
mean = 0.375, std = √(p(1−p)) = 0.484
Â(boxed) = +1.29   Â(unboxed) = −0.77      3 × 1.29 = 5 × 0.77: the advantages sum to 0
```

Because Â sums to 0, tokens that **all** answers share (in the same context) get pushes that cancel exactly. The net push lands where the answers differ: **writing `\boxed{}`**. Strict format teaches the format through the same mechanism that assigns credit in [[Policy Gradient for LLMs]].

If the model **never** boxes, every reward is 0, Â = 0, and that question gives no gradient: a **cold start**. How often a group of G = 8 has no boxed answer at all:

| Base format rate | Groups with no boxed answer (1 − rate)⁸ |
| --- | --- |
| 34% | 3.6% |
| 10% | 43% |
| 5% | 66% |

> **Before training, measure the base model's format rate with the exact prompt.** If it's low, fix the prompt (Qwen's recommended math prompt is "Please reason step by step, and put your final answer within \boxed{}."), add few-shot examples, do a short SFT warm-up, or add a small format reward.

## Partial credit

Giving 0.5 for answers within ±1: group `[72, 71, 50, 50]` → rewards `[1, 0.5, 0, 0]`, mean 0.375, std 0.415, so **Â(71) = +0.30**: GRPO pushes the model *toward a wrong answer*. For exact tasks (arithmetic), close is still wrong. Partial credit fits when sub-goals are **independently verifiable**: the fraction of unit tests a program passes, or the parts of a multi-part question.

## Reward values don't matter under group normalization

If R′ = aR + b with a > 0, then mean′ = a·mean + b and std′ = a·std, so

```text
Â′ = (aR + b − a·mean − b) / (a·std) = (R − mean) / std = Â
```

So `{0, 1}` and DAPO's `{−1, +1}` (a = 2, b = −1) give **identical** advantages in GRPO: `[1,0,0,1]` and `[1,−1,−1,1]` both give `[1,−1,−1,1]` with the population std (or ±0.866 for both with the n−1 std; use the same convention for both). The values matter only when:
- there is **no std normalization** (e.g. Dr. GRPO): the scale then acts like a learning-rate multiplier;
- there is **no baseline** at all: with `{0, 1}`, wrong answers are never pushed down;
- the reward **combines components**: the gap between correct and wrong (1 or 2) sets how much a length penalty or format bonus matters relative to correctness.

## Rule-based vs learned reward models

| | Rule-based checker | Learned reward model |
| --- | --- | --- |
| Works for | verifiable tasks (math, code with tests) | open-ended tasks (helpfulness, style) |
| What it measures | the actual ground truth | a learned approximation of human preference |
| How it gets hacked | **bugs in the checker** (extraction, parsing) | the policy finds inputs the model scores wrongly: length, confident tone, sycophancy ([[Reward Hacking]]) |
| Cost | a few functions; no GPU memory | a whole model in memory during training |

Rule-based rewards are harder to hack, not impossible: the attack surface is small and testable, but every checker bug is an exploit (see [[Reward Hacking]]).

## Common misconceptions

- **"Let the model answer in any format; we can always convert."** No. Without a required format the checker has to guess which number is the answer.
- **"Strict format slows learning."** Only if the base format rate is very low (cold start). Otherwise it teaches the format quickly. Measure it first.
- **"`parse(pred) == parse(gold)` is enough."** No. Two failed parses give `None == None`, which rewards garbage. Require both to parse.
- **"Rewards of 0/1 vs −1/+1 change GRPO."** No. Group normalization cancels any positive scaling and shift.
- **"Partial credit is gentler, so it's better."** Not for exact tasks: it gives wrong answers positive advantages.
- **"Rule-based rewards can't be hacked."** Checker bugs are exploitable.

## Interview summary

> A rule-based (verifiable) reward checks a completion against ground truth in code. For math: extract the final answer (require `\boxed{}`, take the last complete box with a one-pass brace stack), normalize it (thousands separators including LaTeX forms, currency, Unicode minus), and compare exactly (fractions, not floats; for symbolic answers add string and `math-verify` levels). Require exactly one number to block hedging, fail closed on bad model output, and validate gold answers at load time. Strict format works because advantages sum to zero within a group: shared tokens cancel and the push lands on the box, but if the base model never uses the format the group has zero variance and nothing is learned, so measure the format rate first. Partial credit gives wrong answers positive advantages on exact tasks. Under group normalization the reward's scale and offset don't matter ({0,1} ≡ {−1,+1}). Rule-based rewards are harder to hack than learned reward models, but checker bugs are still exploitable.

## Related notes

- [[Reward Hacking]]
- [[GRPO]]
- [[Advantage Estimation]]
- [[Policy Gradient for LLMs]]
- [[DAPO]]
- [[LLM Training MOC]]
