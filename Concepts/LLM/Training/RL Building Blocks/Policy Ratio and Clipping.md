---
date: 2026-09-29
tags:
  - llm
  - post-training
  - reinforcement-learning
  - ppo
  - grpo
  - interview
aliases:
  - policy ratio
  - importance ratio
  - PPO clipping
  - clipped objective
  - clip-higher
  - 策略比率
  - 重要性采样比
  - π_old
---
The **policy ratio** ρ = π_θ(token) / π_old(token) measures, **for each token**, how much more or less likely the model being trained is to produce that token than the snapshot that generated the rollout. **Clipping** limits the ratio to [1−ε, 1+ε] in the helpful direction, so one batch of rollouts can be reused for several gradient steps without any single token being pushed too far. PPO introduced both; GRPO reuses them; DAPO changes the upper bound (Clip-Higher).

## Why a ratio exists: reusing rollouts

Generating rollouts is the expensive part of RL training, so each batch is reused for several gradient steps:

```text
repeat:
  1. ROLLOUT  (no gradients; the current weights are frozen as π_old)
       for each question: generate G answers
       score each answer → reward → Âᵢ                          ← once
       one forward pass → logp_old for every token               ← once
       STORE: { question, answer tokens, Âᵢ, logp_old per token }

  2. UPDATE  (several optimizer steps on the stored batch)
       forward pass of the CURRENT model over the SAME stored text → logp_new per token
       ρ = exp(logp_new − logp_old)                               ← per token
       per-token clipped term → average → loss
       loss.backward(); optimizer.step()                          ← weights change

  3. throw the batch away; the updated model becomes the new π_old
```

- **Nothing is generated again.** Both models **score the same stored text**: "how likely would you be to produce this exact token, after this exact prefix?"
- After the first optimizer step, the model has changed, so the stored answers are slightly stale. The ratio measures by how much, token by token.

## Definition

```text
ρₜ = π_θ(oₜ | q, o₍<ₜ₎) / π_old(oₜ | q, o₍<ₜ₎) = exp(logp_new − logp_old)
```

ρ = 1.3 means the current model is 30% more likely than the snapshot to produce this token here. **ρ is not a reward.** Rewards are per answer and come from the checker; ρ is per token and comes from comparing two models.

## The clipped objective

```text
objectiveₜ = min( ρₜ · Â ,  clip(ρₜ, 1−ε, 1+ε) · Â )          ε is typically 0.2
```

A token is **pushed** when `min` picks `ρ·Â`: the term depends on the weights, so gradient flows. It has **stopped** when `min` picks the clipped constant (1.2·Â or 0.8·Â): the term can't change, so the gradient is zero.

| | ρ = 0.7 | ρ = 1.0 | ρ = 1.1 | ρ = 1.3 |
| --- | --- | --- | --- | --- |
| **Â = +1** (good token, want ρ ↑) | 0.7 · **pushed ↑** | 1.0 · pushed ↑ | 1.1 · pushed ↑ | 1.2 · **stopped** |
| **Â = −1** (bad token, want ρ ↓) | −0.8 · **stopped** | −1.0 · pushed ↓ | −1.1 · pushed ↓ | −1.3 · **pushed ↓** |

```text
Â = +1                                        Â = −1
obj                                           obj
1.2 ┤            ●━━━━━  stopped              −0.8 ┤━━━━━●              stopped
    │          ╱          (already 20%+            │       ╲
1.0 ┤       ╱              more likely)       −1.0 ┤          ╲         pushed ↓
    │    ╱   pushed ↑                              │             ╲
0.7 ┤ ╱                                       −1.3 ┤                ╲   still pushed ↓
    └──┬─────┬─────┬──▶ ρ                          └──┬─────┬─────┬──▶ ρ
      0.8   1.0   1.2                                0.8   1.0   1.2
```

> **Clipping stops a token only once it has moved far enough in the helpful direction. A token that moved the harmful way is never stopped.** That is why it is a `min`: it always keeps whichever version looks worse, so mistakes keep getting corrected, and the model can't gain credit by overdoing a good change.

The two edge cases in bold are the ones the `min` exists for:
- Â = +1, ρ = 0.7: a good token became less likely. The model moved the wrong way, so the push continues.
- Â = −1, ρ = 1.3: a bad token became more likely. Again the wrong way, and the push continues.

## The clipped objective, piece by piece

```text
                    ⎧ 1−ε   if ρ < 1−ε
clip(ρ, 1−ε, 1+ε) = ⎨ ρ     if 1−ε ≤ ρ ≤ 1+ε     inside the band: clip(ρ) = ρ, so both arguments of min are equal
                    ⎩ 1+ε   if ρ > 1+ε
```

