---
date: 2026-11-10
tags:
  - topic/ci-cd
  - github-actions
  - git
  - deployment
  - releases
  - interview-review
  - cmbrater
aliases:
  - CI/CD
  - Continuous Integration
  - Continuous Delivery
  - Continuous Deployment
  - Semantic merge conflict
  - Gate vs report
  - Reusable workflow
  - Build once
  - GitHub Flow
  - Deploy on push
  - Repository ruleset
  - Defense in depth
---
## One-sentence meaning

CI checks that each commit, combined with the current `main`, builds and passes its tests on a clean machine. CD takes commits that passed and gets them to users, either when a person presses a button (Delivery) or automatically (Deployment).

## Why I care

- I already run three pipelines: `interview-review/.github/workflows/ci.yaml`, `interview-review/.github/workflows/deploy.yaml` (`.yml` until 2026-11-18), and `CMBRater/.github/workflows/ci.yml`. Before these rounds I couldn't say what each one protects against, or what it doesn't.
- On 2026-11-16 and 17 I built a release pipeline in a practice repo, `~/Desktop/ci_practice` (GitHub `selma0817/CICD_testing`, private), as a rehearsal for CMBRater's releases. Its runs are the evidence in "Round 2" below.
- Common interview questions: "walk me through your CI/CD pipeline", "Delivery vs Deployment?", "how do you keep `main` green when many people merge?", "how do you know the release is what you tested?"

## The pieces of a pipeline

```text
trigger (on:)  → what event starts the workflow
  job          → runs on its own fresh VM; jobs run in parallel unless one says needs:
    step       → runs in order; the first failing step stops the job
```

