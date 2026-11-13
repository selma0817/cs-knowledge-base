---
date: 2026-11-12
tags:
  - ai/llm/retrieval
  - search
  - elasticsearch
  - interview
aliases:
  - full-text search
  - inverted index
  - posting list
  - analyzer
  - tokenizer
  - BM25
  - IDF
  - Lucene segments
  - near real-time search
---
## One-sentence meaning

A full-text search engine cuts text into words with an **analyzer**, stores a map from each word to the notes that contain it (the **inverted index**), ranks matches with **BM25**, and handles edits by writing new **segments** instead of changing old ones.

## Why I care

- I wanted to know if Elasticsearch would help me search this vault. Working through it on my own notes showed my real problem isn't speed. It's **what counts as a match** and **which note ranks first**.
- BM25 is the "sparse" half of [[Hybrid Retrieval]]. Before this note I could name it but not explain it.
- Common interview questions: "how does Elasticsearch work?", "why is it near real-time?", "why not just `LIKE '%x%'` or grep?", "would you use Elasticsearch for X?"

My vault on 2026-11-12: 132 notes, about 122,000 words, 808 KB of text. A plain `grep -rli` over all of it takes **14 ms**. Speed is not the problem.

## grep vs a search engine: what counts as a match?

Searching for "lock" in my vault:

| Command | Notes matched | Problem |
|---|---|---|
| `grep -rli lock` (any word containing "lock") | 74 | 36 notes only match through other words |
| `grep -rliw lock` (whole word only) | 27 | misses locks / locking / locked |
| lock, locks, locking or locked as whole words | 38 | about half of the 74 |

What lets the extra notes into the 74:
- **Unrelated words** containing the letters: blocks (108 times), block (72), blocking (44), clock. `B+ Tree.md` matches because of one "block". `UDP.md` matches because of one "blocking".
- **Related words**: deadlock, unlock, RLock. Whether "deadlock" should match "lock" is a design decision.

What `-w` breaks: 11 notes say only "locks", "locking" or "locked", including `Transactions and Isolation Levels.md` and `MySQL Storage Engines.md`, which are two of my database-locking notes. It also misses `pthread_mutex_lock`, because `_` counts as part of a word.

A separate problem neither setting fixes: 4 notes say "mutex" but never any form of "lock" (for example `Goroutines and Channels.md`). That's a **different word for the same idea**, which keyword search can't solve. Embeddings can ([[Vector Databases and ANN Search]]).

**Precision** = what fraction of the results are right. **Recall** = what fraction of the right notes were found. grep only gives two settings: 74 results (high recall, low precision) or 27 (better precision, lower recall). A search engine replaces raw character matching with a rule for what a word is.

## Analyzer: what counts as a word

