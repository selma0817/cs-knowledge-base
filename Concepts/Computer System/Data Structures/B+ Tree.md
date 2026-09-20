---
date: 2026-09-15
aliases:
  - B+ tree
  - B+tree
  - B-tree
  - Btree
  - fan-out
  - database index structure
---
A **B+-tree** is a balanced, high-fan-out search tree in which all data lives in the leaves and leaves are linked in order. It is the structure databases and filesystems use to index **on-disk** data, where the cost that matters is the number of page reads.

## Why not a binary tree on disk

The unit of disk/SSD I/O is a **page** (block) — InnoDB uses **16 KB**. One tree node is stored as one page. Because a page holds hundreds of keys, each node has hundreds of children (**high fan-out**), so the tree is very shallow:

```
B+-tree over ~hundreds of millions of rows  →  3–4 levels  →  3–4 page reads
Red-black tree over the same data           →  ~30+ levels →  ~30 random seeks
```

A binary tree ([[Red-Black Tree]]) stores one key per node, so every level is a *random* disk seek — the worst possible access pattern. On disk you minimize the **number of page reads**, not the number of comparisons. Internal nodes are also usually cached in memory (InnoDB's **buffer pool**), so a lookup often costs just one real leaf I/O.

> On disk, shallow beats balanced-but-tall. High fan-out → few page reads → fast. That is the entire reason B+-trees win over binary trees for storage.

## B-tree vs B+-tree

| B-tree | B+-tree |
| --- | --- |
| Data/values stored in **all** nodes (internal + leaf) | Data stored **only in leaves** |
| Internal nodes carry payload → fewer keys per node | Internal nodes hold **only separator keys** → more keys per node → higher fan-out, shallower |
| Leaves **not linked** | Leaves form a **sorted linked list** |
| Range scans need in-order up/down traversal | Range scans walk the leaf linked list sequentially |

Because B+-tree internal nodes store only routing keys (copies of keys used to steer the search, no row payload), they pack more keys per page, raising fan-out and lowering height.

## Why range scans are fast

```
WHERE age BETWEEN 20 AND 30:
  1. Descend from the root ONCE to find the leaf holding 20.
  2. Walk the leaf linked list rightward until you pass 30.
```

Step 2 is **sequential I/O** across linked leaves — no re-descending from the root per row. This is why B+-trees dominate for range queries, `ORDER BY`, and prefix scans, and why a plain B-tree (scattered values, unlinked leaves) cannot match them.

## Balance and occupancy

A B+-tree stays balanced by construction: inserts fill a leaf, and a full leaf **splits**, pushing a separator key up; splits can cascade to the root, which is the only way height grows (so all leaves stay at the same depth). Deletes may **merge** underfull nodes. Nodes are kept at least ~half full, bounding wasted space.

## Where B+-trees are used

- **Databases:** the primary storage structure for InnoDB (MySQL), PostgreSQL, SQLite indexes — see [[Database Indexing]].
- **Filesystems:** NTFS, HFS+, ext4 (HTree), and others index directories/extents with B-tree/B+-tree variants.
- Any ordered, disk-resident key structure needing fast point *and* range lookups.

## Interview summary

> A B+-tree is a balanced, high-fan-out tree storing all data in linked leaves, used to index on-disk data because it minimizes page reads. Each node is one page (e.g. 16 KB); high fan-out makes the tree only 3–4 levels deep over hundreds of millions of rows, versus ~30 random seeks for a binary tree. Unlike a B-tree, a B+-tree keeps payload only in leaves (so internal nodes pack more routing keys and stay shallow) and links leaves in sorted order, which makes range scans a single descent plus a sequential leaf walk. It is the backbone of database and filesystem indexes.

## Related notes

- [[Database Indexing]]
- [[Red-Black Tree]]
- [[Hash Map]]
