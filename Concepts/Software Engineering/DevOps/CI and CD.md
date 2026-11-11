---
date: 2026-11-10
tags:
  - ci-cd
  - devops
  - github-actions
  - git
  - deployment
  - software-engineering
  - interview-review
  - cmbrater
aliases:
  - CI/CD
  - Continuous Integration
  - Continuous Delivery
  - Continuous Deployment
  - Semantic merge conflict
  - Gate vs report
---
## One-sentence meaning

CI checks that each commit, combined with the current `main`, builds and passes its tests on a clean machine. CD takes commits that passed and gets them to users, either when a person presses a button (Delivery) or automatically (Deployment).

## Why I care

- I already run three pipelines: `interview-review/.github/workflows/ci.yml`, `interview-review/.github/workflows/deploy.yml`, and `CMBRater/.github/workflows/ci.yml`. Before these rounds I couldn't say what each one protects against, or what it doesn't.
- Common interview questions: "walk me through your CI/CD pipeline", "Delivery vs Deployment?", "how do you keep `main` green when many people merge?"

## The pieces of a pipeline

```text
trigger (on:)  → what event starts the workflow
  job          → runs on its own fresh VM; jobs run in parallel unless one says needs:
    step       → runs in order; the first failing step stops the job
```

My interview-review `ci.yml`, read as a pipeline:

```text
push to main, or any PR
 └─ job "checks"  (brand-new Ubuntu VM)
     checkout → setup-node(.nvmrc) → npm ci → typecheck → validate:bank → vitest → build → playwright e2e
                                              cheap, fast ─────────────────────────────────→ slow, expensive
```

Cheap checks go first so a broken commit fails in seconds instead of after the slow e2e run.

## Three machines, three questions

| Machine | What it has | Question it answers |
|---|---|---|
| My laptop | My working folder, my `node_modules`, Node v23.3.0, macOS | "Is my **folder** OK?" |
| CI runner | A fresh VM with **only the commit** plus the tools the repo declares (Node 22 from `.nvmrc`). Thrown away afterwards | "Is this **commit**, combined with `main`, OK?" |
| Production | Where users run it: GitHub Pages; a user's Windows PC for CMBRater | "Does it work for users?" |

The CI runner is **not** trying to copy production. It's a neutral third machine. Its job is to remove everything that only exists on my disk.

A local result depends on the commit **plus everything else on my disk**:

- **Files I haven't committed.** See the demo below.
- **`node_modules` that doesn't match the lockfile.** `npm ci` deletes `node_modules`, installs exactly what `package-lock.json` lists, and fails if `package.json` and the lockfile disagree. `uv sync --locked` is the Python version of this.
- **Runtime version.** My laptop runs Node 23. CI runs Node 22.
- **Operating system.** macOS ignores upper/lower case in file names by default; Linux doesn't. `import './header'` can find `Header.tsx` on my Mac and fail on Ubuntu.
- **Other people's work.** I tested against the `main` I last pulled, not today's `main`.

Compiled vs interpreted is not the dividing line. A Go or Java compiler version changes results the same way. What matters is whether the tool and its version are **declared in the repo** or **only exist on my machine**.

### Demo: `git commit -am` with a new file

`-a` stages **tracked** files (git already knows them) that were modified or deleted. New, **untracked** files are skipped. `git add -A` is the command that includes them.

```text
git status before commit:    M src/App.js      ← tracked + modified → -a includes it
                            ?? src/clamp.js    ← untracked          → -a skips it
run on laptop:               slice 20
files in the commit:         src/App.js only
fresh clone (what CI gets):  Error: Cannot find module './clamp'
```

My laptop passes because `clamp.js` is on disk. CI fails because it isn't in the commit.

Uncommitted code never reaches CI. CI runs when commits are **pushed**, and it checks out a commit, so local edits and unpushed commits are invisible to it.

## CI

> CI is the practice of merging small changes into `main` often. Every change is automatically built and tested on a fresh machine, using only the commit plus its locked dependencies, combined with the current `main`. It runs on the PR before merge and again on `main` after merge. It answers "is this commit OK together with everyone else's work?", not "does it work on my laptop?". It doesn't deploy anything.

CI is a habit first and a tool second. A branch that lives for weeks has CI tools but isn't really doing CI, because the longer it lives, the bigger the semantic-conflict risk when it finally merges.

### When CI runs, and what it checks out

CMBRater's trigger:

```yaml
on:
  push:
    branches: [main]
  pull_request:
```

| Event | CI runs? | Why |
|---|---|---|
| Push to a feature branch, no PR open | no | nothing matches |
| Open a PR | yes | `pull_request` (opened) |
| Push more commits while the PR is open | yes, again | `pull_request` (synchronize) |
| Click Merge | no new run before the merge | the button reads the PR's last result |
| …the merge lands on `main` | yes, again | `push: branches: [main]` |

PR CI does **not** test the tip of my branch. GitHub builds a temporary merge commit (`refs/pull/N/merge`), "`main` as it is now + my branch", and tests that. That's the "integration" part.