- Every `.yml` file in `.github/workflows/` is its own workflow. The filename (`ci.yaml`, `release.yaml`) is only a label for humans. Two workflow files know nothing about each other unless I link them on purpose.
- A step is either `uses:` (run a published action, like importing a library) or `run:` (a shell command, exactly what I'd type in a terminal).
- A step fails when its command exits with a non-zero **exit code**. That number, not the printed text, is what Actions looks at.

My interview-review `ci.yaml`, read as a pipeline:

```text
any PR, or called by deploy.yaml
 └─ job "checks"  (brand-new Ubuntu VM)
     checkout → setup-node(.nvmrc) → npm ci → typecheck → bank:validate → vitest → build → playwright e2e → pack dist/ (deploys only)
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
- **Old build output.** `tsc` never deletes files it emitted earlier, so my laptop's `dist/` can hold leftovers that a fresh runner never has (see "Ship only the product").

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
| Push a tag `v1.0.0` | no | a tag isn't a branch, so `branches: [main]` doesn't match |

PR CI does **not** test the tip of my branch. GitHub builds a temporary merge commit (`refs/pull/N/merge`), "`main` as it is now + my branch", and tests that. That's the "integration" part.

`main` is what gets deployed. In interview-review, every new commit on `main` starts `deploy.yaml`, which tests that commit and publishes it (see "Round 3"). That's why teams protect `main`: if it's what ships, everything has to be checked before it gets there.

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

Update 2026-11-17: all 8 CMBRater branches are fully merged (0 commits ahead of `main`), but none of them were deleted.

## Which step guards what

A CI step only guards against the kind of error it actually checks.

| Step | Question it answers |
|---|---|
| `npm ci` | Do the exact locked dependencies install? |
| `typecheck` | Do the types agree? Nothing else checks this. |
| `lint` | Does the code follow the lint rules (for example, no unused variables)? |
| `test` (vitest) | Does the code do what the tests expect? Vitest strips types; it doesn't check them. |
| `build` | Can it be bundled? Whether this checks types depends on the script. |
| `e2e` | Does the real app work in a real browser? |

`npm ci` and `npm run ci` are different commands. `npm ci` is npm's built-in **clean install**: it installs and checks nothing. `npm run ci` runs the script *named* `ci` in `package.json` (in ci_practice: `typecheck && lint && test && build`). A job needs both, install first. On a fresh runner, `npm run ci` without `npm ci` fails because `tsc` isn't installed.

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

interview-review was **Delivery** until 2026-11-18: `deploy.yml` only had `on: workflow_dispatch`. On 2026-11-10, `main` was at `def6f5a` (README change) while the live site was built from `69a7f0e`, one commit behind. Since PR #1 (`be00445`, 2026-11-18) it's **Continuous Deployment**: every merge to `main` goes live about a minute later with no button, but only if CI passes (see "Round 3").

ci_practice is also **Delivery**, of a package instead of a website: pushing a `v*` tag is the human button, and users download a file from the release page. CMBRater will have the same shape, because users install a Windows installer.

## Gate vs report

> A check is a **gate** when its failure automatically stops the next step (the next step in the job, a merge, a deploy). Otherwise it's a **report**: it tells someone, who may or may not look.

A car that beeps when the seatbelt is off is a report. A car that won't start until you buckle up is a gate. Both notice the same problem; only one stops you.

| Check in my repos | Gate or report |
|---|---|
| `typecheck` step fails in `ci.yml`, so later steps in the job are skipped | gate |
| Before 2026-11-18: PR's CI is red in interview-review, but Merge is still clickable (no branch rule) | report |
| Since 2026-11-18: the `main` ruleset requires `checks`, so Merge stays disabled until it's green | gate |
| Before 2026-11-18: `verify` fails in `deploy.yml`, so `deploy` (`needs: verify`) is skipped | gate |
| Before 2026-11-18: `ci.yml` is red on `main`, but `gh workflow run deploy.yml` still runs | report |
| Since 2026-11-18: `ci / checks` fails in a Deploy run, so `deploy` (`needs: ci`) is skipped | gate |
| My deploy button press on Nov 5 | checked nothing |
| ci_practice: `release` job has `needs: verify`, so any failed CI step skips publishing | gate |
| ci_practice: `validate-tag` fails for a tag that isn't on `main` | gate, but only against accidents (see "Release only reviewed code") |
| ci_practice: PRs #7 and #8 merged 12 and 10 seconds after opening, before their CI finished | a report nobody waited for |
| ci_practice: PR #9 merged 27 seconds after its CI turned green | a report, read before acting |

Most real CI/CD failures look like this: the test existed, but nothing connected its result to the merge or deploy. On my private free repos GitHub can't turn a PR check into a gate, so **my habit of waiting for green is the gate**. interview-review is public, so there a ruleset does it (see "Round 3").

### Why an e2e-broken commit could go live in interview-review

Workflows run independently. `deploy.yml` can't see `ci.yml`'s result unless I connect them on purpose: `on: workflow_run`, calling `ci.yml` as a reusable workflow, or checking the commit's status. Two holes line up:

```text
ci.yml:      typecheck → bank → test → build → e2e ❌   ← result goes nowhere
                                                     ✗  (no link)
deploy.yml:  verify: typecheck → bank → test → build ✅  (no e2e) → deploy → live 🔴
```

Close either hole and the broken commit is blocked. On 2026-11-05 I dispatched the deploy of `69a7f0e` at 23:28:27, 6 seconds after its CI started (CI finished green at 23:29:01). The deploy never waited for CI; it only worked because CI happened to pass.

A trigger alone doesn't close the holes. If I had only added `push: branches: [main]` to `deploy.yml`, a merge would start both workflows at the same moment, and neither would wait for the other. Using the Nov 14 run times (CI reached its e2e verdict 38 s in; a whole Deploy run took 42 s), a commit with broken e2e would have gone live about 4 seconds after CI's red X.

Fixed on 2026-11-18 (PR #1): `deploy.yaml` calls `ci.yaml`, and its deploy job has `needs: ci`. When CI fails, the deploy job doesn't run and fail: it's **skipped**. GitHub's docs: when a job fails or is skipped, every job that needs it is skipped too, unless its `if:` says otherwise ([Workflow syntax, `jobs.<job_id>.needs`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)). Skipped is what a gate looks like.

## Round 2: a release pipeline in ci_practice

ci_practice is a small TypeScript task library (`src/task.ts`, vitest tests, eslint). Codex wrote the first CI workflow and a tag-triggered release. I then closed three holes myself, one PR each (E1–E3), and checked every release with real runs.

### The final pipeline

```text
PR to main, push to main
 └─ ci.yaml: verify
     checkout → setup-node 22 → npm ci → typecheck → lint → test → build → upload artifact (dist/)

push tag v*
 └─ release.yaml
     validate-tag ──────▶ verify ─────────────────────▶ release
     is the tagged        = ci.yaml, called:            download that dist/ → tar
     commit on main?      all checks + upload           → gh release create
```

### Three releases, three versions of the pipeline

| Release | Commit | What the pipeline did | What shipped |
|---|---|---|---|
| v1.0.0 | `1b0c2b8` | `release.yaml` re-ran `npm ci` + `npm run ci` and built again | 8 files, including `tests/` |
| v1.0.1 | `985181f` | E1: called `ci.yaml` and shipped its artifact | the same 8 files, byte-identical to that run's CI artifact |
| v1.0.2 | `19ea27f` | E2 + E3: tag check → CI → release; build only `src` | 4 files: `task.js`, `task.d.ts` and their two maps |

### E1: one list of checks (reusable workflow)

The problem: the same checks were written in two places, and two lists drift apart.

```text
ci.yaml (steps)            release.yaml → npm run ci (package.json)
  typecheck                  typecheck
  lint                       lint
  test                       test
  build                      build
  test:e2e  ← added later    (nobody adds it here) → releases silently skip e2e
```

Not hypothetical: interview-review's `deploy.yml` `verify` job already lacks the e2e that `ci.yml` runs.

| Option | One list lives in | Separate step names? | Cost |
|---|---|---|---|
| A. `ci.yaml` runs `npm run ci` as one step | `package.json` | no | open the log to see which check failed |
| B. `release.yaml` calls `ci.yaml` | `ci.yaml` | yes | two new ideas: `workflow_call` and `needs` |
| C. a comment "keep in sync" | still two places | yes | relies on remembering |

I chose B, because it keeps the step names and also makes "build once" possible:

```yaml
# ci.yaml
on:
  workflow_call:        # other workflows may call me
  push:
    branches: [main]
  pull_request:
    branches: [main]

# release.yaml
jobs:
  verify:
    uses: ./.github/workflows/ci.yaml
  release:
    needs: verify       # any failed CI step skips this job
```

- The Actions page names a called job `<caller job> / <called job>`, so mine shows `verify / verify`.
- A PR's CI only runs `ci.yaml`. `release.yaml` first ran when I pushed `v1.0.1`, so until a tag is pushed the release path is untested.

### Build once, ship what you tested

Artifacts are shared within one run. So the release job downloads the `dist/` that the `verify` job just built and tested, instead of building again.

Proof, using SHA-256 hashes of every file:

```text
v1.0.1: that run's CI artifact vs the release tarball → IDENTICAL, all 8 files
v1.0.0 (built again separately from the same source)   → also IDENTICAL
```

The twist: rebuilding happened to give identical bytes, because `tsc` is deterministic and the lockfile pins the tools. So E1 turned "same by luck" into "same by design". A rebuild stops matching as soon as something varies: a new runner image (Actions warns that `ubuntu-latest` moves to Ubuntu 26), an unpinned tool, or a timestamp baked into the build. Teams prove it to users with published checksums or artifact attestations (provenance).

A workflow artifact expires (90 days here: the v1.0.1 artifact expires 2027-02-15). A release asset stays.

### Least privilege: `GITHUB_TOKEN` permissions

Every job gets a temporary key, the `GITHUB_TOKEN`. `permissions:` limits what it can do. A called workflow inherits the caller's permissions and can only lower them, never raise them.

```yaml
# release.yaml
permissions:
  contents: read        # default for every job, including the called CI
jobs:
  release:
    permissions:
      contents: write   # only the job that publishes
```

Why it matters: `npm ci` runs install scripts from third-party packages. With `contents: write`, a compromised package could push commits or create releases in my repo.

### Release only reviewed code

A tag isn't tied to a branch. `git tag v1.1.0` on an unreviewed branch triggers the release just the same.

```yaml
validate-tag:
  steps:
    - uses: actions/checkout@v7
      with:
        fetch-depth: 0        # default is 1 commit; the check needs main's history
    - run: |
        if ! git merge-base --is-ancestor "$GITHUB_SHA" origin/main; then
          echo "::error::Release tags must point to a commit in main's history."
          exit 1
        fi
```

- `verify` has `needs: validate-tag`, so a bad tag stops before any CI time is spent. The cost is a few extra seconds on every good release, because the jobs run one after another.
- Local simulation with this exact script: `main` tip → exit 0, older `main` commit → 0, unmerged branch commit → 1, a commit that doesn't exist → 1 (fails safe). I haven't run the refusal on GitHub itself.

**Is "only main" right?** Not universally. Projects that maintain old versions release from release branches: Node.js tags its v22 releases on the `v22.x` branch, CPython on `3.12`, Kubernetes on `release-1.31`. But "so no restriction at all" overcorrects and reopens the hole. The rule is: **release only from branches where code arrives through review**, an allow-list such as `main` + `release/*`. For me (solo, one supported version) that's just `main`.

**What a check inside the workflow can't do:**

- GitHub runs the `release.yaml` **inside the tagged commit**. A commit from before the check, or a branch that deletes the check from its own copy, isn't checked.
- On a private free repo no branch is protected, so I could push straight to `main` and then tag.

So it catches accidents (tagging the wrong branch), not someone deliberately skipping review. Real enforcement happens on GitHub's side: **branch rulesets** (`main` only accepts reviewed PRs with green checks) and **tag rulesets** (only some people may create `v*` tags). Both need a public repo or GitHub Pro.

### Ship only the product

`tsc` compiles every `.ts` file it's given, so the build put the tests into `dist/`. A user's machine has no devDependencies:

```text
import dist/src/task.js       → ok, exports: completeTask, createTask, renameTask
node dist/tests/task.test.js  → Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'vitest'
```

The fix is two tsconfig files:

```jsonc
// tsconfig.build.json — used only by `npm run build`
{
  "extends": "./tsconfig.json",
  "compilerOptions": { "rootDir": "./src" },
  "include": ["src/**/*.ts"]
}
```

- `tsconfig.json` still includes the tests, so `typecheck` still catches errors there. I planted `const n: number = "oops"` in the test file and got exit 2 (TS2322).
- TypeScript 6 refuses `include` without `rootDir`: `TS5011: … The 'rootDir' setting must be explicitly set`. It exits 2, so CI's Build step would go red. With `rootDir: ./src` the output is `dist/task.js` instead of `dist/src/task.js`.
- `tsc` never deletes old output, so `build` runs a `clean` script first. Using `node -e "require('node:fs').rmSync('dist', …)"` instead of `rm -rf dist` also works on Windows.

**Rule:** a release contains the product, not the tools that checked it.

### Two job-order bugs

1. **Downloading the artifact before `actions/checkout`.** Checkout empties a workspace that has no `.git` folder (`Deleting the contents of …` in [actions/checkout's git-directory-helper.ts](https://github.com/actions/checkout/blob/v4/src/git-directory-helper.ts)). The downloaded `dist/` is wiped, `tar` fails, and no release is made. It fails safe, but it never works.
2. **Removing checkout entirely.** `gh` reads `.git` to know which repo it's in:

   ```text
   $ gh release view v1.0.0
   failed to run git: fatal: not a git repository (or any of the parent directories): .git
   $ GH_REPO=selma0817/CICD_testing gh release view v1.0.0
   found release v1.0.0
   ```

   Fix: `GH_REPO: ${{ github.repository }}` in the step's `env:`. A release job without checkout is actually a good design: it can only ship what CI handed it.

### What a failed release leaves behind

I push the tag *before* the workflow runs, and a workflow can't undo my push. If the release fails, the tag still exists with no release attached. To retry, delete the tag (`git push origin --delete vX && git tag -d vX`) and tag again after the fix, or move on to the next version number.

## Round 3: deploy on push in interview-review

On 2026-11-17 and 18 I closed the three interview-review gaps from "Gaps in my own pipelines". PR #1 (`be00445`) made deploys automatic and gated, and a ruleset now protects `main`. A new flashcard now goes PR → CI → merge → deploy, with no button.

### The deploy-on-push pipeline

```text
PR (every update) → ci.yaml: checks … e2e ✅  (pack step skipped)             → nothing published