Applying `min` separately for each sign of Â (multiplying by a negative Â reverses the order, e.g. −0.7 > −0.8):

```text
Â > 0:  L(ρ) = ρÂ          if ρ ≤ 1+ε
               (1+ε)Â      if ρ > 1+ε        ← clipped only at the TOP

Â < 0:  L(ρ) = (1−ε)Â      if ρ < 1−ε        ← clipped only at the BOTTOM
               ρÂ          if ρ ≥ 1−ε
```

The unclipped piece ρÂ contains the weights θ (through π_θ). The clipped piece (1±ε)Â is a constant. So each token's gradient is

```text
∇L = 𝟙[not clipped] · ρ · Â · ∇log π_θ(token)          using ∇ρ = ρ · ∇log π_θ

"not clipped" = (Â > 0 and ρ ≤ 1+ε)  or  (Â < 0 and ρ ≥ 1−ε)
```

> **"Clipped" means the formula no longer contains the weights, so its gradient is 0.** Each token's push is the plain policy gradient scaled by ρ, and it is switched off once the token has moved more than ε in the helpful direction.

`clip()` changing the number is not enough on its own. With Â = −1 and ρ = 1.25, clip gives 1.2, but `min(−1.25, −1.2) = −1.25` selects the unclipped term, so the token is still pushed. A clipped value only matters when `min` selects it.

| Â = −1, ε = 0.2 | ρ = 1.0 | ρ = 0.9 | ρ = 0.75 | ρ = 1.25 |
| --- | --- | --- | --- | --- |
| L | −1.0 | −0.9 | −0.8 (clipped) | −1.25 (not clipped) |
| Gradient factor 𝟙·ρ | 1.0 · pushed ↓ | 0.9 · pushed ↓ | **0 · stopped** | 1.25 · pushed ↓ |

## Worked example: one batch, three optimizer steps

Question "2+3=?" (correct answer: 5), G = 2, ε = 0.2, no KL. Probabilities are shown instead of log-probs, so ρ = p_new / p_old.

**1. Rollout: the old model W₀ samples answers.**

```text
input [Q]      → W₀: { is:.90 … }               sample "is"
input [Q, is]  → W₀: { 5:.30  6:.60  others:.10 } sample "5" (answer 1), "6" (answer 2)
```

Sampling (rather than always taking the most likely token) is what let a correct answer appear. With greedy decoding both answers would be "is 6", the std would be 0, and nothing would be learned.

**2–4. Reward, advantage, store.** R = [1, 0], so Â = [+1, −1]. The stored batch does not change until the next rollout:

| Answer | Tokens (written by W₀) | Â | p_old |
| --- | --- | --- | --- |
| 1 | `is`, `5` | +1 | is: .90, 5: .30 |
| 2 | `is`, `6` | −1 | is: .90, 6: .60 |

**5–7. Update. At every step the SAME stored tokens are fed into the current model, and their probabilities are looked up. The model never picks a token.**

| Optimizer step | Weights | p_new("5"), answer 1 | ρ("5") | p_new("6"), answer 2 | ρ("6") | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | W₀ | .30 | 1.00 | .60 | 1.00 | plain push: "5" ↑, "6" ↓, the two `is` cancel → W₁ |
| 2 | W₁ | .345 | 1.15 | .555 | 0.925 | both inside [0.8, 1.2], both pushed → W₂ |
| 3 | W₂ | .39 | **1.30** | .51 | 0.85 | "5" **clipped (stopped)**; "6" still pushed ↓ → W₃ |

ρ for `is` stays 1.00 throughout, because its two pushes cancel.

At step 2, W₁ still rates "6" above "5" (.555 vs .345). That doesn't matter: the term asks how likely W₁ is to produce **the stored token "5"**, not what W₁ would say itself.

**8. Next rollout.** The batch is discarded. W₃ becomes the new π_old and samples new answers, and it now produces "5" more often. **This is the only regeneration.** A regenerated answer is a new answer with no reward or Â yet, so it starts the next batch. It is never used to compute ρ in the current batch.

```text
W₀ ──SAMPLE──▶ answers ──checker──▶ R, Â ──store──▶ [fixed batch]
   step 1: W₀ reads batch → ρ = 1            → W₁
   step 2: W₁ reads batch → ρ = 1.15, 0.925  → W₂
   step 3: W₂ reads batch → "5" clipped      → W₃
W₃ ──SAMPLE──▶ new answers → next batch           ← the only regeneration
```

## One optimizer step per batch: clipping does nothing

