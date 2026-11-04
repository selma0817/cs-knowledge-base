---
date: 2026-11-04
tags:
  - react
  - typescript
  - rendering
  - state
  - hooks
  - closure
  - cmbrater
aliases:
  - react re-render
  - useState vs useRef
  - react snapshot
---
## One-sentence meaning

A render is React calling my component function to get a new description of the UI. State lives inside React, a setter queues a change and asks for a render, and each render sees a fixed snapshot of the state.

## Why I care

CMBRater (Electron + React + TypeScript) is built from components like `App` and `SaveStatus`. Most bugs I can write in it come from getting one of these wrong:

```text
reading a value right after setting it      → old value
a callback holding an old snapshot          → stale state
keeping something in a plain variable       → lost on the next render
keeping something in state that isn't shown → extra renders, stale reads in async code
```

## What a render is

```text
render = React calls App() again
       → gets a new JSX description of the UI
       → compares it with the previous description
       → changes only what differs on the real page
```

A render does **not** rebuild the page. An element with the same type in the same position is kept.

JSX is just a plain object that describes the UI:

```ts
<button onClick={...}>{3}</button>
// becomes
{ type: 'button', props: { onClick: [function], children: 3 } }
```

Tested 2026-11-04 with React 19.3: a counter button clicked 3 times rendered 4 times and produced 4 different JSX objects. The page had 1 `<button>` element the whole time. A mark written on that element after the first render was still there after the third click.

## When a component renders

```text
1. when it first appears (mount)
2. once per batch of its own state updates
3. every time its parent renders, whatever its props are
```

**Batching:** React doesn't render once per setter call. It waits until my code stops running (the handler returns, or pauses at an `await`), then does one render for everything queued so far.

```text
handler with 2 setters                    → 1 render
setter, slow await, then 3 more setters   → 2 renders: the first setter alone, then the other three together
```

Tested 2026-11-04: one click on a handler doing `setA(1); await sleep(50); setB(1); setC(1); setD(1)` gave three renders in total, seeing `0000 → 1000 → 1111` (mount, then the two batches).

`openSession` in `App.tsx` has this shape. The file reads are slow, so `setInfo(session)` gets its own render, and `setProject`, `setEvents`, `setSkippedLines` after the `await` share one.

Dev-only exception: if the root is wrapped in `<StrictMode>`, React calls each component twice per render to catch bugs, so render logs double. CMBRater's `main.tsx` doesn't use it.

## Where state lives

State is not stored in my function. A function's local variables are gone once it returns. React keeps a record for each component instance on the page and hands the values back on every render:

```text
App's record in React:
  slot 0 → info
  slot 1 → project
  ...
1st useState call → slot 0, 2nd → slot 1, ...
```

Slots are matched by **call order**, so hooks must be called in the same order on every render: no hooks inside `if`, loops, or after an early `return`.

### `useState` returns a pair

```tsx
const [label, setLabel] = useState<string | null>(null)

// is the same as
const pair = useState<string | null>(null)
const label = pair[0]    // this render's value
const setLabel = pair[1] // the setter
```

Like Python's `value, setter = pair`. Always destructure it rather than passing the pair around as `label[0]` / `label[1]`.

The pair is a **new array every render**, but the setter inside it is the same function every time. Tested 2026-11-04: an effect that called `label[1](...)` with `label` in its deps re-ran after every render. It started 14 loads in 500 ms with the slice never changing, and the label kept flickering. With deps `[slice]` it started 1 load.

`label[0] = text` does nothing useful. React isn't told, no render is scheduled, and the next render's `useState` hands back a fresh pair from React's slot.

## What a setter does

```text
1. puts my value (or updater function) into that state's queue
2. asks React to schedule a render
3. my current code keeps running with the OLD value
4. next render: useState runs the queue in order → new value → this render's snapshot
```

The setter doesn't change the variable I'm holding. `count` is a `const` for this whole render:

```tsx
setCount(count + 1)
console.log(count) // still the old value
```

### Value vs updater function

A value says "set it to this". A function says "whatever it is when you get to me, do this to it".

```text
count = 0, one click:

setCount(count + 1) ×3    → queue [1, 1, 1]                → 1
setCount(c => c + 1) ×3   → queue [c+1, c+1, c+1]          → 0 → 1 → 2 → 3

setCount(c => c + 1)
setCount(count + 10)
setCount(c => c * 2)      → queue [c+1, 10, c*2]           → 0 → 1 → 10 → 20   (the plain 10 replaces the 1)
```

The last one was tested 2026-11-04: 20, in one render.

Use the updater form when:

```text
several updates to the same state happen in one batch
the code may hold an old snapshot (a callback made with [] deps)
```

CMBRater: `persist` and `toggleOverlays` are `useCallback(..., [])`, so they would see the first render's values forever. They use `setEvents(previous => ...)` and `setOverlays(visible => ...)` instead of reading state.

Separate clicks are fine with the value form. Each click comes after a render, and each render creates a new `onClick` holding that render's value.

