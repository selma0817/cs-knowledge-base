---
date: 2026-09-15
aliases:
  - RAG
  - retrieval-augmented generation
  - RAG pipeline
  - chunking
  - RAG evaluation
  - faithfulness
tags:
  - ai/llm/retrieval
  - ai/llm/rag
  - ai/systems
  - interview
---
**Retrieval-Augmented Generation (RAG)** retrieves relevant documents from an external knowledge base and injects them into the LLM's prompt before generation, grounding answers in up-to-date, private, or domain-specific data without retraining.

## Why RAG

- **Adds knowledge** the model wasn't trained on (fresh, private, domain-specific).
- **Reduces hallucination** by giving the model facts to ground on and cite.
- **Cheaper than fine-tuning** to add knowledge, and updatable without retraining.

RAG vs the alternatives:

| Approach | Use for |
| --- | --- |
| **RAG** | knowledge that changes, is large/private, or needs citations |
| **Fine-tuning** | teach *format/style/behavior* or a narrow skill — not fast-changing facts |
| **Long context** (stuff everything in the prompt) | small static corpora; costly per token, "lost in the middle" recall issues, doesn't scale |

Often combined: RAG selects what goes into a long context window.

## The pipeline

**Indexing (offline):** load docs → **chunk** → **embed** each chunk → store vectors + metadata in a [[Vector Databases and ANN Search|vector DB]].

**Query (online):** embed the query → **retrieve** top-k similar chunks (ANN) → optionally [[Reranking|rerank]] → stuff chunks + question into the prompt → LLM generates a grounded, cited answer.

```
docs → chunk → embed → vector DB          (index, offline)
query → embed → retrieve top-k → rerank → prompt(context+question) → LLM → answer   (online)
```

## Chunking

Chunking sets retrieval granularity, and it matters:

- **Too large** → chunk contains irrelevant text, diluting the embedding and wasting context.
- **Too small** → loses surrounding context; retrieves fragments.

Strategies: **fixed-size with ~10–20% overlap** (baseline; overlap preserves cross-boundary context), **recursive/structural** (split on paragraphs/sections/markdown headers), **semantic** (split where topic shifts). A strong pattern is **small-to-big / parent-document retrieval**: index *small* chunks for precise matching but return the larger *parent* section to the LLM.

## Retrieval quality stack

- **Dense** (embeddings) → semantic similarity; misses exact keywords.
- **Sparse** (BM25) → exact terms; no semantics.
- **[[Hybrid Retrieval]]** → fuse both (RRF) — usually best.
- **[[Reranking]]** → cross-encoder re-scores the top-k for precision before the LLM.
- **Query transformation** → rewriting/expansion, **HyDE** (embed a hypothetical answer), multi-query, sub-question decomposition for multi-hop.

## Evaluation

Separate **retrieval** from **generation**:

- **Retrieval:** recall@k, precision@k, MRR, NDCG (did we fetch the right chunks?).
- **Generation:** **faithfulness/groundedness** (is the answer supported by the retrieved context — the key RAG metric), answer relevance, context relevance. Often scored with an **LLM-as-judge** (RAGAS-style).

**Debugging a wrong answer — isolate the stage:** Is the right chunk retrieved at all? If **no** → retrieval problem (chunking, embedding model, k, add hybrid/rerank, query transform). If **yes but still wrong** → generation problem (prompt, model ignoring context, or context too long → "lost in the middle").

## Failure modes

- **Lost in the middle** — LLMs attend best to the start/end of long context; retrieve fewer, higher-quality chunks and place the best at the edges.
- **Hallucination** — mitigate with good retrieval, "answer only from context / say I don't know", required citations, faithfulness eval, low temperature. Retrieval quality is the biggest lever.
- **Stale index** — re-embed/upsert changed docs; changing the embedding model requires **re-embedding the whole corpus** (query and docs must share the model).

## Interview summary

> RAG retrieves relevant chunks from a knowledge base and injects them into the prompt so the LLM answers from grounded facts — adding knowledge without retraining and reducing hallucination. The pipeline is index (chunk → embed → store) then query (embed → retrieve top-k → rerank → generate). Chunking trades precision vs context (small-to-big retrieval is a good compromise); retrieval quality improves with hybrid search, reranking, and query transformation. Evaluate retrieval (recall@k, MRR) and generation (faithfulness/groundedness) separately, and debug by first checking whether the right chunk was retrieved at all. Key pitfalls: lost-in-the-middle, hallucination from weak retrieval, and stale indexes.

## Related notes

- [[Vector Databases and ANN Search]]
- [[Hybrid Retrieval]]
- [[Reranking]]
- [[LLM Context Management]]
- [[Prompt Caching and Statelessness]]