If each rollout batch gets exactly **one** optimizer step, then during that step the weights are the same ones that computed `logp_old`. Same weights, same input, same token, so **ρ = 1 for every token**. That is inside [1−ε, 1+ε], so **clipping never activates**.

ρ *equals* 1 but isn't *stuck* at 1, so it still has a gradient:

```text
∇ρ = ∇π_θ / π_old                 π_old is a stored number, so it has no gradient
at this moment π_θ = π_old  ⇒  ∇ρ = ∇π_θ / π_θ = ∇ log π_θ
⇒ ∇(ρ · Â) = Â · ∇ log π_θ         (plain policy gradient)
```

> **With one optimizer step per rollout batch, the clipped objective reduces to plain policy gradient.** The ratio and clipping are still in the code, but they have no effect.

Consequences:
- **ρ ≠ 1 only if `optimizer.step()` has run since the rollout was generated.** Clipping matters only with several optimizer steps per rollout batch (several passes, or several mini-batches).
- **A Clip-Higher ablation with one step per batch tests nothing.** Moving the upper bound changes nothing if ρ is always 1, so any difference in the results is noise. For the ablation to mean something, split each rollout batch into mini-batches with one optimizer step each.
- In practice ρ can be slightly off 1 even with one step, when `logp_old` comes from a different code path (vLLM, different kernels or precision). This is called **train–inference mismatch**.

Setting ε only matters through the switch 𝟙[not clipped]. At ρ = 1 the switch is always on and the ρ scaling is 1, so ε appears nowhere in the gradient. That is exactly why changing ε, as Clip-Higher does, has no effect when every optimizer step is the first one after a rollout.

### Why the formula keeps ρ even when it equals 1

1. **The formula has to cover every setting.** With several updates per rollout (DAPO uses 16), ρ ≠ 1 from the second step on. ρ = 1 is the special case of the first step.
2. **Its value is 1, but its gradient is the policy gradient.** TRL writes the one-update case as π_θ / [π_θ]_no-grad: value 1, gradient ∇log π_θ. One loss function gives the correct update for 1 update per rollout or for 16.
3. **It is PPO's objective.** GRPO only changes how the advantage is computed, so reusing a batch for several updates, which needs the ratio and clipping, is always available.

## How many updates per rollout

It is a **hyperparameter**; nothing in the algorithm fixes it. Two different kinds of splitting are easy to confuse:

```text
rollout batch: 32 questions × 8 answers = 256 stored answers        (sampled once by W₀)
 ├── mini-batch 1 (64 answers) → optimizer.step()   ρ = 1
 ├── mini-batch 2 (64 answers) → optimizer.step()   ρ ≠ 1     (answers written by W₀, read by W₁)
 ├── mini-batch 3 (64 answers) → optimizer.step()
 └── mini-batch 4 (64 answers) → optimizer.step()   ⇒ 4 updates per rollout
       └── each mini-batch split into micro-batches of 8, only to fit in GPU memory
           (gradient accumulation: gradients are ADDED up, then ONE optimizer.step()
            → the weights don't change between micro-batches, so ρ doesn't either: it doesn't count)
```

> **Updates per rollout = number of mini-batches × number of passes over the batch (μ).** Micro-batches for memory don't count: they all see the same weights, so they never create new chances for clipping.

| Setting | Updates per rollout batch | Clipping |
| --- | --- | --- |
| GRPO in DeepSeekMath | 1 ("a single update following each exploration stage") | never acts |
| DAPO | 16 (512 questions × 16 answers per rollout, mini-batches of 512 answers) | matters a lot |
| TRL defaults | 1 (`num_iterations=1`, and one optimizer step per generation batch unless `steps_per_generation` is set above `gradient_accumulation_steps`) | never acts |

| | Few updates per rollout (1) | Many updates per rollout |
| --- | --- | --- |
| Generation cost per update | high: every update needs a fresh rollout | low: one rollout pays for many updates |
| How fresh the stored answers are | exactly the current model's (ρ = 1) | stale: they describe an older and older model |
| Clipping | never acts | acts, and clips more tokens with each extra update |
| Risk | slow learning | instability; over-fitting to one small batch of answers |

**Choosing it in practice:** start small (1–4) and watch
- **clip fraction**: the share of tokens clipped (TRL: `clip_ratio/low_mean`, `clip_ratio/high_mean`, `clip_ratio/region_mean`). When it gets large, many tokens have zero gradient, so later updates are mostly wasted and the model has already moved far. Use fewer updates or a lower learning rate.
- **approximate KL between π_old and π_θ** on the batch: how far the model moved during the reuse.
- **reward and entropy**: whether learning is steady or starting to become unstable.

