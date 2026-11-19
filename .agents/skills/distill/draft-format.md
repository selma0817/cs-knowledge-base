# Draft file format

A drafts file is a JSON array of draft cards, saved to `~/Desktop/interview-review/.drafts/<YYYY-MM-DD>-<topic-slug>.json` (gitignored). `bank:add` turns each draft into a card: it assigns the `id`, copies `topics` from the cited notes' `topic/` tags, sets `version` to 1 and `created` to today, and stamps each source with its git `blob_sha` and a URL pinned to the vault commit.

## Fields

| Field | Required | Notes |
|---|---|---|
| `type` | yes | `single_choice`, `flashcard`, `short_answer` or `code_reading` |
| `difficulty` | yes | `easy`, `medium` or `hard` (see the style guide) |
| `question` | yes | Markdown; code goes in a fenced block |
| `options` | `single_choice` only | `[{"id": "A", "text": "…"}, …]`, 2–4 options |
| `answer` | yes | the option ID for `single_choice`; otherwise the model answer |
| `explanation` | yes | why, in a few lines; can be `""` for a flashcard |
| `rubric` | optional | 3–5 checkable points, mainly for `short_answer` |
| `code_language` | `code_reading` | e.g. `go`, `typescript`, `python` |
| `extension_note` | optional | a pointer for going deeper |
| `sources` | yes | `[{"path": "<vault path>", "heading": "<exact heading text>"}]`, at least one |
| `provenance` | yes | one sentence naming the session moment |
| `checks` | yes | `{"grounded": "pass", "blind_answer": "pass" or "n/a", "code_run": "pass" or "n/a"}` |

**Never include** `id`, `topic` or `topics` (`bank:add` refuses them). `version` and `created` are optional and default to 1 and today. Any other field is rejected.

`heading` is the heading text exactly as written, without the `#` marks. `path` is relative to the vault root.

## Examples

These show the shape only; they're illustrative, not cards to add.

```json
[
  {
    "type": "single_choice",
    "difficulty": "medium",
    "question": "You add `push: branches: [main]` to a deploy workflow that never looks at CI's result. A commit breaks e2e. What reaches the live site?",
    "options": [
      {"id": "A", "text": "Nothing: CI fails, so the deploy is skipped"},
      {"id": "B", "text": "The broken commit: CI goes red, but the deploy runs anyway"},
      {"id": "C", "text": "The previous commit: GitHub rolls back automatically"},
      {"id": "D", "text": "Nothing: the push is rejected until CI passes"}
    ],
    "answer": "B",
    "explanation": "Workflows are independent unless linked. CI's red result is a report nobody waits for; the deploy workflow starts at the same moment and publishes. A is the belief that a check is automatically a gate.",
    "sources": [{"path": "Concepts/Software Engineering/DevOps/CI and CD.md", "heading": "Gate vs report"}],
    "provenance": "You answered that the deploy wouldn't run, but that was the linked design, not the naive push trigger.",
    "checks": {"grounded": "pass", "blind_answer": "pass", "code_run": "n/a"}
  },
  {
    "type": "short_answer",
    "difficulty": "hard",
    "question": "A term-4 leader finds an entry from term 2 stored on a majority of servers. Why can't it mark that entry committed just by counting replicas?",
    "answer": "Because a server whose log ends in a later, conflicting term could still win an election and overwrite it. The leader commits only entries from its own term by counting; older entries are committed indirectly once a current-term entry after them is.",
    "explanation": "Once a majority stores a current-term entry, any future candidate missing it is too stale to win votes from that majority, so counting is safe only for current-term entries.",
    "rubric": [
      "a later leader could overwrite a majority-stored old-term entry",
      "only current-term entries are committed by counting",
      "older entries are committed indirectly, once a current-term entry after them commits"
    ],
    "sources": [{"path": "Concepts/Distributed Systems/Raft/Raft Commitment and Application.md", "heading": "Why direct commitment requires the current term"}],
    "provenance": "You knew the rule but couldn't give the counterexample.",
    "checks": {"grounded": "pass", "blind_answer": "n/a", "code_run": "n/a"}
  },
  {
    "type": "flashcard",
    "difficulty": "easy",
    "question": "What is an inverted index?",
    "answer": "A map from each word to the documents (and positions) that contain it, so a search looks words up instead of scanning every document.",
    "explanation": "",
    "sources": [{"path": "Concepts/LLM/Retrieval/Full-Text Search.md", "heading": "Inverted index"}],
    "provenance": "Your own definition from the search session.",
    "checks": {"grounded": "pass", "blind_answer": "n/a", "code_run": "n/a"}
  },
  {
    "type": "code_reading",
    "difficulty": "medium",
    "code_language": "go",
    "question": "```go\nfunc fetch() string {\n    ch := make(chan string)\n    go func() { ch <- slowCall() }()\n    select {\n    case r := <-ch:\n        return r\n    case <-time.After(100 * time.Millisecond):\n        return \"timeout\"\n    }\n}\n```\nfetch() times out. What happens to the goroutine, and what is the smallest fix?",
    "answer": "It leaks: its send on the unbuffered channel blocks forever, because nobody receives after the timeout. Fix: make the channel buffered with capacity 1, so the send completes and the goroutine exits.",
    "explanation": "An unbuffered send needs a receiver. After select returns via the timeout, no receiver remains.",
    "sources": [{"path": "Concepts/Programming Languages/Go/Concurrency/Go Channel Pitfalls and Internals.md", "heading": "Goroutine leaks"}],
    "provenance": "You missed this leak in quiz round 2.",
    "checks": {"grounded": "pass", "blind_answer": "n/a", "code_run": "pass"}
  }
]
```
