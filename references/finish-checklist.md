# 交付前收尾清单（Finish Checklist）

目标：在最终输出/交付前做一次“对齐 + 证据 + 文档缓存”收口，减少遗漏与跑偏。

适用：开发实施阶段最终总结前；或任何需要交付结果的阶段。

---

## Checklist（按优先级）

- **对齐不漂移**：`why.md#对齐摘要` 与实现/任务/验证一致（Review-规格一致性）
- **证据可复现**：fmt/lint/typecheck/test/security 的执行情况与结果可复现记录（命令来自 `HAGWroks/project.md#项目能力画像`）
- **任务真实**：`task.md` 所有任务状态已更新；`[X]/[-]/[?]` 具备注释说明
- **快照可续作**：`task.md##上下文快照` 覆盖关键决策/约束/失败/下一步，事实/推断隔离且来源标签齐全
- **未违反执行域**：本次实际改动未违反执行域声明（Allow/Deny/NewFiles/Refactor）；必要时在 `task.md##上下文快照` 记录纠偏检查点（见 `references/execution-guard.md`）
- **Active Context 可续作**：涉及 Public API/契约变更时，`HAGWroks/active_context.md` 已更新且每条具备 `[SRC:CODE]`；若指针漂移必须当轮修复（见 `references/active-context.md`）；必要时运行 `HAGWroks/scripts/validate-active-context.ps1`
- **文档同步（按项目启用）**：`project.md` 命令矩阵、wiki、CHANGELOG、history/index 等与代码一致
- **版本控制（按需且需授权）**：未在未授权情况下执行 `git add/commit/push/merge/rebase/reset/tag`；如用户要求提交/推送，确认目标分支/远端/提交规范，并检查是否包含敏感信息
- **输出格式**：最终输出严格按 `templates/output-format.md`（文件清单纵向列出 + 验证结果）

---

## 失败/阻断处理（必要时）

- 阻断性门禁失败：按 `references/quality-gates.md` 停止并走失败协议
- 连续失败≥3：按 `references/failure-protocol.md` 升级，必要时执行 `references/break-loop-checklist.md`
