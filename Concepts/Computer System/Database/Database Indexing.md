---
date: 2026-09-15
aliases:
  - database index
  - database indexing
  - clustered index
  - secondary index
  - covering index
  - composite index
  - leftmost prefix
  - back to table
  - 回表
  - index invalidation
  - 索引失效
  - InnoDB index
---
A **database index** is a [[B+ Tree]] that lets queries find rows without scanning the whole table. In InnoDB the table *is* an index, so understanding clustered vs. secondary indexes, back-to-table lookups, composite ordering, and when indexes silently fail is the core of query performance.

## Clustered vs. secondary index (InnoDB)

- **Clustered index** — organized by the **primary key**; rows are physically stored **in PK order** and the **leaf holds the entire row**. The table *is* the clustered index. If there is no primary key, InnoDB uses the first `UNIQUE NOT NULL` index, and failing that generates a hidden 6-byte `DB_ROW_ID`.
- **Secondary index** — a separate B+-tree keyed on other columns; its **leaf stores the indexed columns + the primary key**, *not* the row.

Because the PK is duplicated inside **every** secondary index, the PK should be **small and monotonic** (e.g. `BIGINT AUTO_INCREMENT`) — see the UUID note below.

## 回表 (back-to-table)

Querying a non-covered column through a secondary index takes **two** lookups:

```
SELECT name FROM t WHERE email = 'x';   (index on email, name not in it)
  1. Search the secondary index by email → get the primary key.
  2. Search the CLUSTERED index by that PK → get the row (name).   ← 回表
```

That second clustered lookup is **回表 / back-to-table**, and it is a random I/O per matched row — the main reason low-selectivity queries avoid indexes.

## Covering index

If the secondary index **already contains every column the query needs**, InnoDB answers entirely from its leaves and **skips 回表**:

```
INDEX(email, name);   SELECT name WHERE email = 'x';   → no back-to-table
```

`EXPLAIN` shows `Using index`. A secondary index implicitly contains the PK, so `INDEX(email)` already **covers** `SELECT id, email WHERE email = ?` for free (id is the PK stored in the leaf). Covering indexes are one of the highest-leverage optimizations.

## Composite indexes: leftmost prefix and the range rule

An `INDEX(a, b, c)` is sorted by `a`, then `b` within equal `a`, then `c` within equal `(a,b)`. Two rules govern its use:

**Leftmost prefix** — the index can seek only on a **contiguous prefix starting from the left**. With `INDEX(last_name, first_name, age)`:

| Query | Uses index |
| --- | --- |
| `last_name = ?` | ✅ prefix of 1 |
| `last_name = ? AND first_name = ?` | ✅ prefix of 2 |
| `first_name = ?` | ❌ no leftmost `last_name` → full scan* |
| `last_name = ? AND age = ?` | ⚠️ seeks `last_name`; `age` is a filter (gap at `first_name`) |

**Range stops the seek** — the index can seek up to and **including the first range condition** (`>`, `<`, `BETWEEN`, `LIKE 'x%'`); every column after the range becomes a filter, not a seek:

```
INDEX(a, b):
  WHERE a = 10 AND b > 5   → seeks a, then range-seeks b        ✅ both used
  WHERE a > 10 AND b = 5   → range-seeks a; b is only a filter  ⚠️ b not a seek
```

Once `a` is a *range*, `b` is not globally sorted across that range, so `b` cannot be sought.

> Design rule: **put equality columns first, range/sort columns last.** `*` Skip-scan (MySQL 8.0+) can occasionally use a non-leftmost column when the leading column has very few distinct values.

## Index design principles

- **Equality first, range/`ORDER BY` last** in composite indexes.
- An index whose column order matches an `ORDER BY` provides the sort **for free** (no filesort) and lets `LIMIT` stop early; InnoDB can read the index backward for `DESC`.
- Prefer **covering** indexes for hot read paths to eliminate 回表.
- Keep the **primary key small and monotonic**; it is copied into every secondary index.
- Every index adds **write cost** (each `INSERT`/`UPDATE`/`DELETE` maintains every affected index) and storage/buffer-pool pressure. Index for real query patterns; drop unused indexes.

