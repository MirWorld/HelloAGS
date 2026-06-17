<!-- CONTRACT: pre-implementation-checklist v1 -->

# 开工前检查清单（Pre-Implementation Checklist）

目标：在写代码前 60 秒完成“对齐 + 验证 + 边界/复用”三件事，减少做错方向、返工与耦合回潮。

适用：开发实施阶段第一次改代码前；或任何改动型任务准备动手前。

---

## Checklist（命中就做，不需要逐条复述）

### 必做（最小闭环）

- **对齐摘要可复述**：能否用一句话复述目标与成功标准？非目标/约束是否明确且可执行？
- **高信号取证已完成**：按 `references/triage-pass.md` 完成一次取证，并将“事实/缺口/下一步唯一动作”写入 `task.md##上下文快照`（未落盘则禁止进入实现）
- **验证已绑定**：至少明确 1 条 `verify_min`（最小验证动作；SSOT 在 `how.md` 的 `verify_min: ...`），并确保 `task.md` 里有可执行验证项/证据记录位点（见 `references/triage-pass.md`）
- **执行域声明**：按 `references/execution-guard.md` 明确 Allow/Deny/NewFiles/Refactor，并写入 `task.md##上下文快照`（决策区）
- **写前先读三问**（见 `references/agent-coding-discipline.md`）：
  - 已读将改文件、直接调用方 / 导出入口 / 共享工具的相关最小片段了吗？
  - 本次修改是否只覆盖用户目标与成功标准，且没有顺手改相邻代码？
  - 若存在两种实现约定冲突，是否已选择一边并记录依据，而不是折中平均？

### 推荐默认（按触发器/项目现状）

- **命令矩阵已收敛（如适用）**：若已能明确技术栈但项目命令/规范不完整：按 `references/stack-detection.md` 在仓库内定位真实可用入口（脚本/CI/README）；仍无法确认则写 `unknown` 并向用户索取命令；允许写入时固化到 `HAGSWorks/project.md#项目能力画像`（避免下次继续猜）
- **影响面已圈定**：预计改哪些模块/文件？能否收敛到更小范围（避免“顺手扩大”）
- **复用检索已做**：常规仓库用 `rg` 搜索相似实现/类型/错误码/字段名；Delphi/Pascal 任务若语义工具可用，先查 `delphi/getIndexStatus`，`missing` 先 `delphi/indexWorkspace`、`stale` 先 `delphi/refreshIndex`、`failed/unavailable` 记录原因并用 `rg` 兜底，再按 `delphi/getSymbolsOverview`、`delphi/findDefinition`、`delphi/findReferences`、`delphi/impactAnalysis` 圈定符号和影响面；按 `references/delphi-evidence-gate.md` 区分真实工具调用与文本搜索 fallback；优先复用而不是新造
- **边界与依赖明确**：落点与依赖方向是否正确？是否有跨层 import 风险？
- **风险与回滚**：是否触发 EHRB？是否需要兼容/降级/回滚策略？
- **落盘**：关键决策/约束/下一步唯一动作写入 `task.md##上下文快照`（事实/推断隔离 + 来源标签）

---

## 发现缺口时怎么处理（优先级）

1. **缺成功标准/边界/约束**：用 1–3 个高信息增益问题追问；或将相关任务标记为 `[?]` 暂停推进
2. **缺验证方式**：在 `task.md` 补最小可复现验证步骤/脚本（必须可重复）
3. **缺边界/复用结论**：在 `how.md` 补齐“边界与依赖 / 复用与去重策略 / 重构范围与不变量”
4. **缺写前先读证据**：常规任务先 `rg` 定位并读取最小相关片段；Delphi/Pascal 任务优先补索引状态、`missing/stale/failed` 生命周期处理、符号 overview、定义、引用和影响面证据；若没有真实 `delphi.*` tool call 或 `item/tool/call namespace=delphi` 证据，必须标注“文本搜索 fallback”；仍无法解释调用关系时，禁止直接写代码