```text
one click = one snapshot
the updater form only matters inside one batch, or in an old callback
```

### Put limits inside the updater

```tsx
// ❌ checks a snapshot copy but updates through the queue: two different numbers
function jump(n: number) {
  let cur = slice
  for (let i = 0; i < n; i++) {
    if (cur + 1 <= MAX_SLICE) {
      setSlice((s) => s + 1)
      cur++
    }
  }
}

// ✅ the limit uses the same number as the update
function jump(n: number) {
  setSlice((s) => Math.min(MAX_SLICE, s + n))
}
```

Both work for button clicks, because each click runs a handler from the latest render. Tested 2026-11-04 with a keyboard listener registered once (`useEffect(..., [])`), where `slice` is 0 forever. Five presses gave `5, 10, 15, 20, 25` with the first version and `5, 10, 15, 20, 20` with the second.

CMBRater's `back` does it right: `setReviewOffset((offset) => Math.min(history.length, offset + 1))`.

Rule: if the new value depends on the old one, compute it inside the updater, limit checks included.

## Snapshots and closures

A **snapshot** is the set of state values one render sees. It is made per **render**, not per setter call.

Every function created during a render (an `onClick`, an effect, the code after an `await` inside it) is a closure. It keeps that render's snapshot forever, even after newer renders happen.

## When effects run

```text
render                      → React puts the result on the page
effect                      → runs after that, if a dep changed (always after the first render)
setter called in the effect → another render
```

So the first render always shows the **initial state**. If the page should say "loading…" from the start, the initial state has to mean loading already:

```tsx
const [label, setLabel] = useState<string | null>(null) // null = not loaded yet
// ...
<p>{label ?? 'loading…'}</p>
```

`<string | null>` is needed because `useState(null)` alone infers the type `null`.

Tested 2026-11-04: with `useState("nothing yet")` and `label[1]("loading…")` in the effect, the first render showed "nothing yet". When the load was fast, "loading…" never appeared at all.

### Trace: one change to `slice` costs two renders

Real log from my SliceViewer quiz code (React 19.3). Each `useState` has its own queue.

```text
mount
  RENDER  slice=0   label="nothing yet"         ← initial state, before any effect
  EFFECT  slice=0   ticket 1, set "loading…", start load 0
  RENDER  slice=0   label="loading…"
load 0 arrives
  ARRIVE  ticket 1 === current 1 → set "label for slice 0"
  RENDER  slice=0   label="label for slice 0"
click +5
  CLICK   slice queue: [s+1, s+1, s+1, s+1, s+1]  (one batch)
  RENDER  slice=5   label="label for slice 0"   ← new slice, old label: the effect hasn't run yet
  EFFECT  slice=5   ticket 2, set "loading…", start load 5
  RENDER  slice=5   label="loading…"
click +5 again
  RENDER  slice=10  label="loading…"
  EFFECT  slice=10  ticket 3, set "loading…", start load 10
  RENDER  slice=10  label="loading…"            ← same value, still a render
load 10 arrives first
  ARRIVE  ticket 3 === current 3 → set "label for slice 10"
  RENDER  slice=10  label="label for slice 10"
load 5 arrives late
  ARRIVE  ticket 2 !== current 3 → ignored: nothing queued, no render
```

## `let` vs `useRef` vs `useState`

| | Survives the next render? | Changing it re-renders? | Use for | CMBRater |
| --- | --- | --- | --- | --- |
| `let` / `const` | ❌ recreated every render | — | values computed from props and state during this render | `targetCandidate` |
| `useRef` | ✅ same box every render | ❌ | things to remember but not show | `viewerRef`, `timerRef`, `showToken` |
| `useState` | ✅ | ✅ | things the screen shows | `sliceOffset`, `save`, `events` |

Decision question:

```text
Does the screen show it?                  → useState
Must it be remembered but not shown?      → useRef
Can it be computed from what I have now?  → plain const (useMemo if expensive)
```

`useRef(0)` runs on every render, but like `useState(0)`, React only uses the `0` the first time. After that it returns the same `{ current }` box.

Each component instance gets its own state and refs. Two `<Clicker />`s on the page don't share a ref.

## Pattern: newest-request token

CMBRater's viewer effect (`App.tsx`, the effect on `[project, targetId]`), trimmed:

```tsx
const showToken = useRef(0)

useEffect(() => {
  const token = ++showToken.current                  // take a ticket
  viewerQueue.current = viewerQueue.current.then(async () => {
    if (token !== showToken.current) return          // a newer request exists → stop
    const [swi, labels] = await Promise.all([...])   // slow: large scan files
    if (token !== showToken.current) return
    await viewer.loadSubject(...)
    if (token !== showToken.current) return
    viewer.showCandidate(candidate)
  })
}, [project, targetId])
```

```text
showToken.current = one shared box, the newest ticket handed out
token             = this request's own ticket, a const fixed when it started
```

