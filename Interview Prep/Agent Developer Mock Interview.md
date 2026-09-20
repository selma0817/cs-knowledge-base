---
tags: [interview, mock, agent-developer]
date: 2026-07-22
aliases: [Mock Interview Questions, Agent Developer Q&A]
---

# Agent Developer — Mock Interview Questions

根据 knowledge_base 已有知识体系定制，覆盖 Agent 八股 + 后端八股 + 系统设计。

---

## 🧠 Agent Architecture

### 1. Agent Loop
Agent 是在一个 `while True` 里循环调 LLM 还是用事件驱动？什么时候决定 stop？

**思路方向：**
- ReAct loop vs 纯 Function Calling
- Max iterations 和 early stopping 策略
- 异常情况：LLM 陷入循环 / 重复调同一个 tool

### 2. Tool Calling Error Handling
如果 tool 返回了 500 或者超时，你怎么让 agent 优雅恢复而不是直接崩掉？

**思路方向：**
- Retry with backoff
- 给 LLM 返回错误信息让它重新规划
- 降级策略：跳过该 tool / 换替代方案
- 什么情况下应该给用户报错而不是继续重试

### 3. ReAct vs Function Calling
什么场景下 ReAct 的 reasoning 是必要的，什么时候是浪费 token？

**思路方向：**
- ReAct: 多步推理、需要中间思考的任务
- Function Calling: 简单查询、参数明确的 tasks
- 混合模式：先 ReAct 规划，再 Function Calling 执行

### 4. MCP (Model Context Protocol)
MCP 解决了什么问题？如果不用 MCP，你怎么自己管理 tool 的 discovery 和调用？

**思路方向：**
- Tool 注册与发现机制
- Schema 标准化
- 动态 tool 加载
- 安全边界（sandboxing）

### 5. Agent Memory 分层
Short-term (in-context) vs long-term (RAG/DB) 怎么切换？什么时候该做 compaction 或 summarization？

**思路方向：**
- Context window 管理策略
- Compaction race condition 处理
- 长期记忆的存储与检索

---

## ⚙️ LLM Serving & Infrastructure

### 6. Continuous Batching vs PagedAttention
如果别人问你 "vLLM 为什么比普通 HuggingFace 推理快"，你怎么回答？

**思路方向：**
- Continuous Batching = 调度问题（动态增删请求）
- PagedAttention = 内存管理问题（KV Cache 分页）
- 类比：OS 的进程调度 + 虚拟内存

### 7. Prompt Caching 优化
你设计 agent system prompt 时会怎么优化 cache hit rate？

**思路方向：**
- 静态部分放前面，动态变量放最后
- 系统 prompt 版本管理
- 跨请求复用 prefix

### 8. Context Window 满了怎么办？
你的 compaction 策略是 sliding window 还是 active summarization？如果 compaction 正在跑的时候用户又发了一条消息，怎么处理 race condition？

**思路方向：**
- Sliding window: 简单但丢失上下文
- Active summarization: 保留摘要但增加延迟
- Race condition 处理：先发旧摘要 + 原始消息 + 新输入

---

## 🔧 Tool Use & Integration

### 9. Structured Output 保证
你让 LLM 调用 tool 的时候，是让 LLM 自由输出 JSON 还是用 constrained decoding / grammar？各自的 trade-off 是什么？

**思路方向：**
- 自由 JSON: 灵活但可能格式错误
- Constrained decoding: 保证格式但可能限制能力
- JSON Mode / Grammar 各厂家支持情况

### 10. Idempotency in Agent Tools
如果 payment tool 被调了两次，你怎么保证不会重复扣钱？

**思路方向：**
- 请求级别的 idempotency key
- 幂等性检查在 tool 实现层
- Agent 重试策略和幂等性配合

---

## 🏗️ 后端八股

### 11. gRPC vs REST
你选哪个做 agent 的 internal service 通信？为什么 gRPC 在 streaming 场景下更合适？