`main` is what gets deployed. In interview-review, `gh workflow run deploy.yml --ref main` builds the newest commit on `main` at that moment. That's why teams protect `main`: if it's what ships, everything has to be checked before it gets there.

## Semantic conflicts

> Two changes that merge cleanly as text (different lines or files) but break when combined. Git compares lines, not meaning, so it can't see it. Only building and testing the combined code catches it.

Git only reports a conflict when both branches changed the same or neighboring lines of the same file. The break isn't always an error. It can be silently wrong behavior: A changes a default from 20 to 10, and B's new code assumes 20.

### Demo: two green PRs, red `main`

`main` has `loadSlice` in `api.ts`. PR A renames it to `fetchSlice`. PR B, branched before A merged, adds `Preview.ts` that calls `loadSlice(3)`.

```text
PR A's CI  (old main + A)                 typecheck PASS ✅
PR B's CI  (old main + B, when B opened)  typecheck PASS ✅
merge A into main                         Merge made by the 'ort' strategy.
merge B into main                         Merge made by the 'ort' strategy.   ← no conflict
push-to-main CI                           FAIL ❌  TS2305: Module './api' has no exported member 'loadSlice'
```

B's ✅ was honest but **stale**: it described "old `main` + B". When A merged, nothing re-tested B, because `pull_request` only re-runs when B's own branch changes.

The fix is to **test the exact commit that will become `main`, right before it becomes `main`**:

- **Require branches to be up to date before merging.** B must pull in the new `main` first. That's a new push, so CI re-runs on `main` + A + B, goes red, and the merge is blocked. The cost: on a busy repo everyone keeps updating and waiting for CI.
- **Merge queue.** GitHub lines PRs up, tests `main` + A, then `main` + A + B, and only moves `main` forward when that exact combination passes.
- **The push-to-`main` run** is the safety net. It catches what got through, but only *after* the break is on `main`.

My CMBRater on 2026-11-10: `feature/admin-dashboard` (5 commits ahead), `feature/save-hardening` (4) and `feature/round-integration` (1) were all forked from the same `main`. Short-lived branches are healthy CI, but this is exactly the setup above. CMBRater is private on the free plan, so GitHub can't enforce "require up to date". The manual habit: after each merge, merge `main` into the next branch, push, and wait for green.

## Which step guards what

A CI step only guards against the kind of error it actually checks.

| Step | Question it answers |
|---|---|
| `npm ci` | Do the exact locked dependencies install? |
| `typecheck` | Do the types agree? Nothing else checks this. |
| `test` (vitest) | Does the code do what the tests expect? Vitest strips types; it doesn't check them. |
| `build` | Can it be bundled? Whether this checks types depends on the script. |
| `e2e` | Does the real app work in a real browser? |

### Demo: delete the typecheck step

Added `export const MAX_SLICE_CHECK: number = "20"` to `App.tsx` in throwaway clones and ran the remaining steps:

```text
CMBRater
  npm test          (vitest)                     PASS ✅
  npm run build     (electron-vite / esbuild)    PASS ✅   → CI green
  npm run typecheck (the deleted step)           FAIL ❌  TS2322

interview-review
  npm test          (vitest)                     PASS ✅
  npm run build     (= typecheck && vite build)  FAIL ❌  TS2322 → CI red
```

At runtime it doesn't crash. Types are erased (see [[TypeScript Types vs Runtime Data]]):

```text
JS after build:  const max = "20";
                 console.log(max + 1, typeof max, max > 5);
node prints:     201 string true
```

In CMBRater the typecheck step is the only type gate. Without it, type errors ship as silently wrong values.

## Continuous Delivery vs Continuous Deployment

> **Delivery:** every green commit on `main` *could* go live; a person presses the button. **Deployment:** every green commit on `main` *does* go live automatically.

The question that separates them: **between a green `main` and users, does a person press a button?**

| | Delivery | Deployment |
|---|---|---|
| Human button | yes | no |
| Why choose it | control over timing, human sign-off, grouping changes into one release | speed, small releases |
| What it costs | someone has to remember, and the button is only a check if they actually check something | more automated safety: thorough e2e, canary releases, monitoring, automatic rollback |

Both can run exactly the same tests. e2e is **not** what separates them. Removing the human just means automation has to do the human's job.

interview-review is **Delivery**: `deploy.yml` only has `on: workflow_dispatch`. On 2026-11-10, `main` was at `def6f5a` (README change) while the live site was built from `69a7f0e`, one commit behind.

## Gate vs report

> A check is a **gate** when its failure automatically stops the next step (the next step in the job, a merge, a deploy). Otherwise it's a **report**: it tells someone, who may or may not look.

A car that beeps when the seatbelt is off is a report. A car that won't start until you buckle up is a gate. Both notice the same problem; only one stops you.

| Check in my repos | Gate or report |
|---|---|
| `typecheck` step fails in `ci.yml`, so later steps in the job are skipped | gate |
| PR's CI is red in interview-review, but Merge is still clickable (no branch rule) | report |
| `verify` fails in `deploy.yml`, so `deploy` (`needs: verify`) is skipped | gate |
| `ci.yml` is red on `main`, but `gh workflow run deploy.yml` still runs | report |
| My deploy button press on Nov 5 | checked nothing |

