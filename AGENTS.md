# Instructions for agents working in this vault

This is an Obsidian vault of computer-science notes, written through **dialectical learning**: work through a concept with probing questions and corrected misconceptions, and only then write it up. It is interview prep for software-engineer and agent-developer roles, and the source for the flashcard site in `~/Desktop/interview-review` (repo `selma0817/interview-review`), whose cards cite these notes.

These rules apply in every session, with or without a skill loaded, whichever agent harness you are (`CLAUDE.md` just imports this file).

## Layout

- `Concepts/<Area>/<Folder>/…` holds concept notes. Put a new note in the folder of its main subject; if no folder fits, ask.
- `Topics.md` is the list of allowed `topic/` tags. Read it before tagging anything.
- `Concepts/Interview MOC.md` and the per-area `… MOC.md` notes are indexes. When you add a note, link it from the relevant MOC.
- `Interview Prep/` holds mock interviews. `Projects/<project>/` holds a project overview and an experiment log.
- `.study/` (gitignored) holds study-session state: rounds asked, answer keys, plans for next time. It's local and private; never commit it.

## Note anatomy

Frontmatter first:

```yaml
---
date: 2026-11-18
aliases:
  - names people search for, including Chinese interview phrasings
tags:
  - topic/<main topic>        # 1–3 concept tags, main first
  - topic/<language>          # at most one, only for notes about that language itself
  - free-form-tag
---
```

Body, in this order (skip sections that don't apply):

1. `## One-sentence meaning`: the term in bold and what it is.
2. `## Why I care`: the problem it solves, ideally from my own projects.
3. Core sections that build the idea up with diagrams, code and **real output**. Make headings specific claims ("Why direct commitment requires the current term", not "Details"). Cards cite headings.
4. `## My definitions` (after a dialectical session): my own one-line definitions, as I finally stated them.
5. `## How I'd answer in an interview` or `## Interview summary`.
6. `## Still to learn`, if anything is open.
7. `## Common mistakes`: one `### Mistake N: <the wrong belief>` per mistake. The heading states the wrong belief; the body gives the correction, with a counterexample or failure scenario when there is one. Add ` (mine)` to the heading when it was my own misconception.
8. `## Related notes`: `[[wikilinks]]`.

Writing rules:

- **Cite a primary source** (paper, official docs) for key claims, numbers and formulas. Don't state from memory what you haven't checked.
- English body. Chinese aliases and quoted interview phrasings are fine.
- Inside a Markdown table, escape a wikilink's alias pipe: `[[Note\|alias]]`.

## Tags

The full rules are in `Topics.md`. In short:

- 1–3 `topic/` concept tags plus at most one language tag, main topic first, only tags defined in `Topics.md`.
- If no topic fits, **don't invent one**. Propose a new entry (name, one-line description, why the existing ones don't fit), wait for my approval, add it to `Topics.md` first, then tag. There is no `misc`.
- Free-form tags: lowercase, words joined by `-`, no nesting, one spelling per idea, never a duplicate of a topic tag, no status tags like `interview`.
- MOCs, `README`, `Topics.md` and `Interview Prep/` don't need `topic/` tags.

## Notes and cards

- **One-way flow: notes → cards.** Editing a note never changes cards. Cards are added, edited and removed only in `interview-review/bank/`, through its scripts (`bank:add`, `bank:remove`, `bank:retopic`).
- **Note first.** A card's answer must be in a section of a note. If it isn't yet, update the note first.
- `bank:add` only accepts notes that are committed **and pushed**, so push note changes before making cards from them.
- After retagging notes that cards cite, run `npm run bank:retopic` in `interview-review`.

## Git

- Commit and push only when I ask. Say what changed in the commit message.
- Stage only the notes you changed. Leave `.obsidian/` changes (for example `graph.json`) out unless I ask.

## Learning loop and skills

Study (drill: question → my answer → correction → next question, until solid → note) → distill (session → proposed cards → my yes/no → PR to interview-review) → daily review on the site.

Each step has a skill in `.agents/skills/<name>/SKILL.md`, in the open Agent Skills format. If your harness doesn't load skills by itself, **open the skill's `SKILL.md` and follow it** whenever the task matches:

| Skill | Use when | Status |
|---|---|---|
| [study](.agents/skills/study/SKILL.md) | I say "teach me X", "drill me on X", "quiz me", "interview me", "test me on X" or "I don't get X": probing questions, each answer corrected and evaluated, until every part of the concept is solid; then the note | ready |
| [distill](.agents/skills/distill/SKILL.md) | I say "distill", "make cards" or "turn this into cards", or accept an offer to distill at the end of a session; also "edit card X" / "remove card X" | ready |

`.agents/skills/` holds the only copy of each skill. Harness-specific folders (for example `.claude/skills/<name>`) are symlinks to it, so edit skills in `.agents/skills/` only.