**思路方向：**
- gRPC: 强类型、二进制、streaming、双向流
- REST: 浏览器友好、调试方便
- 典型架构：外部 REST → Gateway → 内部 gRPC

### 12. JWT 局限性
如果有一个 token 被泄露了，服务端能做什么？怎么处理 token revocation？

**思路方向：**
- JWT 无状态，无法主动 revoke
- 黑名单 / 短过期时间 / refresh token 轮换
- 对比 session-based auth

### 13. OAuth 2.0 Authorization Code Flow
Refresh token 和 access token 的生命周期怎么管理？

**思路方向：**
- Authorization code + PKCE
- Refresh token rotation
- Token 存储安全

---

## 🌐 分布式系统

### 14. Rate Limiting
Token bucket vs Leaky bucket，在分布式环境下怎么保证限流准确？

**思路方向：**
- Token bucket: 允许 burst
- Leaky bucket: 平滑流量
- 分布式: Redis + Lua script / 本地 + 集中式配合

### 15. Retry 策略
什么时候用 exponential backoff？加不加 jitter？为什么？

**思路方向：**
- 网络抖动: 加 jitter 避免 thundering herd
- 服务过载: backoff 给恢复时间
- 幂等性是 retry 的前提

### 16. Message Queue 在 Agent 系统中的应用
怎么保证消息不丢不重？

**思路方向：**
- 生产者: 确认机制 + 重试
- 消费者: 至少一次语义 + 幂等消费
- 死信队列处理

---

## 💾 数据与存储

### 17. RAG Retrieval 流程
Embedding + 关键词 hybrid search 怎么切换？re-ranking 怎么做？

**思路方向：**
- Dense retrieval (embedding) vs sparse retrieval (BM25)
- Hybrid search 权重融合
- Cross-encoder re-ranking 对 top-k 精排

### 18. Agent Conversation History 存储
用什么存？PostgreSQL？Redis？有什么取舍？

**思路方向：**
- PostgreSQL: 持久化、复杂查询、但延迟高
- Redis: 快、适合热数据、但容量有限
- 分层: 热数据 Redis + 冷数据 PG

---

## 💻 Coding

### 19. Go Worker Pool
Goroutine 和 Channel 怎么实现 worker pool？能手写一个简单的吗？

**思路方向：**
- 带缓冲 channel 作为任务队列
- WaitGroup 管理 worker 生命周期
- Context 取消 / graceful shutdown

### 20. Go Scheduler (GMP)
M、P、G 分别是什么？什么情况下会发生 goroutine 的 starvation？

**思路方向：**
- M: 操作系统线程
- P: 处理器（调度上下文）
- G: Goroutine
- Starvation: 大量密集计算 goroutine 阻塞 P

### 21. Python Asyncio
Event loop 怎么工作的？`await` 到底在等什么？如果有一个 blocking call 堵住了 event loop，怎么 debug？

**思路方向：**
- Event loop 调度 coroutine
- await = 挂起当前 coroutine，让出控制权
- Blocking call 排查: asyncio debug mode, blocking detector

---

## 🏛️ 综合系统设计

### 22. 设计 Multi-Agent 协作系统
一个 orchestrator agent 管理多个 specialist agent，每个 agent 都有自己的 tool set —— 你怎么设计通信协议、任务调度、错误隔离？

**思路方向：**
- 通信: gRPC streaming / MQ
- 调度: 任务队列 + 优先级
- 隔离: 每个 agent 独立 sandbox / 进程 / 容器
- 错误处理: 单个 agent 失败不影响整体
- 上下文传递: 共享 context 的分片与合并

### 23. Agent Observability
用户说 "agent 回答错了"，你怎么定位问题？

**思路方向：**
- Trace: 完整请求链路（LLM call → tool call → 结果）
- Log: 每个 step 的 reasoning 和 action
- 排查: LLM reasoning 错了 / tool 返回错误 / context 被截断
- 评估: 逐 step 回放 replay

---

*根据 knowledge_base 已有知识体系生成，2026-07-22*