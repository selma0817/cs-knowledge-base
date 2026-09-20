---
date: 2026-09-15
aliases:
  - hybrid retrieval
  - hybrid search
  - dense retrieval
  - sparse retrieval
  - BM25
  - reciprocal rank fusion
  - RRF
tags:
  - ai/llm/retrieval
  - ai/systems
  - interview
---
**Hybrid retrieval** combines **dense** (embedding) and **sparse** (keyword) search and fuses their results, capturing semantic similarity *and* exact-term precision — usually beating either alone. It is a standard quality lever in [[Retrieval-Augmented Generation]].

## Dense vs sparse

| | **Dense** (embeddings) | **Sparse** (BM25 / TF-IDF) |
| --- | --- | --- |
| Matches on | **semantic** meaning | **exact terms** |
| Strengths | synonyms, paraphrase, intent | rare terms, IDs, codes, names, exact keywords |
| Weakness | misses exact/rare tokens | no semantics; vocabulary mismatch |
| Needs training | yes (embedding model) | no |

Dense retrieval fails on things like product codes or exact names it never learned; sparse retrieval fails when the query and document use different words for the same idea. Each covers the other's blind spot.

## Fusion: Reciprocal Rank Fusion (RRF)

Run both retrievers, then combine their ranked lists. Scores from the two systems aren't comparable, so the common method is **Reciprocal Rank Fusion**, which combines by **rank position**, not raw score:

```
RRF_score(doc) = Σ over retrievers  1 / (k + rank_in_that_retriever)
   (k is a small constant, e.g. 60; lower rank = higher contribution)
```

Documents ranked highly by *either* retriever bubble up; documents ranked well by *both* rank highest. No score normalization needed.

## Where it fits

Hybrid retrieval is the **first stage**; its fused top-k is typically passed to a [[Reranking|reranker]] for final precision before the LLM. So the full stack is often: **hybrid retrieve (recall) → rerank (precision) → generate.**

## Interview summary

> Hybrid retrieval fuses dense (embedding, semantic) and sparse (BM25, exact-keyword) search, so it catches both paraphrased meaning and exact rare terms — covering each method's blind spot. Because the two produce non-comparable scores, results are fused by Reciprocal Rank Fusion (RRF), which combines by rank position. It's the first-stage retriever, usually followed by reranking then generation.

## Related notes

- [[Retrieval-Augmented Generation]]
- [[Reranking]]
- [[Vector Databases and ANN Search]]
