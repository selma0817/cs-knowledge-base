# Writing good cards

A card is reviewed on a phone in about 30 seconds, again and again over months. It should bring back **one idea the user struggled with**, in the shape an interviewer would ask about it.

## Pick the type from where the card came from

| From the session | Card type | Why |
|---|---|---|
| A misconception the user showed | `single_choice` | Their wrong belief becomes a wrong option, so they practice rejecting it |
| A failure scenario they couldn't give | `short_answer` with a `rubric` | Explaining "what breaks if…" out loud is the interview skill |
| A definition they finally stated | `flashcard` | Quick recall of the term and its one-line meaning |
| Code behavior (output, deadlock, leak, race) | `code_reading` | Predicting what code does is how coding interviews probe it |

## Questions

- **One idea per card.** If the answer needs "and also…", split it, or keep only the part the user got wrong.
- **Prefer a concrete scenario** over an abstract prompt: "A PR merges at 22:09; what fires on `main`?" beats "Explain triggers."
- **Prefer "what breaks if…"** and "why" over "what is". The user's weak spot is the failure scenario behind a correct conclusion.
- Use the note's real data, numbers and names when they help (their own repos, runs, commits). Use numbers only when they matter to the idea.
- The question must not give the answer away in its wording.
- No yes/no questions; ask for the choice, the trace, or the reason.

## Multiple choice (`single_choice`)

- 3–4 options, IDs `A`–`D`, **exactly one** defensible from the cited section (the blind-answer check enforces this).
- Wrong options are **real misconceptions**: the user's own `(mine)` beliefs first, then common ones. Never filler.
- Options of similar length and style, so the right one doesn't stand out. No "all of the above", no double negatives.
- `explanation` says why the right option is right **and** why the user's wrong belief fails.

## Short answer (`short_answer`)

- Ask for something they'd say in an interview: a trace, a failure scenario, a comparison.
- `answer`: the model answer in 5 lines or fewer.
- `rubric`: 3–5 checkable points, each a distinct fact or step. The user ticks these mentally when they reveal the answer.

## Flashcard (`flashcard`)

- Front: the term or a short prompt. Back (`answer`): 1–3 lines, in the user's own wording from the session when they had a good one.

## Code reading (`code_reading`)

- A runnable snippet of about 25 lines or fewer, fenced in the question with its language, and `code_language` set.
- Ask what it prints, whether it terminates, or where the bug is.
- The code-run check must reproduce the claimed behavior, so keep the snippet self-contained.

## Difficulty

- `easy`: recall one fact or definition.
- `medium`: apply or explain an idea in a given situation.
- `hard`: trace a failure scenario, an edge case, or two interacting mechanisms.

## Don't

- Don't go beyond the cited section. A fact that isn't in the note isn't a card yet: update the note first.
- Don't make cards about trivia the session didn't struggle with.
- Don't duplicate a card already in `interview-review/bank/` (search it for the idea first).
