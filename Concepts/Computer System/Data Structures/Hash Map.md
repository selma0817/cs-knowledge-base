---
date: 2026-09-15
aliases:
  - hash map
  - hash table
  - HashMap
  - dictionary
  - dict
  - separate chaining
  - open addressing
  - load factor
  - rehashing
  - hash flooding
  - treeification
---
A **hash map** stores key–value pairs with average O(1) insert, lookup, and delete by converting each key into an array index. Its real subtleties are collision handling, resizing, and worst-case degradation under adversarial input.

## The hashing pipeline: key → index → address

Reading or writing `m["cat"]` runs the same three-stage funnel:

```
"cat"  --hash function-->  3892745123        (hash code: a big integer)
                              │  compress:  index = hash % capacity
                              │  (real impls use hash & (capacity-1) for power-of-2 capacity)
                              ▼
                          index 7  ──►  buckets[7]
```

The buckets are **one contiguous array allocated all at once**. Reaching bucket `i` is pure arithmetic, not a search:

```
address_of(bucket i) = base + i × slot_size
```

That arithmetic is the O(1). Collisions can arise at **either** stage: two keys with different hash codes can still collide after `% capacity`.

> Capacity = the number of buckets (the length of the bucket array), not the size of any one bucket.

## Collisions are inevitable

The key space is far larger than the number of buckets, so by the **pigeonhole principle** distinct keys must sometimes share a bucket. Two strategies handle this:

**Separate chaining** — each bucket slot holds a **pointer to a list (or tree)** of entries; nodes are heap-allocated and scattered:

```
 buckets (contiguous)          heap (scattered nodes)
 ┌──────┐
 │ slot7├──────►[ "cat":5 ]──►[ "dog":9 ]──►nil
 └──────┘
```

**Open addressing** — entries live **directly in the array**; on collision you **probe** for another slot (linear `i+1,i+2,…`, quadratic `i+1,i+4,i+9,…`, or double hashing):

```
 ┌───────────┬───────────┬───────────┬───────────┐
 │           │ "cat":5   │           │ "dog":9   │   entries stored inline
 └───────────┴───────────┴───────────┴───────────┘
```

Open addressing is more cache-friendly (everything in one block, no pointer chasing) but must resize before getting too full. Java `HashMap` uses chaining; Python `dict` and Go `map` are closer to open addressing.

## Load factor and resizing

Buckets are kept short by watching the whole table's **load factor**, not any single bucket:

```
load factor = total entry count / number of buckets
```

When it crosses a threshold (Java **0.75**, Python **~2/3**, Go **~6.5** per 8-slot bucket) the *entire table* resizes:

```
1. TRIGGER:   count/capacity crosses the threshold.
2. ALLOCATE:  a new bucket array, usually 2× capacity (power of 2).
3. REHASH:    for EVERY entry, recompute index = hash % new_capacity, move it.
4. SWAP+FREE: point the map at the new array; free the old one.
5. RESULT:    load factor halves; buckets are short again.
```

Every entry must move because the index depends on `capacity`, which just changed. That is **O(n)**, but it happens only once per doubling (every ~n inserts), so **amortized insertion stays O(1)** — the same amortization as a growable array. Resizing doubles the **number of bins** (the denominator), spreading the same entries thinner.

**Power-of-2 masking trick.** With `index = hash & (capacity-1)`, doubling capacity exposes one more hash bit, so each old bucket splits into exactly two new ones:

```
Old cap 8  → hash & 0111        New cap 16 → hash & 1111  (one new bit)
  new bit = 0 → stays at index i
  new bit = 1 → moves to index i + old_capacity
```

Java 8 uses this to split each chain into a "stay" and a "move" list without recomputing full hashes.

**All-at-once vs. incremental** — a real tail-latency tradeoff:

- **Java / Python: stop-the-world.** The insert that crosses the threshold pays the whole O(n) rehash → a latency spike.
- **Go: incremental ("evacuation").** Allocates the new array but migrates a few buckets per subsequent write, keeping both arrays during migration, so no single write eats the full cost.
- **Redis dict: incremental rehashing** — keeps two tables and migrates a bit per command, because a stop-the-world rehash would stall its single thread.