Most real CI/CD failures look like this: the test existed, but nothing connected its result to the merge or deploy.

### Why an e2e-broken commit can go live in interview-review

Workflows run independently. `deploy.yml` can't see `ci.yml`'s result unless I connect them on purpose: `on: workflow_run`, calling `ci.yml` as a reusable workflow, or checking the commit's status. Two holes line up:

```text
ci.yml:      typecheck → bank → test → build → e2e ❌   ← result goes nowhere
                                                     ✗  (no link)
deploy.yml:  verify: typecheck → bank → test → build ✅  (no e2e) → deploy → live 🔴
```

Close either hole and the broken commit is blocked. On 2026-11-05 I dispatched the deploy of `69a7f0e` at 23:28:27, 6 seconds after its CI started (CI finished green at 23:29:01). The deploy never waited for CI; it only worked because CI happened to pass.

## Gaps in my own pipelines (as of 2026-11-10)

- **interview-review `main` is unprotected** (public repo, no branch rules). A red PR can be merged, and I can push straight to `main`.
- **`deploy.yml` ignores `ci.yml`'s result**, and `verify` skips e2e. An e2e-broken commit can go live.
- **`deploy.yml` rebuilds** (`npm ci` + `npm run build` again) instead of deploying the output that `verify` checked. → Round 2: build once, deploy that same output.
- **CMBRater is private on the free plan.** Branch protection returns "Upgrade to GitHub Pro or make this repository public", so no red merge can be blocked.
- **CMBRater's typecheck step is the only type gate.** `build` and `test` both strip types.
- interview-review `ci.yml` runs typecheck twice: once as its own step and again inside `build`. Harmless; the separate step fails earlier with a clearer name.

## How I'd answer in an interview

**"Walk me through your CI/CD."** On every PR and every push to `main`, GitHub Actions runs a fresh Ubuntu VM: `npm ci` from the lockfile, typecheck, data validation, unit tests, build, then Playwright e2e, cheapest first. PR runs test the merge of my branch into the current `main`. Deploys to GitHub Pages are manual (Continuous Delivery). One gap I found: the deploy workflow doesn't depend on CI's result and doesn't run e2e, so I'd gate it on a green CI run for that exact commit.

**"How do you keep `main` green with many PRs?"** A PR's green check is about "old `main` + PR". After another PR merges, it's stale, and semantic conflicts merge cleanly as text. So test the exact future `main`: require up-to-date branches, or use a merge queue. And run CI on `main` after merge as a safety net.

**"Delivery vs Deployment?"** Whether a person presses the release button. Deployment removes the person, so it needs more automated safety: e2e, canaries, monitoring, rollback.

## Still to learn (round 2)

- Build once, deploy that same output (`deploy.yml` currently rebuilds)
- `concurrency` and `cancel-in-progress` for deploys
- Least-privilege `permissions:`, OIDC `id-token: write` vs stored secrets
- Environments and required approvals
- Rolling back a bad deploy
- Flaky tests, caching, `pull_request` vs `pull_request_target` for forks
- Releasing an Electron app (build artifacts, code signing)

## Common mistakes

From my rounds on 2026-11-10.

### Mistake 1: thinking CI fails because the deployment environment is different

The CI runner isn't production. It's a clean third machine whose job is to see only the commit. CI also doesn't deploy. That's the CD part.

### Mistake 2: "I tested locally, so CI is redundant"

I tested my folder, with my `node_modules`, my Node version and my OS. CI tests the commit combined with today's `main`.

### Mistake 3: thinking `git commit -a` adds new files

It only stages **tracked** files. A new `clamp.ts` stays behind, so the laptop passes and CI fails with "Cannot find module".

### Mistake 4: thinking CI only runs when I merge

It runs when the PR opens, on every new push to the PR, and again on `main` after the merge.

### Mistake 5: expecting git to report a semantic conflict

Git conflicts are textual: the same or neighboring lines. A rename in one PR and a new caller in another merge cleanly.

### Mistake 6: thinking a failed CI blocks the merge

Only if a branch rule requires the check. Even then, a **stale** green check passes. B's ✅ was for a `main` that no longer existed.

### Mistake 7: thinking `const max: number = "20"` crashes at runtime

Types are erased. It runs, and `max + 1` is `"201"`. Only the typecheck step sees it.

### Mistake 8: calling a manual deploy "Continuous Deployment"

It's backwards. A human button means Delivery.

### Mistake 9: thinking e2e is what separates Delivery from Deployment

Both can run the same tests. The difference is only whether a person presses the release button.

### Mistake 10: saying "we didn't check it in CI"

CI did check it and went red. The result just didn't reach anything that could stop the deploy. That's a report, not a gate.

### Mistake 11: treating the deploy button itself as a check

A button is only a gate if the person pressing it actually checks something. On Nov 5 I pressed it 6 seconds after CI started.

## Related notes

- [[Container]]
- [[Dockerfile vs Docker Compose vs Kubernetes]]
- [[TypeScript Types vs Runtime Data]]
- [[Interview MOC]]