merge to main     → deploy.yaml run:
                      job ci = ci.yaml: checks … e2e ✅ → pack dist/ ──→ job deploy: hand it to Pages → live
                      └────────────── machine 1: has dist/ ─────────┘    └────── machine 2: empty ──────┘
```

`ci.yaml`, the trigger and the last steps:

```yaml
on:
  workflow_call:          # deploy.yaml may call me
  pull_request:           # no push trigger: deploy.yaml runs CI on main
jobs:
  checks:
    steps:
      # … checkout, setup-node, npm ci, typecheck, bank:validate, test, build …
      - run: npm run test:e2e -- --project=chromium
      - if: github.event_name != 'pull_request'
        uses: actions/upload-pages-artifact@v5
        with:
          path: ./dist
```

`deploy.yaml`, trimmed:

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:      # the "Run workflow" button
jobs:
  ci:
    uses: ./.github/workflows/ci.yaml
  deploy:
    needs: ci
    if: github.ref == 'refs/heads/main'
    permissions: { contents: read, pages: write, id-token: write }
    environment: github-pages
    steps:                # no checkout, no Node, no build
      - uses: actions/configure-pages@v6
      - uses: actions/deploy-pages@v5
```

PR #4's merge, timed (2026-11-19, UTC):

```text
03:31:28  merge → commit b4fe68c on main
03:31:34  ci / checks starts      03:32:10 done ✅  (e2e, then pack dist/)
03:32:15  deploy starts           03:32:29 done ✅
live questions.json   last-modified: Thu, 19 Nov 2026 03:32:25 GMT   ← 57 s from merge to live, no button
```

