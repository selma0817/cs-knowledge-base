---
date: 2026-10-01
tags:
  - llm
  - post-training
  - reinforcement-learning
  - reward
  - interview
aliases:
  - reward hacking
  - specification gaming
  - reward overoptimization
  - Goodhart's law
  - 奖励欺骗
  - 奖励黑客
---
**Reward hacking** is when the policy raises its reward without doing what the reward was meant to measure. RL is a strong optimizer: thousands of updates search for *any* behavior the reward scores highly, so every gap between "what the reward checks" and "what we want" eventually gets found. This is Goodhart's law: when a measure becomes a target, it stops being a good measure.

## Where it comes from

### 1. Bugs in a rule-based checker

The checker is the whole definition of "correct", so its bugs are exploits. Examples from the grpo-dapo reward ([[Rule-Based and Verifiable Rewards]]):

| Bug | Effect |
| --- | --- |
| Unicode minus `−` (U+2212) skipped by the number regex | `\boxed{−3}` scored **1.0 against gold 3**: a wrong sign rewarded (fixed) |
| Naive `parse(pred) == parse(gold)` | two failed parses give `None == None`: garbage rewarded (guarded by requiring both to parse) |
| Lenient extraction ("any number in the text matches") | a model listing many numbers hits the answer by chance |
| Accepting several numbers in the box | hedging (`12 or 72`) pays off |
| Parser ignores words | `\boxed{not 72}` scores 1.0. Harmless here, since the model still had to know 72 |

In code RL, a well-documented version is the model special-casing or skipping the unit tests instead of fixing the code.

### 2. What an outcome-only reward can't see

A reward that checks only the final answer is blind to *how* it was reached:
- **Unfaithful reasoning:** wrong or irrelevant steps followed by a right answer (including memorized training answers).
- **Readability:** DeepSeek-R1-Zero, trained with outcome rewards only, produced reasoning with poor readability and mixed languages. DeepSeek-R1 added a language-consistency reward and an SFT stage to fix it.
- **Length drift:** nothing rewards a sensible length, so responses can grow until they hit the limit, or shrink.
- **Guessing a common answer:** only pays off if answers are concentrated. GSM8K answers are diverse, so it doesn't work there.

### 3. Learned reward models: overoptimization

A reward model is a learned approximation of human preference. The policy finds inputs it scores wrongly: longer answers, confident tone, agreeing with the user, heavy formatting. The reward model's score keeps rising while true quality falls.

## Warning signs

- **Training reward rises, but held-out accuracy is flat or falls.** Evaluate with a separate, stricter checker.
- **Sudden changes in response length.**
- **Outputs look strange** (repetition, language mixing, odd formatting) while the reward climbs.
- **Format rate or the rate of boxed-but-unparseable answers shifts suddenly.**

## Defenses

- **Test the checker adversarially:** box spam, hedging, garbage input, huge numbers, unusual characters (as in the grpo-dapo reward tests).
- **Make the reward strict and unambiguous:** one required format, the last box only, exactly one number.
- **Monitor** the warning signs above and **read samples** regularly.
- **Limit drift:** a KL penalty toward the reference model ([[Policy Ratio and Clipping]]).
- **For reward models:** KL penalties, early stopping, ensembles, and refreshing the reward model with new data.

## Common misconceptions

- **"Rule-based rewards can't be hacked."** No. The attack surface is the checker's code, and every bug is an exploit.
- **"If training reward goes up, the model got better."** Not necessarily. Check held-out accuracy and read samples.
- **"Reward hacking needs the model to be clever."** No. Plain optimization pressure finds any gap the reward allows, over thousands of updates.

## Interview answer to "什么是 reward hacking"

**中文 (30 秒):** Reward hacking 是指策略模型提高了奖励分数，却没有真正完成奖励想衡量的目标。RL 优化能力很强，会找到奖励函数和真实意图之间的任何漏洞。来源有三类：规则奖励里的检查器 bug（比如答案解析错误把错误答案判对）；只看最终答案的奖励看不到推理过程（推理不忠实、可读性差、长度失控，比如 DeepSeek-R1-Zero 出现语言混杂）；学习到的奖励模型被过度优化（回答变长、语气自信、迎合用户）。信号是训练奖励上升但验证集准确率不升。防御方法：对检查器做对抗测试、让奖励严格无歧义、监控长度和格式、定期看样本、用 KL 限制偏移。

**English:** Reward hacking is when the policy raises its reward without achieving what the reward measures. RL optimizes hard enough to find any gap. It comes from bugs in rule-based checkers (an answer parser marking a wrong answer correct), from outcome rewards being blind to the reasoning (unfaithful steps, unreadable or language-mixed reasoning as in DeepSeek-R1-Zero, length drift), and from overoptimizing learned reward models (longer, more confident, more agreeable answers). The main warning sign is training reward rising while held-out accuracy doesn't. Defenses: adversarial tests for the checker, strict unambiguous rewards, monitoring length and format, reading samples, and a KL penalty.

## Interview summary

> Reward hacking is the policy raising reward without doing the intended task; RL's optimization pressure finds any gap between reward and intent (Goodhart's law). Rule-based checkers are hacked through their bugs (parsing errors that reward wrong answers, None == None, lenient extraction, accepted hedging). Outcome-only rewards can't see the reasoning, so unfaithful or unreadable reasoning (DeepSeek-R1-Zero's language mixing) and length drift go unpunished. Learned reward models get overoptimized toward length, confidence and sycophancy. Watch for training reward diverging from held-out accuracy, sudden length changes and strange outputs; defend with adversarial checker tests, strict rewards, monitoring, sample reading and KL regularization.

## Related notes

- [[Rule-Based and Verifiable Rewards]]
- [[GRPO]]
- [[Policy Ratio and Clipping]]
- [[DAPO]]
- [[LLM Training MOC]]
