# Drilling: how to ask, correct and evaluate

## What the user is like

They usually get the conclusion right but can't give the failure scenario or the mechanism behind it. So the drill's main job is to push past a correct conclusion: "why?", "what breaks if…?", "which exact line makes that true?".

## Asking

Prefer these question types, roughly in this order:

1. **Prediction:** "what does this print?", "red or green?", "which job runs?". Concrete, checkable, and a wrong prediction exposes the misconception directly.
2. **Failure scenario:** "what breaks if you remove X?", "trace what happens when…".
3. **Counterexample:** "give a case where that rule would be wrong."
4. **Mechanism:** "which part makes that true?", "why does it work?".
5. **Trade-off:** "why X rather than Y? what does X cost?".
6. **Code reading,** when the topic has code: runnable, about 25 lines or fewer.
7. **Definitions,** only as a warm-up or at the end.

Rules:

- **Use real material:** the user's own repos and runs, the note's demos, or output you produce now. Never invented output.
- **Write the key first** (in `.study/`), and verify it: run the code (`go run`, `node`, `python3`, a throwaway clone) or cite the source.
- **Don't give the answer away** in the wording. No yes/no questions: ask for the choice, the trace or the reason.
- **Revisit the user's `(mine)` mistakes** in a new form, never in the note's words.
- **Show the concrete problem before any fix,** then the options with trade-offs, then your pick. Never present one fix as the only one.
- **At most 3 small parts per message.** Number them, so shorthand answers are easy ("1: red · 2: b because…").

## Correcting and evaluating

Reply to every answer in this shape, one block per part:

```text
1. shaky
   ✓ Right: <what they got right>
   ✗ Missing: <what was missing or wrong, and why>
     Evidence: <real output, a source, or Note › heading>
   Misconception: you said "<their words>"; actually <the correction>.
```

Leave out lines that don't apply (a solid answer has no ✗ line). Then the one-line progress update, then the next question.

**Verdicts:**

| Verdict | When |
|---|---|
| **solid** | right, with the mechanism, and no help |
| **shaky** | right conclusion with a missing or wrong reason; or right only after a hint or word bank |
| **missing** | wrong, or no answer |

Be exact about what was wrong, but keep it short. Explain only the gap the answer revealed: a few lines, a plain analogy, real output. A longer explanation only when the user asks for one.

## When the user is stuck

When the user says "not sure" or answers far off, make the step smaller rather than repeating the question:

- **two or three options** to choose between;
- **a fill-in with a word bank;**
- **a smaller example** of the same idea;
- or **a short explanation** (define the terms, show the problem), followed by a re-ask in a new form.

Whatever helped, the part is shaky at best until the user answers a new question on it without help.

## Starting a brand-new topic

When the user meets a topic for the first time, the loop still starts with questions, but easy, concrete ones:

1. "What problem do you think this solves?" or a prediction about a tiny example.
2. Define each term the moment it appears, with a plain analogy.
3. Give word banks before fill-ins.
4. Say where any file you create lives and whether it's temporary.

## Language

English, as AGENTS.md says. The user may answer in Chinese; reply in English, and offer the Chinese interview phrasing for a term when it helps.