### Merging a PR is a push to main

A merge adds a new commit to `main`, and GitHub treats that like any other push: every workflow with `on: push: branches: [main]` starts. Squash, merge commit and rebase all count, and so does a plain `git push origin main` (which the ruleset now rejects).

```text
CICD_testing, 2026-11-17
22:09:25  PR #9 merged as commit 19ea27f
22:09:28  push  CI  branch=main  19ea27f       ← 3 s later, event "push"
```

That's why `ci.yaml` lost its own `push: main` trigger. With it, one card PR would run CI three times: on the PR, by itself after the merge, and again when `deploy.yaml` calls it. The last two test the same commit.

The two runs that are left aren't duplicates, because they test different commits. The PR run tested `main` + my branch as they were then (reported on `af96727` in PR #1). The Deploy run tests the squash commit `be00445`, which was created at merge time and had never been tested (see "Semantic conflicts").

### GitHub Pages serves the last deploy, not the repo

With the "GitHub Actions" source, Pages never reads my repo. It serves the files the last deploy uploaded, until the next deploy replaces them.

```text
live questions.json, checked 2026-11-17:  last-modified: Sat, 14 Nov 2026 00:12:10 GMT   ← the Nov 14 deploy
                                          its content last changed in git on 2026-11-05 (69a7f0e)
live questions.json, checked 2026-11-19:  last-modified: Thu, 19 Nov 2026 03:32:25 GMT   ← PR #4's deploy,
                                          which only changed .gitignore
cache-control: max-age=600                ← browsers may also reuse a copy for 10 minutes
```

