---
name: distill
description: Turn what a learning or interview session exposed (misconceptions, failure scenarios, definitions, code behavior) into checked flashcards, get the user's yes/no on each, and open a PR that adds them to the interview-review card bank. Use when the user says "distill", "make cards", "turn this into cards", or accepts an offer to distill at the end of a session; also for "edit card X" or "remove card X".
---

# Distill a session into cards

The user learns in this vault, then reviews daily on https://selma0817.github.io/interview-review/. This skill is the bridge: it turns **this conversation** into a few well-checked cards and ships them through a pull request the user merges.

Read first: the vault's `AGENTS.md` (note rules), [style-guide.md](style-guide.md) (what a good card is) and [draft-format.md](draft-format.md) (the draft file).

Paths: the vault is `~/Desktop/knowledge_base`; the card site and bank is `~/Desktop/interview-review`.

## Hard rules

- **Never write `id`, `topic` or `topics` in a draft.** `bank:add` assigns IDs and copies topics from the cited notes' `topic/` tags.
- **Never edit `bank/*.json` by hand**, and never push to `main` of interview-review (it's protected). Cards reach `main` only through a PR, and **the user merges it**, never you.
- **Every card is grounded:** its answer and explanation must be stated in the section it cites. If they aren't, the note gets updated first (step 2), or there's no card.
- **At most 8 cards per session. Fewer is fine.** Two excellent cards beat eight vague ones.
- English only, even when the session mixed in Chinese.

## Workflow

### 1. Collect

List what the session actually exposed, in this priority order:

1. **The user's own misconceptions**: something they said or chose that was wrong, and the correction (these become `(mine)` mistakes and multiple-choice cards).
2. **Failure scenarios they couldn't give**: "what breaks if…", counterexamples, traces.
3. **Definitions** they finally stated in their own words.
4. **Code behavior** that was run or predicted (output, deadlock, leak, race).

Skip anything the session only mentioned in passing. Each item gets one line: what happened in the session, and what the correct idea is.

### 2. Note first

For each item, find the note and **exact heading** that states the correct idea (`grep -n '^#' "<note>"` to see headings). If a note has it, record `{path, heading}`.

If no section states it yet:

- A misconception goes into the note's `## Common mistakes` as `### Mistake N: <the wrong belief> (mine)`, with the correction (and a counterexample or failure scenario when there is one).
- A missing idea becomes a short new section with a specific, claim-like heading.
- The note must already follow `AGENTS.md` (it needs `topic/` tags; add them per `Topics.md` if missing).

Show all proposed note edits together, then ask once: **"OK to apply these note edits, commit and push the vault?"** On yes: edit, commit only those notes with a message saying what was added, push, and confirm `git branch -r --contains HEAD` lists `origin/main`. `bank:add` refuses notes that aren't committed and pushed.

### 3. Draft

Write the drafts to `~/Desktop/interview-review/.drafts/<YYYY-MM-DD>-<topic-slug>.json` in the [draft format](draft-format.md). Choose each card's type from its origin (see the style guide). `provenance` is one sentence naming the session moment, e.g. "You said a merge to main isn't a push."

Then run the bank's own checks early, without writing anything:

```bash
cd ~/Desktop/interview-review && npm run -s bank:add -- .drafts/<file>.json --dry-run
```

This shows each card's ID and **topics** (copied from the notes' tags) and catches made-up headings, untagged or unpushed notes. Fix anything it refuses before going on.

### 4. Check

Run all three checks on every draft and record the results in its `checks` field. A card that fails gets fixed and re-checked **once**; if it still fails, drop it and say why.

Extract each cited section exactly as pushed, from its heading to the next heading of the same or higher level (lines inside code blocks never count as headings), and use that same text for checks a and b:

```bash
~/Desktop/knowledge_base/.agents/skills/distill/extract-section.sh "<path>" "<heading>"
```

**a. Grounded** (every card). Read the extracted section. Every claim in `answer`, `explanation` and `rubric` must be stated there. A claim that isn't means trimming the card or going back to step 2. Result: `grounded: "pass"`.

**b. Blind answer** (`single_choice` only). Give a **fresh model context** only the cited section's text, the question and the options: not the answer, not this session. Use a subagent if your harness has one; otherwise make a separate model call, or ask the user to paste that text into a new chat and report the answer. Ask it to pick one option and say whether any other option is defensible from the section. Pass only if it picks the keyed answer **and** finds no second defensible option. Otherwise rewrite the question or options. Result: `blind_answer: "pass"`, or `"n/a"` for other types.

**c. Code run** (any card whose answer depends on what code does). Put the snippet in a scratch folder with the smallest harness that runs it (`go run`, `node`, `python3`), run it, and compare with what the card claims: output, deadlock message, leak (use a timeout), race (`go run -race`). Result: `code_run: "pass"`. If it truly can't run here (needs a cluster, a GPU), use `"n/a"` and give the reason when presenting the card. Cards without code: `"n/a"`.

### 5. Present

Show a numbered list, one block per card:

```
[1] single_choice · medium · topics: ci-cd, resilience
    Q: …
    A) …  B) …  C) …  D) …        Answer: B
    Why: …
    Source: CI and CD › Gate vs report
    From the session: You said …
    Checks: grounded ✓ · blind answer ✓ · code run n/a
```

End with: **"Reply like `keep 1 3 4 · drop 2 · edit 5: <what to change>`."**

### 6. Apply the reply

- `keep` / `drop`: as stated. Cards not mentioned are dropped; ask if the reply is ambiguous.
- `edit N: …`: make the change, re-run the checks for that card, and show it again for a final yes.
- Write the kept cards to the drafts file and run the dry run again.

### 7. Publish

```bash
cd ~/Desktop/interview-review
git switch main && git pull
git switch -c cards/<YYYY-MM-DD>-<topic-slug>
npm run -s bank:add -- .drafts/<file>.json
npm run -s bank:validate && npm test
git add bank/                      # only the bank; never git add -A here
git commit -m "Add N cards: <session topic>"
git push -u origin cards/<YYYY-MM-DD>-<topic-slug>
gh pr create --title "Add N cards: <session topic>" --body "<one line per card: id · type · topics · question; plus the check results>"
```

Report the PR link and tell the user to merge it when `checks` is green. Merging deploys automatically (about a minute). Offer to verify the live site afterwards. Delete the drafts file once the PR is merged.

## Side flows

**Edit a card** ("card X is wrong / unclear"): find it in `bank/`, propose the change, and say whether it changes the card's **meaning**. A meaning change bumps `version`, which resets the user's review schedule for it; a wording fix doesn't. The user confirms. Re-run the checks, then branch → commit → PR as in step 7.

**Remove a card**: `npm run -s bank:remove -- <id>` (its ID is retired forever), then branch → commit → PR.

**After retagging notes**: `npm run -s bank:retopic -- --dry-run`, show the changes, then run it for real in a branch → PR.