**Random UUID PK is bad for writes.** Rows are stored in PK order, so an `AUTO_INCREMENT` PK always appends to the rightmost page (sequential, few splits). A random UUID lands at random positions, forcing **page splits** (a full 16 KB page splits in two to make room) → fragmentation, random write I/O, buffer-pool churn, and 16-byte bloat in every secondary index. Fix: `AUTO_INCREMENT`, or a time-ordered UUID (UUIDv7 / `UUID_TO_BIN(uuid, true)`).

## Index失效 (invalidation)

Two flavors: **structural** (the query shape makes the index unusable) and **cost-based** (usable but the optimizer judges a scan cheaper).

Structural:
1. **Function/expression on the column** — `WHERE YEAR(created_at) = 2020`, `WHERE UPPER(name) = 'X'`. The index stores raw values. Fix: rewrite as a range, or use a **functional index**.
2. **Arithmetic on the column** — `WHERE id + 1 = 5`; move the math to the constant side.
3. **Implicit type conversion** — `VARCHAR` column compared to a number (`WHERE phone = 138...`) coerces the *column* → index dead. Quote the literal.
4. **Leading wildcard** — `LIKE '%abc'` cannot seek; `LIKE 'abc%'` can.
5. **Leftmost-prefix violation** — querying a non-leading composite column.
6. **`OR` across an unindexed column** — often a full scan (an index merge is possible if both sides are indexed).
7. **Negation** — `!=`, `<>`, `NOT IN` usually cannot seek.

Cost-based:
8. **Low selectivity** — if a predicate matches a large fraction of rows (e.g. `status = 'active'` at 95%), index + 回表 for most rows costs more than one sequential full scan, so the optimizer correctly chooses the scan. Past ~20–30% of the table, scans usually win. A **covering** index removes 回表 and can flip this back.
9. **Stale statistics** — a wrong cardinality estimate makes the optimizer misjudge selectivity; fix with `ANALYZE TABLE`.

> Structural failure = the index *can't* be used (function/type/prefix/wildcard). Cost-based = the index *isn't worth* using (selectivity/stats). A highly selective predicate that still full-scans is almost always structural or stale-stats, not a legitimate cost decision.

## Reading EXPLAIN

Access-type hierarchy, best → worst:

```
const / eq_ref  >  ref  >  range  >  index  >  ALL
PK/unique hit      non-uniq  range    full     full
                   eq lookup  scan     index    table
                                       scan     scan
```

Also watch: `Using index` = covering (great); `Using index condition` = **Index Condition Pushdown** (filter pushed into the index scan before 回表); `Using filesort` / `Using temporary` = sorting or temp table (often an index-design opportunity).

## Applied patterns

- **Function in `WHERE` → rewrite as a range.** `DATE(created_at) = '2024-01-15'` (unindexed) → `created_at >= '2024-01-15' AND created_at < '2024-01-16'` (range seek).
- **Deep pagination is slow.** `LIMIT 20 OFFSET 1000000` must walk and discard a million index entries. Use **keyset / seek pagination**: `WHERE id > :last_seen ORDER BY id LIMIT 20` — an index seek that is O(1) regardless of page depth (trade-off: next/prev only, no jump-to-page).

## Interview summary

> InnoDB stores the table as a clustered B+-tree keyed on the primary key (leaf = full row); secondary indexes are separate B+-trees whose leaves hold indexed columns + the PK. Reading a non-covered column needs a second clustered lookup (回表); a covering index that holds all needed columns avoids it. Composite indexes seek only on a leftmost contiguous prefix and only up to the first range condition, so put equality columns first and range/sort columns last; a matching index order also satisfies ORDER BY for free. Indexes fail structurally (function/expression, type coercion, leading wildcard, prefix gap) or by cost (low selectivity, stale stats) — a highly selective predicate that still scans is usually structural. Keep the PK small and monotonic (random UUIDs cause page splits), and remember function→range rewrites and keyset pagination as the two most common applied fixes.

## Related notes

- [[B+ Tree]]
- [[Red-Black Tree]]
- [[Hash Map]]
