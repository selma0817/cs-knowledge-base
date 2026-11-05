---
date: 2026-11-04
tags:
  - typescript
  - types
  - runtime
  - validation
  - narrowing
  - type-guard
  - cmbrater
aliases:
  - type erasure
  - any vs unknown
  - type predicate
  - runtime validation
---
## One-sentence meaning

TypeScript types exist only before the code runs. At runtime there are only values, so data that comes from outside the program (files, IPC) has to be checked by real code, and narrowing is how those checks become types TypeScript can trust.

## Why I care

CMBRater reads JSON files from a shared drive and passes data between two processes. TypeScript never sees any of that data. If a value has the wrong type, the typecheck doesn't fail. The app fails later, somewhere else, with an error that doesn't mention the file the bad value came from.

## Types are erased

electron-vite strips types without checking them. Only `npm run typecheck` (`tsc --noEmit`) checks.

```ts
// what I write (contracts.ts)
export const DECISIONS = ['yes', 'no', 'unsure', 'skip'] as const
export type Decision = (typeof DECISIONS)[number]

// what runs
export const DECISIONS = ['yes', 'no', 'unsure', 'skip']
```

Using a type where a runtime value is needed fails:

```text
error TS2693: 'Decision' only refers to a type, but is being used as a value here.
```

At runtime a value only has JavaScript's own coarse kind:

```text
typeof 'hi'             → "string"
typeof 5                → "number"
typeof candidateTable   → "object"
typeof plan             → "object"   ← same answer: the runtime can't tell them apart
typeof []               → "object"   ← use Array.isArray
typeof null             → "object"   ← a bug from JavaScript's first version; null is not an object
```

So code can't ask "is this a `CandidateTable`?". It can only check one field at a time.

### One runtime list, one derived type

```text
const DECISIONS = [...]     the NAME can't be reassigned          DECISIONS = []            ✗
                            the CONTENTS can still change         DECISIONS.push('maybe')   ✓
                            so the type is string[]          →    Decision = string

[...] as const              the CONTENTS are fixed as written: readonly, each item its own literal type
                                                             →    Decision = 'yes' | 'no' | 'unsure' | 'skip'
```

Tested 2026-11-04: without `as const`, `const d: Decision = 'maybe'` compiles. With it:

```text
error TS2322: Type '"maybe"' is not assignable to type '"yes" | "no" | "unsure" | "skip"'.
error TS2339: Property 'push' does not exist on type 'readonly ["yes", "no", "unsure", "skip"]'.
```

The array exists at runtime, so `isDecision` can check against it. The type is derived from the array, so the two can never disagree. `as const` is erased too: it doesn't freeze the real array.

## `any`, `unknown`, `as`

| | What tsc does | What happens at runtime |
| --- | --- | --- |
| `any` | turns checking off for this value and everything read from it | nothing is checked |
| `unknown` | knows nothing, so refuses every use until I check | nothing is checked; I have to do it |
| `as X` | believes me | nothing: no check, no conversion |

`as` is not Java's cast. Java's `(String) obj` is checked at runtime and throws `ClassCastException`. TypeScript's `as` is deleted.

```ts
function a(x: any)     { return x.toFixed(2) }   // compiles; a('hello') → TypeError: x.toFixed is not a function
function b(x: unknown) { return x.toFixed(2) }   // error TS18046: 'x' is of type 'unknown'.
```

`JSON.parse` returns `any`, so there are three ways to take its result:

```text
const t = JSON.parse(text)                     any              anything compiles, nothing is checked
const t = JSON.parse(text) as CandidateTable   CandidateTable   tsc believes me, nothing is checked
const t: unknown = JSON.parse(text)            unknown          nothing compiles until I check
```

### Honest vs dishonest `as`

An `as` is honest when it claims no more than has already been checked.

