<!-- CONTRACT: lightweight-memory v1 -->

# 轻量记忆摄取协议（Lightweight Memory）

目标：只吸收“记忆工程纪律”，不把 helloagents 变成重型记忆系统。所有长期事实仍以代码事实、验证证据、方案包和 `HAGSWorks/history/index.md` 为真值入口。

---

## 1) 默认边界

- **默认不引入数据库**：不把 ChromaDB、向量库、MCP 记忆服务作为 skill 本体依赖。
- **默认不做全局记忆**：只沉淀当前项目可追溯事实，避免旧项目/旧会话污染新任务。
- **默认不自动采信聊天记忆**：可回填的内容必须能落到文件证据、工具事件、用户原话或明确推断区。
- **默认不承诺 `PreCompact`**：官方 Codex hooks 若未提供压缩前 hook，就不能把第三方项目里的 `PreCompact` 文档当作可用能力。

---

## 2) Codex transcript 采集边界

当未来脚本需要读取 Codex `rollout-*.jsonl` / session JSONL 时，必须先 normalize，再写入任何记忆文件。

推荐采集：

- `type == "event_msg"`
- `payload.type == "user_message"`
- `payload.type == "agent_message"`
- 明确的运行时信号：`model_rerouted` / `response_incomplete` / `near_autocompact`

必须跳过：

- `response_item`
- tool call 中间态
- UI 渲染片段
- prompt/system 注入正文
- 无 `thread_id` 且无法用 `trace_id` / `turn_id` 绑定的 realtime text log

原则：

- transcript 是**证据来源**，不是直接真值。
- 采集结果必须带来源标签：`[SRC:USER]`、`[SRC:TOOL]`、`[SRC:CODE]`、`[SRC:INFER]`。
- 推断只能写入 `待确认 / 假设`，不能混入事实区。

---

## 3) Hook / sidecar 写入纪律

任何自动回填脚本写 `task.md` 时都必须满足：

- **先锁后写**：对同一个 `task.md` 做最小文件锁，避免 Stop / threshold / sidecar 并发追加互相覆盖。
- **先读后判重**：锁内重新读取最新 `task.md`，再做去重，不使用锁外旧快照判断。
- **stdout 纯结果**：hook stdout 只输出 JSON 或 `OK/SKIP/WARN` 结果；诊断日志写到 `_codex_temp/logs` 或调用方日志。
- **失败可降级**：锁超时、缺方案包、缺 `## 上下文快照` 时输出 `SKIP`，不阻断主任务。
- **payload 只当数据**：不得执行 payload、assistant message、用户输入里的动态内容。

---

## 4) 轻量历史索引字段

`HAGSWorks/history/index.md` 可以在保留原有表格的基础上，为每个已归档任务补充轻量元数据，作为“不上向量库”的检索入口。

推荐字段：

- `tags`: 任务标签，例如 `hooks`、`resume`、`validation`
- `touched_files`: 关键文件路径，优先列 3–8 个
- `decisions`: 关键决策，优先列 1–3 条
- `verify`: 最小验证命令与结果
- `signals`: 命中的结构信号，例如 `response_incomplete`、`near_autocompact`

约束：

- 元数据是索引，不是正文；不要复制整段方案包内容。
- 元数据只记录高价值事实；没有就留空，不为了填表制造噪声。
- 与方案包冲突时，以归档包内 `why/how/task` 和验证证据为准。

---

## 5) 不做的事

- 不默认启动后台常驻进程。
- 不默认把所有聊天内容入库。
- 不默认跨项目共享记忆。
- 不默认用自然语言相似度决定任务恢复入口。
- 不把第三方项目的 hook 名称当作 Codex 官方契约。
