---
tags: [ai-engineering, api, openai, anthropic]
date: 2026-06-24
aliases: [API Endpoints, OpenAI vs Anthropic]
---
The industry is currently split between two primary payload structures for communicating with foundational models.

* **OpenAI Standard (`/v1/chat/completions`):** The de facto industry standard. The payload is a `messages` array. The `system` prompt is simply passed as the first object in that array.
* **Anthropic Standard (`/v1/messages`):** Designed specifically for the Claude family. The `messages` array strictly contains `user` and `assistant` back-and-forth. The system prompt is extracted as a completely separate, top-level parameter to give it stronger foundational weight.

**Related:** * How these payloads interact with statelessness: [[Prompt Caching and Statelessness]]