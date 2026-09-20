---
date: 2026-09-15
aliases:
  - reranking
  - reranker
  - cross-encoder
  - bi-encoder
  - two-stage retrieval
tags:
  - ai/llm/retrieval
  - ai/systems
  - interview
---
**Reranking** re-scores a first-stage retriever's top-k with a more accurate but slower **cross-encoder**, so the few chunks sent to the LLM are the most relevant. It is the precision stage of the retrieval stack in [[Retrieval-Augmented Generation]].

## Why rerank

First-stage ANN retrieval optimizes for **speed over a huge corpus**, so its top-k is fast but **noisy** — relevant and marginally-relevant chunks mixed together. Feeding all of them to the LLM wastes context and triggers "lost in the middle." A reranker cleans up the ordering so only the best few reach the model.

## Bi-encoder vs cross-encoder

| | **Bi-encoder** (retrieval) | **Cross-encoder** (reranking) |
| --- | --- | --- |
| How | embeds query and doc **separately**, compares vectors | feeds **(query, doc) together** into the model, attends jointly |
| Accuracy | lower (no cross-attention) | **higher** (models query-doc interaction) |
| Speed | fast; embeddings **precomputable** and ANN-searchable | slow; must run per (query, doc) pair at query time |
| Role | scan the whole corpus for recall | re-score a small candidate set for precision |

A cross-encoder can't scan millions of docs (too slow, nothing precomputable), and a bi-encoder isn't precise enough alone — so they're used **together**.

## The two-stage pattern

```
retrieve top-100 cheaply (bi-encoder ANN / hybrid)   ← recall
        → rerank to top-5 with a cross-encoder        ← precision
        → feed top-5 to the LLM                        ← grounded generation
```

Retrieve **many** fast, rerank to **few** accurately. This balances the cost: the expensive cross-encoder runs only over a small candidate set, not the whole corpus.

## Interview summary

> Reranking re-scores the first-stage top-k with a cross-encoder, which feeds (query, doc) into the model together and attends jointly — far more accurate than the bi-encoder embedding similarity used for retrieval, but too slow to run over the whole corpus. So the standard two-stage pattern is retrieve many cheaply (bi-encoder/hybrid ANN, for recall) then rerank to a few accurately (cross-encoder, for precision) before generation. It also mitigates lost-in-the-middle by shrinking the context to the most relevant chunks.

## Related notes

- [[Retrieval-Augmented Generation]]
- [[Hybrid Retrieval]]
- [[Vector Databases and ANN Search]]
