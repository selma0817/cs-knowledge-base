---
date: 2026-09-15
aliases:
  - vector database
  - ANN
  - approximate nearest neighbor
  - HNSW
  - IVF
  - pgvector
  - Chroma
  - Milvus
  - embeddings
tags:
  - ai/llm/retrieval
  - ai/systems
  - databases
  - interview
---
A **vector database** stores embeddings and serves **approximate nearest-neighbor (ANN)** search — the retrieval engine under [[Retrieval-Augmented Generation]]. The core tradeoffs are index type (recall vs latency vs memory) and whether to use a dedicated store or a general DB like pgvector.

## Embeddings and similarity

An **embedding** maps text to a dense vector where **semantic similarity ≈ geometric proximity**. Retrieval scores similarity by **cosine** (angle; magnitude-invariant, the common default), dot product, or L2 distance. Query and documents **must use the same embedding model** — changing the model requires re-embedding the whole corpus.

## Why ANN, not exact search

Exact kNN is O(N·d) per query — fine for thousands, too slow for millions/billions. **ANN indexes** trade a little recall for large speedups.

| Index | How it works | Tradeoff |
| --- | --- | --- |
| **Flat** | brute force, exact | accurate, slow; baseline for small data |
| **IVF** | k-means clusters vectors into cells; search only the nearest `nprobe` cells | fast, lower memory; recall depends on `nprobe`; needs training |
| **HNSW** | multi-layer navigable graph; greedy descent from sparse top layers to dense bottom | **best recall/latency**; high memory; slower inserts |
| **+ PQ** | product quantization compresses vectors (e.g. `IVF-PQ`) | big memory savings, some recall loss |
| **DiskANN** | graph index on SSD | billion-scale beyond RAM |

**HNSW** is the popular default. Key knobs: `M` (connections/node), `efConstruction` (build quality), `ef`/`efSearch` (search breadth ↔ recall/latency).

## Filtered ANN

RAG often needs "top-k similar **where** category=X, date>Y". **Post-filtering** (retrieve k then filter) can return too few if the filter is selective; **pre-filtering** can be slow or break the ANN graph. Good vector DBs do **filtered ANN** natively — a real engineering tension to mention.

## pgvector vs Chroma vs Milvus

| | **pgvector** (Postgres) | **Chroma** | **Milvus** |
| --- | --- | --- | --- |
| What | Postgres extension: `vector` type + ANN | lightweight, embedded/local-first | distributed, purpose-built for scale |
| Scale | thousands → ~tens of millions | prototyping → small/medium | **100M → billions** |
| Ops | low *if you already run Postgres* | **lowest** (in-process) | **highest** (etcd, object store, message queue) |
| Indexes | `ivfflat`, `hnsw` | HNSW | HNSW, IVF, **DiskANN, PQ, GPU** |
| Filtering | **full SQL** (joins, WHERE, ACID) | basic | rich |
| Killer feature | vectors **+** relational data in one DB, transactions | dead-simple dev experience | massive scale, high QPS |

**pgvector's own indexes:** `ivfflat` (cluster+probe; tune `lists`/`probes`; cheaper build, less memory) vs `hnsw` (better recall/latency, more memory — generally preferred now).

## Choosing: one DB vs best-of-breed

> **pgvector is the pragmatic default** — if you already run Postgres you get vectors *plus* relational data, transactions, joins, and SQL filtering in **one system**, avoiding the need to **sync** a separate vector store with your source of truth (a real consistency headache). **Graduate to a dedicated vector DB (Milvus/Qdrant/Weaviate)** when scale (100M+), QPS, or advanced indexing (DiskANN/GPU/quantization) exceed a single Postgres. **Chroma** is for prototyping/local dev, not a system of record.

The key decision axis: **one DB with transactional consistency vs. a dedicated store you must keep in sync.** The main risk of a separate vector DB is **data sync** — vectors drift from the source data on updates/deletes/re-embeds.

## Interview summary

> A vector DB stores embeddings and serves ANN search. Exact kNN is too slow at scale, so ANN indexes trade recall for speed: HNSW (graph, best recall/latency, high memory) is the default; IVF (cluster+probe, cheaper, needs tuning); PQ compresses; DiskANN goes disk-scale. Filtering + ANN is a tension (pre- vs post-filter). For the DB choice: pgvector is the pragmatic default (vectors + relational + transactions in Postgres, no separate store to sync), Chroma is simplest for prototyping, and Milvus is the distributed billion-scale option — you move off pgvector when scale, QPS, or advanced indexing demand it, accepting the data-sync cost.

## Related notes

- [[Retrieval-Augmented Generation]]
- [[Hybrid Retrieval]]
- [[Reranking]]
- [[Database Indexing]]
- [[Hash Map]]
