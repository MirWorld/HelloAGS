# Trigger + Checklist 示例（跨层改动）

## 用户输入示例
> 新增一个“创建订单”接口，并在前端下单页接入；需要向后兼容旧客户端（旧字段仍可用），同时统一错误码返回。

## 期望触发
- **开工前检查**：第一次改代码前执行（对齐/验证/边界/复用）
- **跨层一致性**：涉及 UI + API + 服务/领域层 +（可能）DB；且改契约/兼容策略
- **复用与去重**：会新增/修改 DTO、错误码、可能新增 util，需要先检索复用
- **交付前收尾**：最终输出前确保门禁证据/快照/active_context/格式齐全

## 关键落盘（最小）
- `how.md`：
  - 写清“契约变化 + 兼容策略 + 验证方式”（参考 `references/cross-layer-checklist.md`）
  - 写清“复用与去重策略/边界/重构预算”（参考 `references/code-reuse-checklist.md`）
- `task.md`：
  - 明确跨层触发与对应任务（模板已包含 `0.5 跨层一致性（触发式）`）
  - 在 `## 上下文快照` 记录关键决策与兼容约束（事实/推断隔离 + 来源标签）
- `HAGSWorks/active_context.md`：
  - 新增/修改 Public API（HTTP 路由/handler/命令等）必须登记并带 `[SRC:CODE] path symbol`（行号可选）

## 输出要点（收尾）
- 按 `references/finish-checklist.md` 自检
- 最终总结严格使用 `templates/output-format.md`（纵向文件清单 + 验证结果）

