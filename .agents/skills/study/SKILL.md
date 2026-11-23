---
name: study
description: Drill the user dialectically on a computer-science concept, using their Obsidian vault. Ask probing questions, correct and evaluate every answer, track a progress map of the concept's parts, and keep going until every part is solid; then write or update the vault note. Use when the user says "teach me X", "drill me on X", "quiz me", "interview me", "test me on X", "I want to learn X" or "I don't get X".
---

# Study: drill until it's solid, then write the note

The user preps for software-engineer and agent-developer interviews. Their loop is: study a concept with this skill → a note in the vault → the separate `distill` skill turns the session into flashcards → daily review on https://selma0817.github.io/interview-review/.

This skill is one loop: **ask → the user answers → correct and evaluate → ask the next question**, until the user has a good grasp of every part of the concept. Then the note.

Read first: the vault's `AGENTS.md` (note rules) and [drilling.md](drilling.md) (how to ask, correct and evaluate).

Paths: the vault is `~/Desktop/knowledge_base`; session state goes in its `.study/` folder.

## 1. Start

1. **Name the topic** back to the user in one line.
2. **Check what the vault has.** Search note titles, aliases and the MOCs (`grep -ril "<term>" Concepts/`). Say which notes exist, what they cover, and what's missing. Read the main note and its `## Common mistakes`: the `(mine)` entries are the user's known weak spots.
3. **Check `.study/<topic-slug>.md`.** If it exists, resume from its progress map and `## Open` list, and say where you're picking up.
4. **Judge the starting level.** A topic with no note and little background: assume an undergraduate meeting it for the first time, and define every term on first use.

## 2. Map the topic

Split the topic into **4–8 parts**, the ideas an interviewer would probe. For each part, write down what a good answer includes and where that comes from:

- **from the note**, citing `Note › heading`, when the vault covers it;
- otherwise **from a primary source** (paper, spec, official docs) or **a real run** you do now. Never from memory alone.

Save the map to `.study/<topic-slug>.md` (format below), and show it to the user as a short list. They can add, drop or reorder parts.

## 3. The loop

1. **Ask one question** on the weakest part that isn't solid yet: at most 3 small, numbered parts. Before asking, write its answer key in the `.study/` log. Question types and rules are in drilling.md.
2. **Wait for the answer.** Shorthand is fine. If the user says "not sure", scaffold (drilling.md); don't just answer it for them.
3. **Correct and evaluate** right away, in drilling.md's format:
   - a verdict: **solid**, **shaky** or **missing**;
   - what was right;
   - what was wrong or missing and why, with evidence (real output, a source, or `Note › heading`);
   - any misconception, named plainly.

   Keep explanations short and inside the correction. Teach only what the answer showed was missing.
4. **Update the map** and show progress in one line, e.g. `Raft commitment: 3/6 solid · now: why the current term matters`.
5. **Pick the next question:**
   - **solid** → go harder on the same part (its failure scenario, a counterexample, "which line makes that true?"), or move on once the part is solid;
   - **shaky** → a follow-up on exactly what was missing;
   - **missing** → a smaller question, two options or a word bank, or a short explanation followed by a re-ask in a new form.

A part is **solid** when the user has answered, without help, what it is, why it works (the mechanism), and what breaks without it (a failure scenario or counterexample). An answer that needed a hint makes the part shaky at best.

The loop ends when **every part is solid**: say so and move to step 4. If the user stops earlier, save the map and the `## Open` list so the next session picks up where you left off.

## 4. After every part is solid

1. **The user's definitions.** Ask for a one-line definition of each key term in their own words. Point out anything missing or wrong, and let them restate it. Their final versions go into the note's `## My definitions`.
2. **The note.** Write a new note or update the existing one, following AGENTS.md exactly: folder, frontmatter, tags from `Topics.md`, claim-like headings, real output, primary sources, the interview answer, and a link from the relevant MOC. Every misconception from the session becomes `### Mistake N: <the wrong belief> (mine)` under `## Common mistakes`, with the correction. Anything the session found that the note doesn't cover gets a section.
3. **Show the draft or diff, and ask once:** "OK to apply these note edits, commit and push the vault?" On yes: write, commit only those notes with a message saying what changed, and push.
4. **Update `.study/`**, then **offer to distill** the session into cards (the `distill` skill).

Optional, when the concept is something the user builds (a pipeline, a concurrency pattern): offer a hands-on exercise in their own or a practice repo. Settle the design together first; the user writes it; you review it; they run it, including one failure on purpose. Never push to their projects or change their settings without asking.

## The `.study/` file

`.study/` is gitignored: local, private, readable by any agent. One file per topic:

```markdown
# Raft commitment

## Map (updated 2026-11-23)

| Part | Status | A good answer includes | Source |
|---|---|---|---|
| Counting replicas | solid | majority of matchIndex; leader counts itself | Raft Commitment and Application › Leader commitment calculation |
| Why only the current term | shaky | the Figure 8 counterexample; prefix committed indirectly | … › Why direct commitment requires the current term |
| … | not asked | … | … |

## Log

### 2026-11-23
1. Q: <the question as asked>
   Key: <the expected points>
   Answer: <one line on what the user said>
   Verdict: shaky (missing: the counterexample)

## Open
- <where to pick up, unanswered questions, things the note lacks>
```

Statuses: `not asked`, `missing`, `shaky`, `solid`. Never commit `.study/`, and never edit card files: cards come only through `distill`.