```text
move to B:      showToken.current 0 → 1   B's token = 1   B starts reading files
Back to C:      showToken.current 1 → 2   C's token = 2   C waits in the queue behind B
B's read ends:  1 !== 2 → return, skip loading B
C runs:         2 === 2 → load and show C
```

`viewerQueue` runs viewer work one step at a time. `showToken` makes older steps stop early.

Why it has to be a ref:

| Version | What B's check reads | Result |
| --- | --- | --- |
| `let showToken = 0` | its own render's counter | never stops anything: B loads anyway |
| `useState` | its render's frozen snapshot | stops everything: nothing ever shows |
| `useRef` | the shared box, read now | stops only older requests |

A ref is the only one of the three that lets a function from an older render read the newest value.

Same idea as a fencing token in [[Distributed Lock]]: a number that only goes up, so whoever holds an older number knows it is stale.

Written from memory in my SliceViewer quiz (2026-11-04), with the fixes from grading:

```tsx
const [label, setLabel] = useState<string | null>(null)
const loadToken = useRef(0)

useEffect(() => {
  const token = ++loadToken.current
  setLabel(null)
  loadSliceLabel(slice).then((text) => {
    if (token !== loadToken.current) return
    setLabel(text)
  })
}, [slice])
```

A `useEffect` function can't be `async` itself, so use `.then(...)` or an inner async function.

## Props

Props are the inputs a parent passes to a child:

```text
data flows down:  App passes save to SaveStatus
events flow up:   App passes onRetry; SaveStatus calls it when clicked
```

```tsx
function SaveStatus({ save, onRetry }: { save: Save; onRetry: () => void })
```

The prop type is a compile-time contract for the **inputs** only. `() => void` is the type of the `onRetry` prop (a function that takes nothing and returns nothing), not the component's output. The component's return type is inferred from what it returns.

Props don't decide **when** a child renders. A child renders when its parent renders, unless it is wrapped in `React.memo`.

A JSX tag is roughly a function call with one props object:

```tsx
<StepButtons slice={slice} max={MAX_SLICE} onStep={handleStep} />
// is roughly
StepButtons({ slice: slice, max: MAX_SLICE, onStep: handleStep })
```

TypeScript checks that object against the props type. Passing `max` to a child whose type doesn't list it fails with `Property 'max' does not exist on type ...`. Inside the arrow `onStep={(delta) => ...}`, `delta` needs no annotation, because TypeScript reads it from the props type.

Everything a child needs should come in through its props. Don't let it read the parent's constants such as `MAX_SLICE`.

### Keep the rule where the state lives

A disabled button is UI, not a rule. The parent owns `slice`, so the parent's update clamps both ends:

```tsx
onStep={(delta) => setSlice((s) => Math.max(0, Math.min(MAX_SLICE, s + delta)))}
```

Otherwise any other caller can push it out of range. In CMBRater, ArrowUp/ArrowDown step slices without touching a button.

```text
higher-order function:   takes or returns a function (array.map(fn), useCallback)
higher-order component:  takes a component, returns a new component
SaveStatus:              a normal component that receives a callback prop
```

## Common mistakes

From my quiz rounds (2026-11-03 to 2026-11-04) and the SliceViewer coding quiz (2026-11-04).

### Mistake 1: thinking a re-render rebuilds the page

I guessed the canvas, the `<h1>` and the `<button>` get recreated. They don't. Only the differences are applied to the page.

### Mistake 2: reading state right after setting it

```tsx
setCount(count + 1)
console.log(count) // old value
```

### Mistake 3: repeating `setCount(count + 1)` in one handler

Every call reads the same snapshot, so three calls add 1, not 3. Use `setCount(c => c + 1)`.

### Mistake 4: applying Mistake 3 to separate clicks

Each click gets a new render and a new snapshot. `setN(n + 1)` on 3 separate clicks gives 3.

### Mistake 5: thinking one setter call means one render

React batches. Two setters in one click give one render.

### Mistake 6: thinking `useRef(0)` resets every render

The `0` is only the initial value. The box keeps its contents.

### Mistake 7: thinking only the component whose state changed re-renders

Its children re-render too, whatever their props are.

### Mistake 8: keeping "the latest value" in state for async code to check

Async code reads the snapshot from the render that created it. Use a ref.

### Mistake 9: calling a component that receives a callback a higher-order component

A higher-order component takes a component and returns one.

### Mistake 10: checking a limit against a snapshot copy

Copying `slice` into a local and counting it up while queueing `s => s + 1` means the check and the update read different numbers. They agree on clicks but drift apart in an old closure. Put the limit inside the updater.

### Mistake 11: relying on a disabled button to enforce a rule

The component that owns the state clamps it. Buttons only reflect the rule.

### Mistake 12: expecting a setter in an effect to show on the first render

Effects run after the render is on the page, so the first render shows the initial state. Make the initial state mean "loading".

### Mistake 13: using `label[0]` / `label[1]` instead of destructuring

The pair is a new array every render. If it goes into an effect's deps, the effect re-runs forever.

## Related notes

- [[TypeScript Types vs Runtime Data]]
    
- [[Distributed Lock]]
