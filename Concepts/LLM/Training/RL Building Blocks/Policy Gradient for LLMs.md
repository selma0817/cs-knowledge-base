---
date: 2026-09-29
tags:
  - llm
  - post-training
  - reinforcement-learning
  - policy-gradient
  - interview
aliases:
  - policy gradient
  - REINFORCE
  - per-token log-probs
  - log-probability of a response
  - credit assignment
  - 策略梯度
---
**Policy gradient** is the core RL update for LLMs: the model generates its own answers, a checker scores them, and training **raises the log-probability of every token in better-than-average answers and lowers it in worse-than-average ones**, weighted by how much better or worse each answer was. GRPO, PPO and DAPO are all this update plus safety mechanisms ([[Policy Ratio and Clipping]]).

## Why RL after SFT

- **SFT** imitates a demonstration: `loss = −Σ log π(token)` over a human-written answer, with every token weighted +1.
- **RL with verifiable rewards** needs no demonstration. The model makes its own attempts, a checker scores them (for example, "is the final answer correct?"), and training pushes the model toward what scored well. It can find solutions nobody wrote down, and it learns from its own kinds of mistakes.

## Log-probability of a response

```text
log π(o | q) = Σₜ log π(oₜ | q, o₁ … oₜ₋₁)
```

- Each term is **one decision the model made**: the probability it gave to the token it actually produced, given the question and every earlier token.
- **Why logs:** multiplying hundreds of probabilities below 1 underflows toward zero, and logs turn the product into a sum. More importantly, the gradient formula itself contains `log π` (see below).
- RL losses use the **per-token** log-probs, not only their sum.

### Generating vs scoring

```text
GENERATE  (sampling, token by token, no gradients)
  q → o₁ → o₂ → … → o_T              ← the text is produced ONCE and stored

SCORE  (one forward pass over the fixed text, called "teacher forcing")
  input:  [ q tokens ][ o₁ … o_T ]
  logits at every position                          [seq_len × vocab_size]
  position t predicts token t+1 → log_softmax → take the entry for the token actually there
  keep only the response positions → per-token log-probs      [T]
```

Any model can score any fixed text. That is how the current model, the rollout snapshot (π_old) and the reference model (π_ref) can all give log-probs for the **same stored answer** without generating it again.

### Computing per-token log-probs in practice

These log-probs feed `logp_old`, `logp_ref` and `logp_new`; small errors in them become fake policy movement in ρ ([[Policy Ratio and Clipping]]).

```text
index:      0   1   2   3   4   5   6           7    8    9
input_ids: [p1  p2  p3  a1  a2  a3  <|im_end|>  pad  pad  pad]     right padding
            └ prompt ┘  └── completion ───────┘

logits[:, :-1] scores input_ids[:, 1:]        output at t predicts token t+1
scored tokens:  p2  p3  a1  a2  a3  <|im_end|>  pad  pad  pad
loss mask:      0   0   1   1   1   1           0    0    0
```