- The built site isn't in the repo at all. `.gitignore` lists `dist/`, and git tracks 0 files under it. The repo holds the source (TypeScript, `bank/*.json`). `npm run build` turns it into `dist/` (plain JavaScript and `questions.json`) on the runner, and the runner is thrown away after the job.
- So the Pages artifact isn't a download for me. It's the only way the built site reaches Pages, which builds nothing itself.
- Cards are data, not code, but they still go through CI: one malformed card file would break the page that loads them. Loading cards straight from `raw.githubusercontent.com` would skip that check.

### Pack the artifact on the machine that ran e2e

Each job is a fresh machine. The deploy job's machine has no `dist/`, so packing there means building again, which ships a build nobody tested (the "Build once" lesson from Round 2). So `upload-pages-artifact` is the last step of the `checks` job, right after e2e passed on those exact files.

The deploy job then needs no checkout, no setup-node, no `npm ci` and no build. `deploy-pages` fetches the artifact from the same run by itself and hands it to Pages, so there's no download step either. In ci_practice the release job did need `download-artifact`, because `gh release create` uploads files from its own disk.

### Why the pack step checks the event, not the branch

`ci.yaml` starts in three ways. In a called workflow, `github.event_name` is the **caller's** event: GitHub's docs say the `github` context of a reusable workflow always belongs to the caller ([Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)).

| How `ci.yaml` starts | `github.event_name` | Pack `dist/`? |
|---|---|---|
| A PR is opened or updated | `pull_request` | no: nothing will publish it |
| A merge, then `deploy.yaml` calls it | `push` | yes |
| The Run workflow button, then `deploy.yaml` calls it | `workflow_dispatch` | yes |

- `if: github.event_name != 'pull_request'` covers both shipping cases.
- `== 'push'` would forget the button: CI would pass and skip the pack step, and the deploy job would have no artifact to publish.
- Which **branch** may deploy is a separate question, answered on the deploy job (see "Two guards keep other branches off the site").

### `needs:` names a job in the same file

`deploy.yaml` defines two jobs, `ci` and `deploy`, so the deploy job says `needs: ci`. `checks` is the job inside `ci.yaml`; `deploy.yaml` doesn't define it, so `needs: checks` names no job here. In ci_practice the caller's job and the called job were both named `verify`, which hid this.

The same job also reports under two names, depending on what started it:

```text
PR #4 branch commit d6d56ce   check runs: checks                (ci.yaml ran by itself on the PR)
merge commit b4fe68c          check runs: ci / checks, deploy   (inside the Deploy run)
```

### Two guards keep other branches off the site

The Run workflow button (`workflow_dispatch`) has a branch dropdown, and the run uses that branch: `github.ref` is the branch that received the dispatch, and the commit is its latest one ([Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)). The ruleset doesn't help here. It only controls what gets **into** `main`, and the button never goes through `main`.

| Guard | Where it lives | A feature branch run |
|---|---|---|
| `if: github.ref == 'refs/heads/main'` on the deploy job | `deploy.yaml` | the deploy job is skipped; CI can still run |
| `github-pages` environment, deployment branches: `main` only | repo Settings | the deployment isn't allowed |