The analyzer is the rule that decides how text is cut into pieces (also called *terms* or *tokens*). It runs on **both** the notes (when they're indexed) **and** the search text, so the pieces line up. If notes were lowercased but searches weren't, `Mutex` would never find `mutex`.

A typical analyzer: clean characters → cut into pieces → adjust the pieces (lowercase, `locking` → `lock`, which is called *stemming*).

Testing a simple rule (lowercase, cut at anything that isn't a letter or digit) on lines from my notes:

| Text | Pieces | What goes wrong | Type of problem |
|---|---|---|---|
| `lock-free` (GMP Scheduler Internals) | lock, free | also matches notes with "lock" in one place and "free the memory" in another | lost the fact the words were **next to each other** → store positions |
| `sync.RWMutex` | sync, rwmutex | searching `mutex` misses it | piece **too big** |
| `C++` | c | searching `C++` matches 29 notes with a lone "c" (`c, err :=` in Go code, `C[Chunkserver]` in diagrams, `INDEX(a, b, c)`). None are about C++ | cut **threw away** the characters that mattered |
| `异常情况：LLM 陷入循环 / 重复调同一个 tool` (Agent Developer Mock Interview, line 21) | 异常情况, llm, 陷入循环, 重复调同一个, tool | searching `循环` misses it. Line 16's `里循环调` hides it too | piece **too big**: Chinese has no spaces |

Possible fixes: split at case changes (RW | Mutex), rewrite `c++` as `cplusplus` before cutting, and for Chinese, one of three methods:

| Method | `陷入循环` becomes | Cost |
|---|---|---|
| One character each (Elasticsearch's default `standard` analyzer) | 陷 / 入 / 循 / 环 | Searches match **any** piece by default, so `循环` also matches line 138 (`在分布式环境下…`), which only shares 环 (in 环境, "environment"). A phrase search (循 directly followed by 环) fixes this |
| Overlapping pairs (`cjk` analyzer) | 陷入 / 入循 / 循环 | No word list needed, and it never misses a two-character word. Junk pairs like 入循 make the index bigger and cause some false matches |
| Word list (IK, smartcn, jieba plugins) | 陷入 / 循环 | Cleanest pieces, but a word missing from the list gets cut wrong, and new tech jargon usually is missing |

My pick for this vault: **pairs**. Real systems often run pairs and a word list side by side.

## Inverted index

A normal index goes from a note to its words. An **inverted** index goes from each word to a **sorted** list of the notes that contain it (a *posting list*).

Four of my notes, using just their titles:

| ID | Title |
|---|---|
| 1 | Go Scheduler |
| 2 | Go Channel Pitfalls and Internals |
| 3 | Raft Concurrency and Locking in Go |
| 4 | MVCC and Locking |

```text
go        → [1, 2, 3]
and       → [2, 3, 4]
locking   → [3, 4]
scheduler → [1]   channel → [2]   raft → [3]   mvcc → [4]   ...
```

A search reads only the lists for its words and **never opens a note**, so the cost depends on how many notes contain the word, not how big the vault is.

### AND search: walk two sorted lists with two fingers

```text
go:      [1, 2, 3]        locking: [3, 4]
1 vs 3 → 1 is smaller, move the go finger
2 vs 3 → 2 is smaller, move the go finger
3 vs 3 → match, record 3, move both
go list ended → result [3]
```

Each finger only moves forward, so each list is read once. Cost is **list A + list B**, not **list A × list B**. In my vault, "the" is in 125 notes and "mvcc" in 6. Sorted, that's at most 131 steps instead of 750. Lucene, the library inside Elasticsearch, also starts from the shortest list and **jumps ahead** in the long one.

### What each list entry stores

```text
go → [ 1 (×1, @1),  2 (×1, @1),  3 (×1, @6) ]
        ID  count  positions
```

- **Note ID**: which note.
- **Count** in that note: needed by BM25, stored right where the walk already is.
- **Positions**: needed for phrase search. Note 3 is Raft(1) Concurrency(2) and(3) Locking(4) in(5) Go(6). The phrase "locking go" doesn't match note 3 (positions 4 and 6 aren't adjacent). The phrase "and locking" matches notes 3 and 4.
- **Note length** is stored **separately, once per note** (Lucene calls these *norms*).
- **Number of notes containing a word** = the length of its list.

## BM25: ranking

What I need at 132 notes is ranking, not speed. BM25 scores a note on three ideas:

1. **More mentions → higher score, but it plateaus.** After about 25 mentions the note is clearly about the word, and the 100th mention adds almost nothing. That also stops keyword stuffing.
2. **Longer than the average note → lower score**, but only partly.
3. **Word appears in fewer notes → higher weight** (IDF, inverse document frequency). Count the **notes containing** the word, not its total mentions.

### The plateau (note of average length, 928 words)

| "lock" count | 1 | 2 | 5 | 10 | 25 | 100 | 1000 |
|---|---|---|---|---|---|---|---|
| score part | 1.00 | 1.38 | 1.77 | 1.96 | 2.10 | 2.17 | 2.20 |

**k1** (default 1.2) controls how quickly it flattens. The ceiling is k1 + 1 = 2.2.

### Length: why not just divide by length?

Plain count ÷ length over-rewards short notes. In my vault, `Interview MOC.md` (just a list of links, "lock" 1 time in 314 words = 0.32%) would beat `Go Channel Pitfalls and Internals.md` (11 times in 3,694 words = 0.30%).

BM25 doesn't divide the score. Length changes **how many mentions a note needs before it plateaus**, measured against the vault's average. The same 7 mentions:

| Note length | 300 | 547 | 928 (avg) | 2,000 | 3,694 |
|---|---|---|---|---|---|
| score part | 2.03 | 1.97 | 1.88 | 1.67 | 1.41 |

**b** (default 0.75) sets how much length counts. **b = 0** ignores length, which gives the raw-count ranking. **b = 1** counts length fully, close to plain division, so the MOC notes win again.

### Rare words weigh more

Example: "render" appears 70 times, but all in **one** note, so it's very rare. Total mentions would call it common. Using total mentions would also double-count repetition that idea 1 already rewards.

| Word | Notes containing it (of 132) | IDF |
|---|---|---|
| the | 125 | 0.06 |
| lock | 27 | 1.58 |
| mvcc | 6 | 3.02 |
| render | 1 | 4.49 |

### The formula

```text
score(note, query) = Σ over query words  IDF(word) × count × (k1 + 1) / (count + k1 × (1 − b + b × length / avg_length))

IDF(word) = ln(1 + (N − n + 0.5) / (n + 0.5))      N = notes in the vault, n = notes containing the word
```

Lucene leaves out the constant `(k1 + 1)` because it doesn't change the order. Elasticsearch's `_explain` output will be my numbers ÷ 2.2. My lengths are `wc -w` counts, while Lucene counts the analyzer's pieces and stores length approximately, so exact scores will differ a little.

### My vault, query "lock"

| Note | count / words | Raw count rank | count ÷ length rank | **BM25 rank** |
|---|---|---|---|---|
| Distributed Lock | 24 / 865 | 2 | 1 | **1** |
| Mutex | 25 / 1,014 | 1 | 2 | **2** |
| Compare-and-Swap | 22 / 1,361 | 3 | 3 | **3** |
| Raft Concurrency and Locking in Go | 7 / 547 | 7 | 4 | **4** |
| Hash Map | 16 / 1,982 | 5 | 5 | **5** |
| Go Map and Slice Thread Safety | 16 / 2,787 | 4 | 7 | **6** |
| Concurrency MOC | 3 / 457 | 8 | 6 | **7** |
| Go Channel Pitfalls and Internals | 11 / 3,694 | 6 | 9 | **8** |
| Interview MOC | 1 / 314 | 9 | 8 | **9** |

The short, focused Raft note beats the long Go Channel note, and both MOCs fall below the real notes.

### Near ties are honest; other words break them

The top three all sit on the flat part of the curve, so for "lock" alone they're nearly tied. A second, rarer word decides the winner:

| Search | Winner | Runner-up |
|---|---|---|
| `lock` | Distributed Lock 3.31 | Mutex 3.30 |
| `redis lock` | Distributed Lock 7.84 (redis ×15) | Mutex 3.30 |
| `cas lock` | Compare-and-Swap 9.32 (cas ×42) | Distributed Lock 3.31 |
| `mutex lock` | Mutex 6.40 (mutex ×29) | Compare-and-Swap 6.05 |

## Editing a note: segments

**Approach 1: edit the lists in place.** Changing note 1 to "Go Scheduler Locking" turns `locking → [3, 4]` into `[1, 3, 4]`. The 1 goes at the front, so everything shifts. A search walking that list at the same moment can skip an entry, read one twice, or read a half-written one. Preventing that needs a lock, and even with a read-write lock (`sync.RWMutex`, see [[Mutex]]) every search **waits** while a write happens.

**Elasticsearch's answer: never change a segment once it's written.**

```text
Segment A (old):  go → [1,2,3]  locking → [3,4]  scheduler → [1]   deleted bits: {1}
Segment B (new):  go → [5]      locking → [5]    scheduler → [5]   (5 = new version of note 1)

search "locking"   → A [3,4] + B [5]            = [3, 4, 5]
search "scheduler" → A [1] is deleted, B [5]    = [5]
```

- A **segment** is a small, finished index. It holds **everything that changed since the last refresh**, not one segment per edited note.
- **Deletes** are recorded in a small side file per segment, with one bit per note (Lucene's *live docs*). The segment itself never changes. An "update" is really **mark the old version deleted, plus add the new one**.
- A search checks every segment, combines the results and skips deleted notes.
- **Merge**: in the background, small segments are combined. The merge copies **only live notes** into a new segment and throws the old ones away. That's when the old version of note 1 finally disappears and its space is freed.

```text
Segment A: 1, 2, 3, 4   (1 deleted)  +  Segment B: 5
        ↓ merge copies only live notes
New segment: 2, 3, 4, 5      → A and B are deleted
```

- **Refresh**: building a segment costs work, so Elasticsearch collects changes and turns them into a new segment on a **schedule, once a second** (`refresh_interval`). A note saved at 10:00:00.2 is not found at 10:00:00.5. It shows up at the next refresh, at most about a second later. That's why Elasticsearch is called **near real-time**. Refreshing after every edit would make lots of tiny segments and more merging.

What this buys: searches read segments that never change, so they **run during writes with no lock and no waiting**. The costs:
- about 1 second before a change can be found
- background merging that uses CPU and disk
- old versions taking up space until a merge removes them

It's the same idea as Postgres MVCC in [[MVCC and Locking]]: an update writes a new row version and marks the old one dead, readers don't wait, and VACUUM cleans up later. Table bloat before VACUUM is the same thing as deleted notes taking space before a merge.

## Should my vault use Elasticsearch?

Not as the daily tool. For 132 notes it's too heavy: a Java server using 1–2 GB of RAM, plus a second copy of my notes that I'd have to keep in sync with every edit. What I need now is **ranking**, not scale. I can get BM25 without a server by building my own index, or with SQLite's built-in full-text search (FTS5, which has a `bm25()` function).

Elasticsearch earns its weight when:
- the data no longer fits on one machine
- many people search at the same time
- search has to stay up when a machine fails (replicas)
- changes have to show up in search within about a second while edits keep coming in

As a learning project it's worth it: build the small version first, then map each Elasticsearch feature onto what I built.

## My definitions

1. **Inverted index**: a map from each word to a sorted list of the notes containing it. A search reads only its words' lists, never the notes. Because the lists are sorted, an AND search walks each list once, so the cost adds instead of multiplies.
2. **Analyzer**: the rule that decides how text is cut into pieces. It runs on both the notes and the search text so the pieces match. If notes were lowercased but searches weren't, `Mutex` wouldn't find `mutex`.
3. **BM25**: more mentions → higher score, but it plateaus. Longer than the average note → lower. In fewer notes → higher.
4. **Segments**: when a note changes, Elasticsearch writes a new segment instead of editing the old one, so searches keep running during writes. Costs: about 1 second before the change is searchable, background merging, and old versions taking space until merged.
5. **Verdict**: for my 132-note vault Elasticsearch is too heavy (RAM, a server, a second copy to keep in sync). I need ranking, which I can get without a server. Elasticsearch makes sense when the data outgrows one machine, many users search at once, or search must stay up and stay fresh under constant writes.

## How I'd answer in an interview

- **"How does Elasticsearch work?"** An analyzer cuts text into terms. An inverted index maps each term to a sorted posting list (IDs, counts, positions). A query reads only its terms' lists and intersects them in one pass. BM25 ranks the matches. Writes go into immutable segments that become searchable on refresh and get merged in the background.
- **"Why is it near real-time?"** New documents sit in memory until the next refresh (every 1 s by default) turns them into a searchable segment.
- **"Why not `LIKE '%lock%'` or grep?"** It reads all the text on every query, matches characters instead of words (74 notes for "lock", mostly "block"), and has no ranking.
- **"Would you use Elasticsearch here?"** Size it to the problem: ranking can come from SQLite FTS5 or Postgres full-text search. Elasticsearch is for scale, many users at once, high availability, or fresh search under heavy writes, and you pay with a second copy to keep in sync.

> **Interview summary:** Full-text search = analyzer → inverted index → BM25 → segments. The analyzer decides what a term is and runs on both documents and queries. The inverted index maps terms to sorted posting lists (IDs, term counts, positions), so a query never scans documents and an AND is a single merge pass. BM25 ranks by term count with a plateau (k1), length relative to the average (b), and rarity across documents (IDF). Elasticsearch writes immutable segments: updates are delete + add, a refresh every second makes new segments searchable (near real-time), and background merges drop deleted documents. Readers never wait on writers, at the cost of a short delay, merge work, and space held by deleted documents.

## Still to learn

- **Stage 1, build it**: an inverted index + BM25 over this vault in about 100 lines. Compare its top results for "lock" with grep's 74.
- **Stage 2, Elasticsearch in Docker**: use `_analyze` to see how it actually splits `sync.RWMutex`, `C++` and Chinese. Use `_explain` to check BM25 against the numbers above (÷ 2.2). Learn mappings (boost the title field, since "Raft Concurrency and Locking in Go" has "Locking" in its title), shards and replicas, and the translog (durability, which is a separate thing from refresh).
- Deleted documents still count toward "notes containing the word" until they're merged away.
- Searching by **paragraph** instead of whole notes (passage retrieval), which is the same chunking problem as in [[Retrieval-Augmented Generation]].
- **Stage 3**: add embeddings and combine both result lists with RRF ([[Hybrid Retrieval]]), so "mutex" notes can be found by a "lock" search.

## Common mistakes

### Mistake 1: thinking I need to "rank keywords"

You rank **notes** (or paragraphs). Keywords get **weights** (IDF), and the weights feed into the note's score.

### Mistake 2: forgetting that matching comes before ranking

Ranking only orders the matches you have. If the match set is wrong (74 notes, mostly "block"), ranking can't fix it.

### Mistake 3: blaming `grep -w` for the "mutex" misses

Plain grep misses those notes too. That's the "different word for the same idea" problem. What `-w` actually breaks is other forms of the word: 11 notes with only locks/locking/locked.

### Mistake 4: "just break the text into smaller pieces"

Sometimes the pieces are too big (`rwmutex`, `陷入循环`). Sometimes the cut throws away what mattered (`C++` → `c`). Smaller isn't always the fix.

### Mistake 5: measuring rarity by total mentions in the vault

Count the **notes** containing the word. "render" appears 70 times in one note, so it's rare.

### Mistake 6: dividing count by note length

The MOC notes win. BM25 compares each note's length to the average and only partly applies it (b = 0.75).

### Mistake 7: expecting 100 mentions to score 4× higher than 25

The score plateaus (k1). Past about 25 mentions, more adds almost nothing.

### Mistake 8: "环 and 循 both match"

Line 138 contains only 环. A search that matches **any** piece needs only one. A phrase search (循 directly followed by 环) fixes it.

### Mistake 9: thinking a merge keeps both the old and new versions

A merge copies only live notes. The deleted version is dropped, and that's when its space is freed.

### Mistake 10: thinking a note shows up exactly 1 second after I save it

Refresh runs on a once-a-second schedule. The note shows up at the next refresh, so the wait is at most about a second.

### Mistake 11: thinking search and writes still have to take turns

That was the problem with editing lists in place. Segments never change after they're written, so searches run during writes with no lock.

## Related notes

- [[Hybrid Retrieval]]
- [[Vector Databases and ANN Search]]
- [[Retrieval-Augmented Generation]]
- [[Database Indexing]]
- [[MVCC and Locking]]
- [[Mutex]]
- [[Interview MOC]]
