---
aliases:
  - Topic List
  - topic tags
---
# Topics

**The fixed list of `topic/` tags for this vault.** A note's `topic/` tags say which concept families it belongs to, the way a LeetCode problem is tagged "binary search" or "dynamic programming". They're broad enough to group many notes, and specific enough that the name tells you what kind of thinking the note trains.

They're used in two places:

- **Obsidian:** the tag pane groups them under `topic`, and search or the graph can filter by them.
- **The interview-review card bank:** a card's topics are copied from the `topic/` tags of the notes it cites, so the review site's topic filters come straight from this list.

## Rules

1. **Every concept note gets 1–3 concept tags, plus at most one language tag**, in the frontmatter `tags:` list. Put the note's main topic first: cards citing the note are filed under it.
   ```yaml
   tags:
     - topic/consensus
     - topic/concurrency
     - topic/go
     - raft          # free-form tags can sit alongside
   ```
2. **Only use tags from this list.** Never write a `topic/` tag that isn't defined below.
3. **Language tags** (`topic/go`, `topic/python`, …) are only for notes about that language's own behavior: its runtime, its standard library, its pitfalls. A note about MVCC that happens to show Go code doesn't get `topic/go`.
4. **Exempt notes:** `README`, this file, MOC notes and `Interview Prep/` may carry tags, but don't need them.
5. **A new topic is a decision, never a side effect.** If a note fits nothing below, don't invent a tag. Propose a new entry (name, one-line description, and why the existing tags don't fit), get approval, add it here first, then tag the note.
6. **No `misc` or `other`.** If nothing fits, that's the signal to decide on a new topic.
7. **Renaming or splitting a topic:** update this list, retag the notes, then run `npm run bank:retopic` in interview-review. It re-copies every card's topics from the notes' current tags. Cards are snapshots, so they don't follow note edits on their own.

### Free-form tags

Free-form tags (no `topic/` prefix) are for finer search inside Obsidian (`mvcc`, `goroutine`, `bm25`):

- lowercase, words joined by `-`, no nesting
- one spelling per idea (`llm`, not `llm` + `ai/llm/…` + `vllm`)
- don't repeat a topic tag as a free tag (no free `concurrency` next to `topic/concurrency`)

## The list

### Algorithms and data structures

| Tag | Covers |
|---|---|
| `topic/data-structures` | arrays, hash maps, trees (BST, red-black, B+), heaps, tries, graph representations |
| `topic/algorithms` | complexity, sorting and searching, graph traversal, dynamic programming, greedy |

### Computer systems

| Tag | Covers |
|---|---|
| `topic/operating-systems` | processes and threads, memory, file systems, page cache, syscalls, IPC |
| `topic/concurrency` | locks, CAS and atomics, memory models, channels, races and deadlocks |
| `topic/networking` | TCP/UDP, IP/DNS/NAT, TLS/HTTPS, HTTP versions, sockets, network debugging |
| `topic/gpu-computing` | GPU architecture, memory hierarchy, CUDA basics, FLOPs and the roofline model |

### Programming languages

| Tag | Covers |
|---|---|
| `topic/language-runtimes` | ideas that cut across languages: compilers vs interpreters, VMs, garbage collection, type systems, memory models |
| `topic/go` | Go itself: goroutines and the scheduler, channels, maps and slices, the standard library |
| `topic/python` | Python itself: the interpreter and GIL, asyncio, typing, packaging |
| `topic/java` | Java itself: the JVM, the Java memory model, java.util.concurrent |
| `topic/typescript` | TypeScript and JavaScript: types vs runtime data, the event loop, React-facing language features |

### Data and storage

| Tag | Covers |
|---|---|
| `topic/storage-indexing` | storage engines, B+ trees vs LSM trees, indexes, query execution |
| `topic/transactions` | ACID, isolation levels, MVCC, locking, distributed transactions |
| `topic/caching` | cache patterns, eviction, invalidation, Redis, CDNs |
| `topic/search` | inverted indexes, BM25, vector and ANN search, hybrid retrieval, reranking |

### Distributed systems

| Tag | Covers |
|---|---|
| `topic/consensus` | Raft, Paxos, leader election, replicated logs |
| `topic/replication-consistency` | replication, consistency models, quorums, CAP, clocks and ordering |
| `topic/partitioning-scaling` | sharding, consistent hashing, load balancing, horizontal scaling |
| `topic/distributed-storage` | distributed file and object stores (GFS, HDFS, S3), chunking, leases |
| `topic/messaging-streaming` | queues, Kafka, delivery guarantees, event sourcing, stream processing |
| `topic/resilience` | timeouts, retries with backoff and jitter, idempotency, rate limiting, circuit breakers |

### Backend and system design

| Tag | Covers |
|---|---|
| `topic/api-design` | REST, gRPC, RPC and serialization, API gateways, versioning, pagination |
| `topic/security` | authentication and authorization (OAuth, JWT), TLS and certificates, OWASP Top 10, secrets |
| `topic/system-design` | the design-interview method: requirements, estimation, trade-offs, end-to-end designs |
| `topic/observability` | logs, metrics, traces, SLOs, debugging in production |

### Engineering practice and infrastructure

| Tag | Covers |
|---|---|
| `topic/testing` | the test pyramid, unit, integration and end-to-end tests, mocking, flaky tests |
| `topic/ci-cd` | pipelines, gates vs reports, build once, deployment and release strategies |
| `topic/containers-cloud` | Docker, Kubernetes, cloud services and networking, infrastructure as code |
| `topic/software-design` | design patterns, SOLID, architecture styles, code quality |
| `topic/frontend` | browser rendering, React rendering and state, frontend performance |

### ML and deep learning

| Tag | Covers |
|---|---|
| `topic/ml-fundamentals` | supervised learning, loss and gradient descent, overfitting and regularization, evaluation metrics, bias–variance |
| `topic/deep-learning` | backpropagation, optimizers, normalization, initialization, training stability |
| `topic/transformers` | attention, the KV cache, tokenization and embeddings, positional encoding, mixture of experts |

### LLMs

| Tag | Covers |
|---|---|
| `topic/llm-training` | pretraining, SFT, distributed training (data, tensor and pipeline parallelism, ZeRO/FSDP), mixed precision, LoRA |
| `topic/rl-fine-tuning` | RLHF and PPO, GRPO, DAPO, DPO, reward design, KL regularization, advantage estimation, reward hacking |
| `topic/llm-inference` | serving systems, continuous batching and PagedAttention, decoding and sampling, quantization, prompt caching, speculative decoding |

### LLM applications and agents

| Tag | Covers |
|---|---|
| `topic/llm-apis-prompting` | prompting, function calling, structured outputs, streaming, context management, cost and latency |
| `topic/rag` | chunking, embeddings, retrieval pipelines, grounding, RAG evaluation |
| `topic/agents` | the agent loop, ReAct, planning, tool use and MCP, agent memory, multi-agent systems, human-in-the-loop |
| `topic/evaluation-safety` | evals and LLM-as-judge, agent evaluation, tracing, prompt injection, sandboxing, guardrails |

## Considered, not added yet

These came up while drafting the list. Add one when the first note needs it (rule 5).

- `topic/cpp`: C/C++ systems programming
- `topic/agent-memory`: split out of `topic/agents` once there are several memory notes
- `topic/data-engineering`: batch and stream pipelines, Spark, ETL
- `topic/mobile` and `topic/compilers`

## Related notes

- [[Interview MOC]]: notes grouped by interview area
- [[README]]: how the vault is organized