```text
github-pages environment:  deployment_branch_policy.custom_branch_policies = true
                           branch policies = [{"name": "main", "type": "branch"}]
```

- The `if:` sits on the deploy job, the thing it protects. On the `ci` job it would only work through `needs:`, and it would silently stop working if someone removed `needs:`.
- The `if:` can be deleted on any branch, because the run uses that branch's copy of `deploy.yaml`. The environment rule lives in Settings, which no branch can edit. Two independent layers like this are called **defense in depth**.

### Protecting main with a ruleset

```text
ruleset "no direct push to main"   enforcement: active   target: ~DEFAULT_BRANCH   bypass: []
  deletion, non_fast_forward (no force pushes)
  pull_request: 0 approvals required
  required_status_checks: checks (integration 15368 = GitHub Actions), branch must be up to date
```

- **0 approvals:** GitHub doesn't let a PR's author approve it, and I'm the only person on the repo.
- **Empty bypass list:** not even I, as admin, can skip the rules.
- **Up to date:** if `main` moved after the PR's CI ran, I update the branch first, so CI tests the real combination (the fix from "Semantic conflicts").
- **integration 15368:** the rule wants `checks` reported by GitHub Actions, so another app posting a green `checks` can't open the gate.

I made two setup bugs, and neither showed an error:

1. **No target.** My first save had `"include": []`, so the rules applied to no branch. GitHub only warned: "This ruleset does not target any resources and will not be applied."
2. **The wrong check name.** I required `ci / checks`, the name from a Deploy run. PRs only ever report `checks`, so every PR would wait for a check that never comes, and Merge would never turn on. A gate that never opens fails as badly as one that never closes.

The proof was a direct push to `main`, on purpose:

```text
$ git commit --allow-empty -m "test: direct push should be rejected" && git push origin main
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Required status check "checks" is expected.
remote: - Changes must be made through a pull request.
 ! [remote rejected] main -> main (push declined due to repository rule violations)
```

A rejected push never becomes a push event, so no Deploy ran.

## GitHub Flow for a solo developer

```text
feature/xyz ──PR──▶ CI green ──merge──▶ main ──tag vX.Y.Z──▶ release workflow ──▶ users
```

- **`main` is always releasable.** Unfinished work stays on its branch. A feature that's too big gets split into pieces that are each complete.
- **Hotfix:** branch from `main` → PR → merge → tag the patch version on `main`. No release branch needed.
- **Release branches** only when I must patch an old version while `main` has moved on.
- **Branches live for days, then get deleted.** Turn on Settings → General → "Automatically delete head branches". I don't need to merge a PR to delete its branch: close the PR and click Delete branch, use the Branches page, or run `git push origin --delete <branch>`. Merging an empty PR (my #3 and #4) only adds an empty commit and a CI run to `main`.
- **Wait for green, then merge.** One change per PR, so a red run points at one change.
- **Read the yellow annotations.** "Node.js 20 is deprecated" on the `@v4` actions is a warning today and a failure later.

## Gaps in my own pipelines (as of 2026-11-18)

**interview-review** (rechecked 2026-11-18):

- Fixed on 2026-11-18 (see "Round 3"): `main` was unprotected, the deploy ignored CI's result and skipped e2e, and the deploy rebuilt instead of shipping the checked output.
- **`deploy.yaml` is only tested by real merges.** A PR runs `ci.yaml` alone, so a mistake in `deploy.yaml` first shows up after a merge. It fails safe: `needs: ci` and the environment rule still stop a broken site.
- **Two guards I haven't seen fail yet:** the Run workflow button since the change (does the pack step run on `workflow_dispatch`?), and the `github-pages` environment rule refusing a non-`main` branch.
- `ci.yaml` runs typecheck twice: once as its own step and again inside `build`. Harmless; the separate step fails earlier with a clearer name.

**CMBRater:**

- **Private on the free plan.** Branch protection returns "Upgrade to GitHub Pro or make this repository public", so no red merge or direct push to `main` can be blocked.
- **The typecheck step is the only type gate.** `build` and `test` both strip types.
- **CI never builds what users install.** CI runs only on Ubuntu. The two Electron apps (`apps/client`, `apps/coordinator`) are packaged by hand with `electron-builder --win --x64`.
- **No release workflow, no tags, no code signing**, and no plan yet for versioning two apps in one repo, or for auto-update and rollback.
- **8 merged branches never deleted.**

**ci_practice:** the E2 refusal path hasn't run on GitHub.

## How I'd answer in an interview