| `as` in CMBRater | Claims | Checked by then | |
| --- | --- | --- | --- |
| `value as Record<string, unknown>` (events.ts) | an object, every field unknown | object, not null | ✅ |
| `DECISIONS as readonly string[]` (events.ts) | an array of strings | more than that | ✅ claims less than known |
| `JSON.parse(...) as CandidateTable` (store.ts) | every field of every candidate | only `schema`, afterwards | ❌ |
| `JSON.parse(...) as Plan` (store.ts) | every field of the plan | nothing | ❌ |

A type annotation on a value that arrives as `any` is a hidden `as`. Electron types IPC handler arguments as `...args: any[]`, so in `main/index.ts` this compiles without any check:

```ts
ipcMain.handle('cmbrater:readFile', (_event, relativePath: string) => ...)
```

## Narrowing

**Narrowing** is tsc reading a real check in my code and treating the value as a narrower type in the branch where the check passed.

Two things happen at two different times:

```text
when it runs:     typeof x === 'number' is a real JavaScript check of the real value
before it runs:   tsc reads the if and treats x as a number inside it (tsc runs nothing)
```

It works on any union, not just `unknown`: `string | null`, `Save`, and so on.

**What makes it safe:** the narrower type is only used in code that runs after a real check has passed. It stops being safe when the "check" isn't real: an `as`, or a predicate whose body doesn't keep its promise.

The toolbox. Every tool is a real runtime check that tsc understands:

```text
typeof x === 'number'      typeof check
value === null             equality check
Array.isArray(x)           array check
save.state === 'failed'    tag check (discriminated union)
isRatingInput(value)       type predicate: several checks bundled into a function
```

### Discriminated unions

```ts
type Save =
  | { state: 'idle' }
  | { state: 'saving'; input: RatingInput }
  | { state: 'saved'; decision: Decision }
  | { state: 'failed'; input: RatingInput; message: string }
```

The union is erased, but the `state` field is real data in the object, so checking it is a real runtime check. Tested 2026-11-04:

```ts
if (save.state === 'failed') save.message   // ✅
if (save.state === 'saving') save.message   // error TS2339: Property 'message' does not exist on type '{ state: "saving"; ... }'.
save.input                                  // error TS2339: Property 'input' does not exist on type 'Save'. (idle has none)
```

With no check, only fields that every member has can be read.

### Type predicates

```ts
function isNum1(x: unknown): boolean     { return typeof x === 'number' }
function isNum2(x: unknown): x is number { return typeof x === 'number' }
function isNum3(x: unknown): x is number { return true }   // lies

const v: unknown = JSON.parse('"hello"')
if (isNum1(v)) v.toFixed(2)   // error TS18046: 'v' is of type 'unknown'. (boolean tells tsc nothing)
if (isNum2(v)) v.toFixed(2)   // compiles; the if is false, nothing runs
if (isNum3(v)) v.toFixed(2)   // compiles; TypeError: v.toFixed is not a function
```

`x is T` means "if I return true, treat `x` as `T`". tsc never checks that the body keeps that promise, so a lying predicate is as unsafe as `as`.

### Walkthrough: `isRatingInput` (events.ts)

```ts
export function isRatingInput(value: unknown): value is RatingInput {
  if (typeof value !== 'object' || value === null) return false   // 1. a real object
  const v = value as Record<string, unknown>                      // 2. honest as: every field unknown
  return (
    isText(v.id) &&                                               // 3. check every field
    isText(v.candidate) &&
    isText(v.candidate_set) &&
    isDecision(v.decision) &&
    isNumber(v.viewing_ms) &&
    v.viewing_ms >= 0 &&                                          //    narrowed to number by the line above
    isNumber(v.plan_version)
  )
}
```

What tsc says if a step is skipped (tested 2026-11-04):

```text
read value.id before step 1:     error TS18046: 'value' is of type 'unknown'.
read value.id after step 1:      error TS2339: Property 'id' does not exist on type 'object'.
const id: string = v.id          error TS2322: Type 'unknown' is not assignable to type 'string'.
```