How far the model moves per rollout is roughly learning rate × number of updates. DAPO can afford 16 updates because each of its mini-batches still holds 512 answers.

**Effect on Clip-Higher:** Clip-Higher only changes the switch for tokens with Â > 0 whose ρ lands between 1.20 and 1.28. At 1 update per rollout its effect is exactly zero. As updates per rollout grow, more good tokens drift past ρ = 1.2, so the difference from plain GRPO grows, visible first in the upper clip fraction. Whether that improves accuracy is an empirical question.

## Clip-Higher (DAPO)

Clip-Higher uses **separate lower and upper bounds**, typically ε_low = 0.2 and ε_high = 0.28, so the band becomes [0.8, 1.28]. Good tokens can then rise further before stopping.

The cap is **multiplicative**, so it holds back rare tokens far more in absolute terms. Within one batch, with ε = 0.2, a token at p_old = 0.5 can rise to 0.6 (+0.1), but a token at p_old = 0.01 only to 0.012 (+0.002). A rare token that appeared in a correct answer can barely grow, while already-likely tokens grow quickly. Why that matters (entropy collapse, exploration) is covered in [[DAPO]].

## Clipping vs KL

| | Clipping | KL penalty |
| --- | --- | --- |
| Compares against | **π_old**, the snapshot that generated *this batch*; resets every batch | **π_ref**, the original model before RL; never moves |
| Limits | the size of each step, per token, within one batch | total drift from the starting model |
| Applied as | a hard stop (gradient 0 past the bound) | a soft penalty (−β·KL in the objective); the further the drift, the higher the cost |

- **Clipping alone:** every step is small, but many small steps can add up to drifting anywhere, including into reward hacking or losing fluent language.
- **KL alone:** it only adds a cost and doesn't block a step, so one bad large step can still damage the model.

Think of clipping as a speed limit per step and KL as a rubber band tied to the starting point. How the KL term is estimated per token, and why DAPO removes it, are covered in [[KL Regularization and Reference Models]] and [[DAPO]].

## Common misconceptions

- **"ρ is the token's reward."** No. Rewards are per answer, from the checker. ρ is per token: π_θ / π_old.
- **"Computing the ratio means generating again with the new model."** No. The current model is fed the stored tokens and only looks up their probabilities; it never picks a token. Generating again happens only at the next rollout, which starts a new batch.
- **"Clipping stops large negative values."** No. It depends on direction, not sign. It stops good tokens that rose past 1+ε and bad tokens that fell below 1−ε, and never stops a token that moved the wrong way.
- **"Any ρ outside the band gets clipped."** No. Only when it leaves the band in the helpful direction. With Â = −1 and ρ = 1.25, `min` keeps the unclipped −1.25, so the token is still pushed.
- **"Clipping is always active in GRPO."** No. At the first optimizer step after a rollout ρ = 1, so clipping can only act from the second step on. With exactly one optimizer step per rollout (DeepSeekMath's reported setting, TRL's default), it never acts.
- **"If ρ is always 1 in some setting, it could be dropped from the formula."** No. Its value is 1, but its gradient ∇ρ = ∇log π_θ is what produces the policy-gradient update.
- **"Clipping and KL are redundant."** No. They compare against different models: π_old, which resets every batch, and π_ref, which never moves.

## Interview summary

> RL reuses each expensive rollout batch for several optimizer steps. The policy ratio ρ = π_θ/π_old = exp(logp_new − logp_old), computed per token by scoring the same stored text with both models, measures how far the current model has moved from the rollout snapshot. The PPO clipped objective min(ρÂ, clip(ρ, 1−ε, 1+ε)Â) stops a token once it has moved more than ε in the helpful direction (up for Â > 0, down for Â < 0), while the `min` keeps the gradient for tokens that moved the harmful way. With one optimizer step per rollout batch, ρ = 1 exactly, clipping never activates, and since ∇ρ = ∇log π at that point, the objective reduces to plain policy gradient. So clip-based ablations such as DAPO's Clip-Higher (ε_high = 0.28) only mean something with several optimizer steps per rollout (updates per rollout = mini-batches × passes; micro-batches for gradient accumulation don't count). DeepSeekMath reported one update per rollout, while DAPO uses 16. Because the cap is multiplicative, it holds back rare tokens most. Clipping bounds each step relative to π_old; the KL penalty bounds total drift relative to the fixed reference π_ref.

## Related notes

- [[Policy Gradient for LLMs]]
- [[Advantage Estimation]]
- [[GRPO]]
- [[DAPO]]
- [[KL Regularization and Reference Models]]
- [[LLM Training MOC]]
