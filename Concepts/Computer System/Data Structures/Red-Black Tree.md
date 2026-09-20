---
date: 2026-09-15
aliases:
  - red-black tree
  - red black tree
  - self-balancing BST
  - balanced binary search tree
  - AVL tree
  - rotation
---
A **red-black tree** is a self-balancing binary search tree that guarantees O(log n) search, insert, and delete by keeping its height within a constant factor of log n, no matter what order keys arrive.

## Why plain BSTs are not enough

A binary search tree gives O(log n) operations only when it is **balanced**. Feed a plain BST keys in **sorted order** and every insert goes to the right, producing a degenerate spine:

```
1
 \
  2
   \
    3
     \
      4      height = n, search = O(n) — a linked list in disguise
```

This is the trap behind treeifying a hash bucket (see [[Hash Map]]): the whole point is to survive **adversarial** input, and an attacker can trivially feed keys whose hashes are already ordered. A plain BST would degrade right back to O(n). Only a **self-balancing** tree keeps the height at O(log n) regardless of insertion order — which is why Java uses a red-black tree, not a BST.

> Balance is not a nice-to-have; it is the entire guarantee. An unbalanced BST offers no better worst case than a linked list.

## The red-black invariants

Each node is colored red or black. The coloring rules force the tree to stay approximately balanced:

1. Every node is red or black.
2. The root is black.
3. Every leaf (the null sentinel `NIL`) is black.
4. A red node's children are both black (no two reds in a row).
5. Every root-to-leaf path passes through the **same number of black nodes** (the "black height").

The consequence: rule 5 fixes the black height, and rule 4 says reds cannot cluster, so the longest possible path (alternating red/black) is at most **twice** the shortest (all black). That bounds height at **≤ 2·log₂(n+1)** — still O(log n).

> Invariants 4 and 5 together mean the longest path is at most twice the shortest, which is what keeps height logarithmic.

## Restoring balance: rotations and recoloring

Insertion and deletion can violate the invariants (e.g. inserting a red child under a red parent breaks rule 4). The tree repairs itself with two cheap, **local** operations:

**Rotation** restructures three nodes while preserving BST order:

```
    y                x
   / \    right→    / \
  x   C   ←left    A   y
 / \                  / \
A   B                B   C
```

A left or right rotation is O(1) — it just repoints a few pointers. **Recoloring** flips node colors. Insert/delete fixups walk **up** from the modified node, applying a bounded number of rotations and recolorings until the invariants hold again. Because the tree is O(log n) tall and each level's fixup is O(1), rebalancing is **O(log n)** with at most a **constant number of rotations** per operation.

## Red-black vs AVL

Both are self-balancing BSTs with O(log n) operations; they differ in *how strictly* they balance:

| Red-black tree | AVL tree |
| --- | --- |
| Loose balance: height ≤ 2·log₂(n+1) | Strict balance: height ≤ ~1.44·log₂n |
| Fewer rotations on insert/delete (≤ a small constant) | More rotations to maintain stricter balance |
| Faster **mutation** | Faster **lookup** (shallower tree) |
| Chosen when writes are frequent | Chosen when reads dominate |

Java's `TreeMap`/`HashMap` and the C++ `std::map` use red-black trees because they favor cheaper updates; AVL wins in read-mostly workloads that want the shallowest possible tree.

## Where red-black trees show up

- **Java** `TreeMap`, `TreeSet`, and `HashMap` bucket treeification.
- **C++** `std::map` / `std::set` (typical implementation).
- **Linux kernel** — the Completely Fair Scheduler orders runnable tasks by virtual runtime in a red-black tree; also used for virtual memory area (VMA) lookups.

Note the language contrast: **Go and Python ship no built-in red-black tree.** Python's `dict`/`set` and Go's `map` are hash tables; for ordered/range queries you reach for a sorted slice with binary search, a third-party balanced-tree or B-tree package, or a skip list. In systems code, ordered on-disk data usually uses a **B-tree/B+-tree** (higher fan-out, disk-block friendly) rather than a binary red-black tree.

## Interview summary

> A red-black tree is a self-balancing BST that guarantees O(log n) operations regardless of insertion order, which a plain BST cannot (it degenerates to O(n) on sorted input). Five color invariants — notably no two consecutive red nodes and equal black height on every path — bound the longest path to at most twice the shortest, keeping height logarithmic. Insert/delete restore invariants with O(1) rotations and recoloring walking up the tree, so rebalancing is O(log n) with a constant number of rotations. Red-black balances more loosely than AVL, trading slightly deeper trees for cheaper mutations, which is why write-heavy structures (Java maps, C++ std::map, the Linux CFS scheduler) prefer it. Go and Python have no built-in red-black tree.

## Related notes

- [[Hash Map]]
- [[Cache Coherence and MESI]]