- **Shift by one:** `logits[:, :-1]` pairs with `input_ids[:, 1:]`. The last output has nothing to score; the first token is never scored.
- **Mask:** every **completion** token counts (each is a decision; all share the answer's Â), **including the end token**; prompt and padding don't. Masking the end token means "stop here" is never reinforced, so the model can't learn to stop (a classic bug in SFT too). Build the mask from the completion length (through the first end token), not from `token != pad_token_id`: for Qwen the pad token `<|endoftext|>` is also an end token.
- **Gather immediately:** `logp = logit[token] − logsumexp(logits)`, per micro-batch, in **fp32**. This avoids the full `[batch, tokens, 151,936]` log-softmax tensor ([[LoRA and QLoRA]]).
- **Precision:** ρ = exp(logp_new − logp_old) compares two nearly equal numbers. bf16's rounding step is ~0.125 near a logit of 20, so an error of 0.06 would read as ρ ≈ 1.06, a fake 6% move against a ±20% clip band. Compute `logp_old` and `logp_new` with the **same code path** (dtype, padding, batching), and recompute `logp_old` with a scoring pass instead of taking `generate`'s scores (incremental KV-cache decoding rounds differently).
- **Padding for scoring:** use right padding (real tokens start at position 0, as in `generate`) or pass `position_ids`. With RoPE, attention depends only on relative position, so a uniform shift from left padding cancels mathematically, but it still changes rounding.
- **Invariant check:** at the first optimizer step after a rollout, `max |logp_new − logp_old|` should be ≈ 0. Test it and log it; if it isn't, the shift, mask, precision or padding is wrong.

## The update

```text
loss = − Σ over answers  Σₜ  A · log π_θ(oₜ | q, o₍<ₜ₎)
```

`A` is the **advantage**: how much better than expected this answer scored ([[Advantage Estimation]]). Gradient descent on this loss raises `log π` wherever A > 0 and lowers it wherever A < 0, in proportion to |A|.

**Where it comes from (REINFORCE):** the identity ∇π = π · ∇log π gives

```text
∇ E[R] = E[ R · ∇ log π(o | q) ]
```

So the gradient of the expected reward can be estimated from sampled answers: weight each answer's `∇ log π` by its score. Subtracting a baseline (R − b) keeps the expected gradient the same but reduces its variance. R − b is the advantage.

## What "push up" actually changes: the weights

- There is no table of token probabilities to edit. A probability is **computed by the network from its weights**. "Push up log π('5' | q, 'The answer is')" means: compute the gradient of that log-prob with respect to every trainable weight, and move those weights a small step in that direction.
- With **LoRA**, only the small adapter matrices are trainable. The base model's weights stay frozen.
- The weights are **shared by every input**, so the update changes the model's behavior on all questions. The goal is that it learns "reasoning that leads to correct answers", not "2+3 is 5". That is generalization, and it is also why large steps are dangerous: the side effects spread everywhere.

## Credit assignment with outcome rewards

An outcome reward scores only the final answer, so **every token of a correct answer gets the same push**, including a wrong intermediate step that happened to lead to the right answer.

Statistics resolves this on average. **Tokens that good and bad answers share get opposite pushes that cancel. The tokens where the answers differ get the net push.** See the worked example in [[GRPO]].

The alternative is a **process reward model** that scores each step. It gives more signal, but it is expensive to build and easy to game. DeepSeek-R1 used outcome rewards only.

## SFT vs policy gradient

| | SFT | Policy gradient |
| --- | --- | --- |
| Data | human-written answers (fixed dataset) | the model's own answers (new ones every batch) |
| Weight per answer | +1 for every token | the advantage A, which can be negative |
| Needs | demonstrations | only a way to score answers |
| After a bad step | the next batch corrects it (the data is fixed) | a worse model generates worse data, which can snowball into collapse |

> Policy gradient is **SFT on the model's own samples, with each sample weighted by its advantage**, where a negative weight pushes down.

## Why RL is more fragile than SFT

> In SFT the dataset is fixed, so a bad step gets corrected by the next batch. In RL the **model generates its own training data**. A bad step produces a worse model, which generates worse data, which leads to worse updates. The model can collapse (repeated phrases, empty output) and never recover. This is why RL algorithms limit step size ([[Policy Ratio and Clipping]]).

## Common misconceptions

- **"Training log-probs come from generating the answer again."** No. The stored text is scored in one forward pass.
- **"We push token probabilities directly."** No. Only the weights change, and the probabilities follow.
- **"Logs are used only for numerical stability."** No. The gradient identity ∇π = π·∇log π is why every RL loss is written in `log π`.
- **"Outcome rewards can't teach which step was good."** They can, statistically: tokens shared by good and bad answers cancel, and the tokens where answers differ get the push.

## Interview summary

> Policy gradient trains an LLM on its own sampled answers: score each answer, compute an advantage (how much better than expected it scored), and minimize `−Σ A · log π(token)`, which raises the per-token log-probs of better-than-average answers and lowers those of worse ones. It comes from REINFORCE: ∇E[R] = E[R · ∇log π], where subtracting a baseline reduces variance without biasing the gradient. Log-probs for a stored answer come from one teacher-forced forward pass, so any model can score the same text. Updates change the shared weights (only the adapters, with LoRA), so they generalize across questions, but side effects spread too. With outcome-only rewards, credit assignment happens statistically: shared tokens cancel between good and bad answers. RL is more fragile than SFT because the model generates its own training data, so bad steps compound.

## Related notes

- [[GRPO]]
- [[Advantage Estimation]]
- [[Policy Ratio and Clipping]]
- [[LLM Training MOC]]
