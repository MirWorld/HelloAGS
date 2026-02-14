# 执行证据记录（Execution Report）

目标：把“跑了什么命令/脚本、结果是什么、下一步怎么做”以**最小但可追溯**的格式落盘，减少口径不一致与断层返工。

---

## 1) 写到哪里

- 通过门禁/验证：写入 `task.md##Review 记录`
- 阻断性失败/需要续作：写入 `task.md##上下文快照`（优先写入“错误与尝试”表 + “下一步唯一动作”）

细则：`references/context-snapshot.md`、`references/quality-gates.md`

---

## 2) 最小记录格式（推荐原样使用）

- [SRC:TOOL] 运行: `<command>`（cwd: `<path>`）→ 结果: 通过/失败（exit: `<code>`）
  - 关键输出: `<1–3行>`
  - 产物/影响: `<生成了什么/改了什么>`（如有）

---

## 3) 脚本建议（确定性工具）

可选为“机械且容易错”的动作提供脚本，减少口误与漏检：
- `HAGSWorks/scripts/validate-active-context.ps1`：Active Context 校验（loose/strict）
- `HAGSWorks/scripts/validate-plan-package.ps1`：方案包完整性校验（why/how/task + 关键章节）

使用原则：脚本只负责**确定性检查**；策略与决策仍以 `why.md##对齐摘要` 与 `task.md##上下文快照` 为准。

