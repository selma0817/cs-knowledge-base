---
tags: [system-design, infrastructure, distributed-systems, vllm]
date: 2026-06-24
aliases: [Control Plane, Gateway, Radix Trees, VRAM Eviction]
---
In a massive cloud deployment, LLM infrastructure is split into distinct logical layers.

## The Three Nodes
1. **API Gateway Node (The Front Door):** Receives the payload, tokenizes it, and groups it into chunks. It calculates a sequential hash for each chunk. It does *not* run the LLM.
2. **Control Plane Node (The Directory):** An ultra-fast, distributed in-memory datastore (like Redis or etcd) that maintains a map of block hashes to specific GPU servers.
3. **GPU Worker Node (The Data Plane / The Muscle):** The massive servers storing the KV tensors in VRAM and actually executing the model.

## Cache-Aware Routing
To maximize cache hits across a distributed network, gateways do not route by user IP. 
1. The Gateway chunks and hashes the prompt.
2. The Gateway queries the Control Plane for the longest matching sequence of hashes.
3. The request is routed to the specific GPU already holding those cached KV tensors.
* **The "Flying Blind" Scenario:** If the Control Plane crashes, the Gateway must route randomly. 99.9% of requests become Cache Misses, skyrocketing compute costs even if GPU VRAM is perfectly healthy.

## VRAM Eviction & vLLM
GPUs use an **LRU Algorithm (Least Recently Used)** to manage memory. Because shared system prompts form the "trunk" of the **Radix Tree** (via systems like vLLM), they stay at the top of the pile. Unique user inputs (the "leaves") naturally sink to the bottom and get deleted when VRAM is full.

**Related:**
* Why prefix matching is essential for this routing: [[Prompt Caching and Statelessness]]