Why step 1 needs both halves:

```text
(5).id          → undefined
"hi".id         → undefined
null.id         → TypeError: Cannot read properties of null (reading 'id')
undefined.id    → TypeError: Cannot read properties of undefined (reading 'id')
```

## Where data needs a runtime check

tsc only checks code that is compiled together as one program. Anything that crosses into the program from outside arrives as text or as a copied message, so its type is a promise nobody has checked. Those crossing points are **trust boundaries**.

```text
 shared drive                      main process (Node)              renderer (React)
 candidates.json ── JSON.parse ──►  store.ts   ◄──── IPC: requests ────  App.tsx
 plans/*.json    ── JSON.parse ──►             ───── IPC: replies ────►
 ratings/*.jsonl ── JSON.parse ──►
```

| Where data enters | Code | Checked? |
| --- | --- | --- |
| ratings `*.jsonl` → main | `parseEventLines`: `unknown` + `isRatingEvent` | ✅ every field; damaged lines skipped and counted |
| `candidates.json` → main | `readCandidates`: was `as CandidateTable`, now `parseCandidateTable` (2026-11-04) | ✅ every field (was ⚠️ only `schema`) |
| `plans/<rater>.json` → main | `readPlan`: `as Plan` | ❌ nothing |
| renderer → main: `appendRating` | `input: unknown` + `isRatingInput` | ✅ |
| renderer → main: `unsavedWork` | `value: unknown`, then `value === true` | ✅ |
| renderer → main: `readFile` | `relativePath: string` + `resolveInside` | ⚠️ the path can't leave the project folder, but being a string is assumed |
| main → renderer: every reply | preload: `ipcRenderer.invoke` returns `any`, typed by `CmbRaterApi` | trusted: main is my own privileged side |

Why main checks requests from the renderer, even though I wrote both sides:
- They are separate programs. Messages are copied between processes, so each side's types are only a promise.
- In Electron the renderer is the less trusted side: it shows content and has no Node access. Main can read files, so main decides what it agrees to do. `resolveInside` refuses any path that leaves the project folder.

**Rule: check at the door.** Validate data once, where it enters, then everything inside can trust its types. How deep to check depends on how much I trust the source and how bad a mistake would be.

What a skipped check costs. If `candidates.json` had `"swi": 42` for some subject, `readCandidates` would accept it, and the renderer would later ask main for `readFile(42)`. That ends in `path.isAbsolute(42)` inside `resolveInside`:

```text
TypeError: The "path" argument must be of type string. Received type number (42)
```

The error comes from Node's `path` module in a different process, and it doesn't mention `candidates.json`.