**"Walk me through your CI/CD."** Every PR runs CI on a fresh Ubuntu VM: `npm ci` from the lockfile, typecheck, data validation, unit tests, build, then Playwright e2e, cheapest first. PR runs test the merge of my branch into the current `main`. `main` is protected: changes arrive only by PR, with a green `checks` and an up-to-date branch. Each merge triggers the deploy workflow, which calls the same CI workflow on the merged commit and `needs` it, so a red CI skips the deploy. CI packs the `dist/` that passed e2e, and the deploy job publishes that artifact without rebuilding. That's Continuous Deployment, about a minute from merge to live.

**"How do you stop a feature branch from deploying?"** Two independent guards. The deploy job has `if: github.ref == 'refs/heads/main'`, and the Pages environment only allows `main` in the repo's settings, which no branch's YAML can change. Branch protection doesn't help here: a manual run of the workflow on a branch never goes through `main`.

**"How do you keep `main` green with many PRs?"** A PR's green check is about "old `main` + PR". After another PR merges, it's stale, and semantic conflicts merge cleanly as text. So test the exact future `main`: require up-to-date branches, or use a merge queue. And run CI on `main` after merge as a safety net.

**"Delivery vs Deployment?"** Whether a person presses the release button. Deployment removes the person, so it needs more automated safety: e2e, canaries, monitoring, rollback.

**"How do you know the release is what you tested?"** Build once. The release workflow calls CI as a reusable workflow, and the release job downloads the exact artifact that run built and tested, instead of rebuilding. I checked it with SHA-256 hashes: the tarball matched the CI artifact byte for byte. To prove it to users: publish checksums or artifact attestations.

**"How do you keep CI and release checks from drifting apart?"** Keep one list. In my practice repo the release used a separate `npm run ci` script, so a check added only to CI would never guard releases. My interview-review deploy already had that bug: no e2e. Now the release calls the CI workflow and `needs` it.

**"Where do releases come from?"** From branches where code only lands through review: usually `main`, plus release branches if we maintain old versions. I enforce that with protected branches and tag rules, and the release workflow checks the tagged commit is on one of them, so a tag on a feature branch can't publish.

**"What permissions does your pipeline have?"** Read by default. Write only for the one job that publishes. A called workflow inherits the caller's permissions and can only lower them. The reason is that `npm ci` runs third-party install scripts with that token.

## Still to learn

Done in ci_practice: build once, least-privilege `contents` permissions, one list of checks, release only from `main`. Done in interview-review on 2026-11-18: deploy on push to `main`, gated on the full checks including e2e, shipping the tested `dist/`, with `main` protected.

- CMBRater releases: a `windows-latest` runner, packaging both apps in CI, matrix builds
- Windows code signing, with secrets kept away from PR jobs (`pull_request` vs `pull_request_target`)
- Versioning two apps in one repo (one tag, or `client-v…` / `coordinator-v…`)
- Auto-update and rollback for an installed desktop app, plus a smoke test of the packaged app
- `concurrency` and `cancel-in-progress`, environments and approvals, OIDC `id-token: write` vs stored secrets
- Caching, flaky tests, checksums and artifact attestations

## My weak spots (as of 2026-11-17)

1. **Trusting a habit as if it were a gate.** "We always make sure CI passes" (Q2b), "main commits will pass e2e too" (Q2c), and merging PRs #7 and #8 before CI finished. GitHub can't enforce anything on my private repos, so my habits *are* the gate. Ask: **what stops this automatically, and if nothing does, am I actually doing it?**
2. **Right conclusion, shaky reason.** I said v1.0.0 was safe "because it's from main". The real reason was the `npm run ci` gate inside `release.yaml`. Interviewers push on the why. Ask: **which exact line makes this true?**
3. **Losing track of which commit, file or run.** I thought the CI artifact came from the PR (it came from `main`, the same commit). I didn't expect GitHub to use the tagged commit's own `release.yaml`, checkout to empty the workspace, or `gh` to need `.git`. Ask: **which commit, which run, which machine, and what's on its disk right now?**
4. **Look-alike names.** `npm ci` vs `npm run ci`, Delivery vs Deployment (I had them backwards), staged vs tracked, CI runner vs production. Ask: **what does each word literally do?**
5. **Only seeing the happy path.** Almost every run I've watched was green, and I chose not to run the E2 refusal test because I'm confident in the logic. A guard I've never seen fail hasn't been tested, and I've had little practice reading a red run's logs. When something new protects me, trigger its failure once on purpose. First time: on 2026-11-18 I pushed straight to interview-review's `main` and watched the ruleset reject it (GH013).
6. **Bundling changes.** PR #8 mixed the tag check with version updates. If it had gone red, I'd have had to work out which change broke it. One change per PR.

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

