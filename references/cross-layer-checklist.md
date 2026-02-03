# 跨层一致性检查清单（Cross-layer Thinking）

目标：当改动涉及多层/契约/多消费者时，避免“某层改了、另一层忘了”与契约漂移。

触发：见 `references/checklist-triggers.md`。

---

## Checklist

- **列出受影响层与入口**：UI / HTTP / API / Service / Domain / DB / Infra / CLI / Jobs…（以及路由/handler/command 等入口）
- **契约对齐**：请求/响应/DTO/schema/事件 payload 是否同步更新？字段名、可选性、默认值、枚举、时间格式、错误码语义是否一致？
- **兼容策略**：是否需要向后兼容（旧字段保留/双写/降级）、迁移步骤、特性开关？
- **错误传播**：底层错误如何映射到上层（统一错误结构、日志、用户提示）；避免泄露敏感信息
- **多消费者清点**：谁在用这个契约？（`rg` 搜调用点/clients/SDK/tests/docs）是否全部更新？
- **Active Context**：如 Public API/契约变化，更新 `HAGWroks/active_context.md`，并为每条条目提供 `[SRC:CODE] path:line symbol`；必要时运行漂移校验脚本
- **验证**：至少补/跑一条覆盖“跨层路径”的验证（集成测试/契约测试/脚本/手动步骤，必须可复现）

---

## 落盘建议（最小）

- 契约与兼容策略：`how.md##API设计` / `how.md##数据模型`
- 受影响消费者清单与验证证据：`task.md##上下文快照` 或 `task.md##Review 记录`