> Same total work; stop-the-world spikes one operation to O(n), incremental smears migration across many operations to bound tail latency.

## Worst-case degradation and treeification

If many keys land in one bucket, that bucket's list lookup becomes **O(n)**. Java 8 defends structurally: when a single bucket's chain exceeds length **8** (and capacity ≥ 64), it converts that chain from a **linked list into a red-black tree**, changing the worst-case single-bucket lookup from **O(n) → O(log n)**. It untreeifies back to a list below length **6** (the 6/8 gap avoids flip-flopping).

Why a threshold rather than always using a tree: tree nodes cost more memory (child/parent pointers, color bit) and more complex inserts, and on short chains O(n) over tiny n with good cache locality beats a tree. Under a decent hash at load factor 0.75, bucket length follows a **Poisson distribution** — the chance a bucket ever reaches 8 is about **6 in ten million**. So treeification essentially never fires on honest input; it is a **safety net for adversarial or broken hashes**. See [[Red-Black Tree]] for why a *self-balancing* tree (not a plain BST) is required.

## Hash flooding (the DoS that motivated treeification)

An attacker who can craft keys that all hash to one bucket turns bulk insertion from O(n) into **O(n²)**: inserting n colliding keys costs 1+2+…+n. Any endpoint that parses **untrusted keys into a map** is exposed — HTTP form/POST parameters, JSON object keys, headers, query strings. A single small request can pin a CPU core. This was a coordinated disclosure in **2011 ("28C3 hashDoS")** hitting PHP, Java, Ruby, Python, ASP.NET, and is exactly why Java 8 added treeification (worst case becomes O(n log n) instead of O(n²)).

> Any endpoint dumping untrusted keys into a hash map is a hash-flooding target. Defend it structurally (trees) or at the hash-function layer (randomized seed).

## Deterministic hashing: per-run, not eternal

A hash function for an in-memory table must be deterministic **only for the lifetime of that table**, not across processes. Model it as `index = hash(seed, key) % capacity`, where the **seed is fixed once** (process start, or map creation) and never changes during the map's life. So within one run, `"cat"` always maps to the same bucket; only *across* runs does the mapping differ. That is fine — a map never needs cross-process agreement.

This is what lets **Go and Python defend at the hash-function layer** instead of with trees:

- **Python `dict`:** open addressing, no trees; since Python 3.4 (PEP 456) strings are hashed with **SipHash keyed by a per-process random seed**, so an attacker cannot predict which keys collide.
- **Go `map`:** seeds each map's hash with a **random value at creation**; buckets hold **8 slots** with **overflow buckets** chained when full and no trees; iteration order is deliberately randomized.

Contrast with hashing that *does* need eternal, cross-machine determinism — sharding, consistent hashing, on-disk indexes, checksums (MD5/SHA), Git object IDs — which must use **fixed, unseeded** functions. Java kept `String.hashCode()` fixed and public (a portable spec attackers can exploit offline), which is precisely why Java needed the **structural** tree defense.

> Same threat, two philosophies. Java keeps a stable, attackable hash and treeifies the bad bucket (O(log n)). Go/Python randomize the seed so the colliding keys cannot be constructed at all — and never need trees.

## Interview summary

> A hash map maps key → hash code → bucket index (`hash % capacity`) → an O(1) array offset. Collisions are inevitable (pigeonhole) and handled by separate chaining (lists/trees off the array) or open addressing (probing within the array). The table-wide load factor triggers resizing: allocate ~2× buckets and rehash every entry (O(n), amortized O(1)); power-of-2 masking splits each bucket in two; resizing can be stop-the-world (Java/Python) or incremental (Go/Redis). A single overloaded bucket degrades to O(n); Java 8 treeifies chains past length 8 into a red-black tree (O(log n)) to survive hash-flooding DoS. Go and Python instead randomize the hash seed (Go per-map, Python SipHash per-process) so collisions cannot be engineered, and use no trees. Hash determinism is required only per-run, which is what makes randomized seeding safe.

## Related notes

- [[Red-Black Tree]]
- [[Cache Coherence and MESI]]
- [[Concurrency vs Parallelism]]