The fix for `readCandidates` is in [[#Practice: `isCandidateTable`]] below. It was applied to CMBRater on 2026-11-04 as `shared/candidates.ts`.

## Practice: `isCandidateTable`

A guard for `candidates.json` plus a parse function for `readCandidates` to call. `isSubjectEntry` follows the same pattern as `isRatingInput`.

```ts
export function isVec3(value: unknown): value is Vec3 {
  return Array.isArray(value) && value.length === 3 && value.every(isNumber)
}

export function isCandidate(value: unknown): value is Candidate {
  if (typeof value !== 'object' || value === null) return false
  const v = value as Record<string, unknown>
  if (typeof v.bbox_vox !== 'object' || v.bbox_vox === null) return false   // nested object: same two steps again
  const bbox = v.bbox_vox as Record<string, unknown>
  return (
    isText(v.id) &&
    isText(v.subject) &&
    isText(v.candidate_set) &&
    isNumber(v.label) &&
    isNumber(v.voxel_count) &&
    isNumber(v.volume_mm3) &&
    isVec3(v.centroid_vox) &&
    isVec3(v.centroid_mm) &&
    isVec3(bbox.min) &&
    isVec3(bbox.max) &&
    isVec3(v.extent_mm) &&
    isNumber(v.elongation) &&
    Array.isArray(v.flags) &&
    v.flags.every((flag) => typeof flag === 'string')   // may be empty
  )
}

export function isCandidateTable(value: unknown): value is CandidateTable {
  if (typeof value !== 'object' || value === null) return false
  const v = value as Record<string, unknown>
  const subjects = v.subjects
  return (
    isNumber(v.schema) &&
    typeof subjects === 'object' &&
    subjects !== null &&
    !Array.isArray(subjects) &&                 // typeof [] is "object" too
    Object.values(subjects).every(isSubjectEntry) &&
    Array.isArray(v.candidates) &&
    v.candidates.every(isCandidate)
  )
}

export function parseCandidateTable(text: string): CandidateTable {
  const value: unknown = JSON.parse(text)
  // Schema first, so a future format gets the clear error. value is unknown, so check it's an object before reading .schema.
  const schema = typeof value === 'object' && value !== null ? (value as Record<string, unknown>).schema : undefined
  if (schema !== SCHEMA_VERSION) throw new Error(`Unsupported candidate table schema ${String(schema)}`)
  if (!isCandidateTable(value)) throw new Error('candidates.json does not match the candidate table format')
  return value
}
```

Then `readCandidates` becomes `return parseCandidateTable(await fs.readFile(resolveInside(this.root, CANDIDATES_FILE), 'utf8'))`.

In CMBRater the guards live in `shared/candidates.ts`, reusing `isText` and `isNumber` exported from `events.ts`, and 15 tests were added to `shared.test.ts`. The real `candidates.json` parses in about 0.4 ms.

Tested 2026-11-04 with 23 checks: valid tables (including the real `candidates.json`, 280 candidates), 17 broken ones, and 3 parse cases. Strict typecheck OK.

```text
this version                    23/23
only top-level checks           10/23   accepted "subject": 42, "swi": 42, a null candidate, subjects: [] ...
                                        and said "Invalid candidates.json" for a schema-2 file
always returns false            19/23   passes every reject case, fails every valid table
```

### Checklist for writing a guard

```text
1. object and not null before reading any field
2. honest as to Record<string, unknown>, again for every nested object
3. every field gets its own check
     arrays:   Array.isArray + .every(check)
     records:  object, not null, !Array.isArray, Object.values(...).every(check)
4. allow extra fields: the real candidates.json has a "prep" field the type doesn't list
5. test with real data as well as broken data: a guard that rejects everything passes every reject test
6. at the door: clearest error first (schema), and name the file in the message
```

`readPlan` (`as Plan`, no check) needs the same treatment.

## Common mistakes

From my quiz rounds, 2026-11-04.

### Mistake 1: thinking types turn into something at runtime

They are deleted. What's left are values with JavaScript's coarse kinds.

### Mistake 2: thinking `const` fixes an array's contents

`const` fixes the name. `as const` makes the type exact and readonly.

### Mistake 3: thinking `typeof` "infers the type at runtime"

`typeof` is a plain JavaScript check. The narrowing is done by tsc, before the code runs, by reading that check.

### Mistake 4: thinking `as` checks or converts like a Java cast

It is deleted. It only changes what tsc believes.

### Mistake 5: thinking the typecheck can catch bad JSON behind `as`

tsc checks code, not data. It never sees the file.

### Mistake 6: forgetting `typeof null === 'object'`

An object check needs `typeof value === 'object' && value !== null`.

### Mistake 7: returning `boolean` where a type predicate is needed

`boolean` tells tsc nothing. `value is T` narrows the caller's value.

### Mistake 8: writing a predicate whose body doesn't keep its promise

tsc trusts the predicate's signature and never checks its body.

### Mistake 9: annotating an `any` input and calling it checked

`(_event, relativePath: string) =>` on an IPC handler is an unchecked `as`.

## Related notes

- [[React Rendering and State]]
    
- [[Compiler vs Interpreter]]
