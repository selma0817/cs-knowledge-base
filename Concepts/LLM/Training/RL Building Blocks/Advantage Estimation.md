---
date: 2026-09-29
tags:
  - llm
  - post-training
  - reinforcement-learning
  - grpo
  - interview
aliases:
  - advantage
  - group-relative advantage
  - baseline
  - 组内相对优势
  - 优势函数
  - zero-variance groups
---
The **advantage** of an answer is **how much better than expected it scored**: its reward minus a baseline, where the baseline estimates the expected reward for that question. The advantage sets both the direction (up or down) and the size of each answer's push in [[Policy Gradient for LLMs]]. GRPO's key idea is to get the baseline from a **group of samples of the same question** instead of from a trained critic.

## Why a baseline

With 0/1 rewards and no baseline (A = R):
- Correct answers get pushed up, and wrong answers get **no push at all**, so nothing is ever pushed down.
- Easy questions the model already solves keep getting pushed up, which wastes updates.
- The gradient has high variance.

Subtracting a baseline centers the pushes: **better than expected goes up, worse than expected goes down.** Any baseline that doesn't depend on the particular answer leaves the expected gradient unchanged and only reduces variance.

## Group-relative advantage (GRPO)

Sample G answers to the **same** question, score each, and normalize within the group:

```text
Âᵢ = (Rᵢ − mean(R₁…R_G)) / std(R₁…R_G)          one value per answer, shared by all its tokens
```

- **Why the same question:** questions differ in difficulty. A correct answer means less on an easy question than on a hard one. The group mean estimates "how well does the current model usually do on this question".
- **This replaces the critic.** PPO trains a separate value network to predict expected reward. GRPO gets the same kind of estimate by sampling, so it needs no extra model and no second training problem.

### Worked examples (divide by n for the std)

| Rewards | mean | std | Â |
| --- | --- | --- | --- |
| `[1, 0, 0, 1]` | 0.5 | 0.5 | `[+1, −1, −1, +1]` |
| `[1, 0, 0, 0]` | 0.25 | 0.433 | `[+1.73, −0.58, −0.58, −0.58]` |
| `[1, 1, 1, 0]` | 0.75 | 0.433 | `[+0.58, +0.58, +0.58, −1.73]` |

To compute the std: squared deviations → their **mean** → the **square root**. A common mistake is to stop at the *sum* of squared deviations.

### Closed form for 0/1 rewards

With **p** = the fraction of the group that is correct: mean = p, std = √(p(1−p)), so

```text
Â(correct) = +√((1−p)/p)          Â(wrong) = −√(p/(1−p))
```

| p | Â correct | Â wrong | Reading |
| --- | --- | --- | --- |
| 0.25 (hard question) | **+1.73** | −0.58 | the rare success is the surprise: big push up |
| 0.50 | +1.00 | −1.00 | success and failure equally informative |
| 0.75 (easy question) | +0.58 | **−1.73** | the rare failure is the surprise: big push down |

> **Surprising outcomes get large advantages, expected ones get small ones.**

### Two checks for your arithmetic

1. **The Â values in a group add up to 0**, because you subtracted the mean.
2. With the std computed by dividing by n, **the Â² values add up to G**. This check catches a wrong std; check 1 doesn't.

**n vs n−1:** PyTorch's `tensor.std()` divides by **n−1** by default. When testing your code against another implementation, match whichever convention it uses.

## Groups where every answer scores the same

If all G answers are correct (or all wrong), then std = 0 and every Rᵢ − mean = 0, so **Â = 0 for the whole group**. An ε in the denominator avoids dividing by zero, but the result is still 0.

- That question contributes **no gradient**. The G generations are wasted compute.
- As the model improves, more groups end up all-correct, so the number of useful samples per batch shrinks. This is one of the problems [[DAPO]] addresses.
- A reward that only says right or wrong can't separate a clean correct answer from a messy correct one. Learning from all-correct groups would need a richer reward (for example, one that also scores format or length).

## Other ways to get the baseline

| Method | Baseline for question q | Cost |
| --- | --- | --- |
| None | 0 | nothing, but high variance, and with 0/1 rewards nothing is pushed down |
| Critic / value model (PPO) | a second network predicts expected reward, per token (with GAE) | a whole extra model to train and keep in memory |
| **Group mean (GRPO)** | mean reward of G samples of q | G generations per question |
| Leave-one-out (RLOO) | mean of the *other* G−1 samples, so the baseline doesn't depend on the answer being scored (GRPO's group mean includes it) | the same generation cost as GRPO |

PPO's critic gives a **different advantage for each token**. GRPO's outcome advantage is **the same for every token** in an answer. The critic and GAE are covered in [[RLHF with PPO]].

## Common misconceptions

- **"All wrong answers in a group get the same −1."** No. The size depends on how common failure is in that group (−0.58 when 3 of 4 failed, −1.73 when only 1 of 4 failed).
- **"Every question contributes to the gradient."** No. A group where every answer got the same reward contributes nothing.
- **"GRPO needs a value model like PPO."** No. The group mean replaces it.

## Interview summary

> The advantage is reward minus a baseline, meaning how much better than expected an answer scored; it sets the direction and size of each answer's policy-gradient push. GRPO samples G answers per question and uses Âᵢ = (Rᵢ − mean)/std within the group. The group mean estimates the question's expected reward, replacing PPO's critic, so no extra model is needed. For 0/1 rewards with fraction correct p, Â(correct) = √((1−p)/p) and Â(wrong) = −√(p/(1−p)): rare outcomes get large advantages (a lone success on a hard question, a lone failure on an easy one). Advantages in a group sum to 0. A group where every answer gets the same reward has Â = 0 and gives no gradient, and these groups become more common as the model improves (DAPO's dynamic sampling addresses this). Unlike PPO's critic with GAE, GRPO's outcome advantage is the same for every token in an answer.

## Related notes

- [[Policy Gradient for LLMs]]
- [[GRPO]]
- [[Policy Ratio and Clipping]]
- [[DAPO]]
- [[LLM Training MOC]]