From ci_practice on 2026-11-16 and 17.

### Mistake 12: thinking the CI artifact came from the PR branch

It came from the push-to-`main` run on `1b0c2b8`, the same commit as v1.0.0. The same commit was simply built twice, on two machines.

### Mistake 13: "v1.0.0 is safe because it's from main and we always check CI"

`release.yaml` never checked for `main`, and "we always" is a habit, not a gate. The real reason: `release.yaml` ran `npm run ci` before publishing, so a failed check would have skipped the release.

### Mistake 14: "a check I add to ci.yaml will also guard future releases"

The release ran its own list (`npm run ci`). A check added to only one list never guards releases. That's how interview-review's deploy ended up without e2e.

### Mistake 15: mixing up `npm ci` and `npm run ci`

`npm ci` is a clean install and checks nothing. `npm run ci` runs the script named `ci`. A job needs both, install first.

### Mistake 16: thinking a PR's CI also tests the release workflow

A PR only runs `ci.yaml`. `release.yaml` first ran when I pushed the `v1.0.1` tag.

### Mistake 17: downloading the artifact before `actions/checkout`

Checkout empties a workspace with no `.git`, so the downloaded `dist/` disappears.

### Mistake 18: removing checkout without telling `gh` which repo

`gh` reads `.git` to find the repo. Without it: "not a git repository". Set `GH_REPO: ${{ github.repository }}`.

### Mistake 19: merging before CI finished

PR #7 was merged 12 seconds after opening, PR #8 after 10 seconds. Both turned green later, by luck. Wait for the check, then merge.

### Mistake 20: "releases shouldn't be restricted to main, so no restriction"

Right that `main` isn't the only valid source: release branches exist. Wrong to drop the rule entirely. The rule is an allow-list of branches where code arrives through review.

### Mistake 21: merging an empty PR just to get the "Delete branch" button

Close the PR and delete from there, use the Branches page, or run `git push origin --delete <branch>`. An empty merge adds an empty commit and a CI run to `main`.

From the interview-review deploy-on-push exercise on 2026-11-17 and 18.

### Mistake 22: thinking a deploy triggered by the same push waits for CI (mine)

Adding `push: branches: [main]` to `deploy.yml` alone starts both workflows at the same moment, and neither sees the other's result. With e2e broken, CI goes red and the deploy still publishes, about 4 seconds later. Only a link makes it wait: `deploy.yaml` calls `ci.yaml` and `needs` it.

### Mistake 23: thinking the deploy job "runs and fails" when CI fails (mine)

With `needs: ci`, it's skipped: it never starts. Skipped is what a gate looks like.

### Mistake 24: thinking a merged PR isn't a push to main (mine)

A merge adds a commit to `main`, which is a push. PR #9 in CICD_testing merged at 22:09:25, and a `push` CI run started at 22:09:28. Keeping `push: main` in `ci.yaml` would have tested every merged commit twice.

### Mistake 25: thinking GitHub Pages picks up changed files in the repo by itself (mine)

Pages serves what the last deploy uploaded. The live `questions.json` said `last-modified` Nov 14 (the deploy), though its content last changed on Nov 5. The built site isn't even in the repo: `dist/` is gitignored.

### Mistake 26: thinking the site's zip belongs in the deploy job, not in CI (mine)

The deploy job runs on a fresh machine with no `dist/`, so it would have to build again and ship an untested build. Pack `dist/` at the end of the `checks` job, right after e2e. The deploy job needs no checkout, Node or build.

### Mistake 27: thinking the pack step should check the branch (mine)

It checks what started the run: `github.event_name != 'pull_request'`. `== 'push'` would break the Run workflow button (`workflow_dispatch`), whose deploy would find no artifact. The branch check is the deploy job's `if:`.

### Mistake 28: thinking `needs:` can name the job inside the called workflow (mine)

`needs:` names a job in the same file. `deploy.yaml`'s jobs are `ci` and `deploy`, so it's `needs: ci`, not `needs: checks`.

### Mistake 29: thinking the required check is the name shown in a Deploy run (mine)

I required `ci / checks`. On a PR the same job reports as `checks`, so the required check would never arrive and Merge would never turn on.

### Mistake 30: thinking a ruleset applies once its rules are set (mine)

It also needs a target. Mine had `"include": []` and protected nothing until I added the default branch.

## Related notes

- [[Container]]
- [[Dockerfile vs Docker Compose vs Kubernetes]]
- [[TypeScript Types vs Runtime Data]]
- [[Interview MOC]]
