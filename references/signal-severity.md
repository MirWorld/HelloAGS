<!-- CONTRACT: signal-severity v1 -->

# 信号等级（Signal Severity）

目标：把 `Green / Yellow / Red` 收敛为单一来源，避免路由、快照、恢复、hooks 各写一套，后续越改越漂。

原则：
- 本文件只定义**等级语义**与**稳定映射**。
- 其它文件只说明“本处如何消费该等级”，不再重复完整定义。
- 等级用于收敛动作，不用于绑定自然语言措辞。

---

## 1) 等级定义

- **Green**：可继续推进；当前 contract 明确，且没有等待态、未恢复异常或明显漂移。
- **Yellow**：先复核 / 先补快照；未处理前不要直接继续改代码。
- **Red**：禁止继续改代码；必须等待 / 恢复 / 重规划 / 获得用户决策后再继续。

---

## 2) 稳定映射

| 信号 | 等级 | 默认动作 | 主要来源 |
|---|---|---|---|
| `contract_checkpoint: ok` 且无 Pending / 无漂移 | Green | 可继续推进 | `references/context-snapshot.md` |
| `model_event: model_rerouted` | Yellow | 先做 contract 复核 / 补恢复检查点 | `references/context-snapshot.md`、`references/resume-protocol.md` |
| `progress_checkpoint: stalled` | Yellow | 改成高信息增益动作，不继续空转 | `references/context-snapshot.md`、`references/break-loop-checklist.md` |
| 轻度 `repo_state` 漂移 | Yellow | 先补 `repo_state` / Delta，再决定是否继续 | `references/context-snapshot.md`、`references/resume-protocol.md` |
| `Pending` 非空 | Red | 进入等待态；本轮只处理用户回复 | `references/routing.md`、`references/context-snapshot.md` |
| `model_event: response_incomplete` | Red | 先补恢复检查点或走恢复协议；禁止直接继续执行 | `references/context-snapshot.md`、`references/resume-protocol.md` |
| `contract_checkpoint: needs_realign` | Red | 禁止继续改代码；先重新对齐 | `references/context-snapshot.md`、`references/resume-protocol.md` |
| `feature_removal_approved: no` 且命中删功能路径 | Red | 等待用户批准，不得继续沿删减路径实施 | `references/feature-removal-guard.md` |
| `current_package` 无效 / 方案包不完整 | Red | 修复 `_current.md` 指针或重新选包 | `references/resume-protocol.md`、`scripts/hooks/helloagents-sessionstart.ps1` |

---

## 3) 使用方式

- **路由层**：命中 `Yellow` 先复核 / 补快照；命中 `Red` 直接阻断到等待 / 恢复 / 重规划。
- **快照层**：优先把信号写成结构字段（如 `model_event`、`contract_checkpoint`、`progress_checkpoint`），不要写成模糊描述。
- **恢复层**：先看等级再决定是否可以继续执行，避免把“恢复成功”误当成“可以直接改代码”。
- **hooks 层**：优先把 `Red` 信号前移到继续执行之前；主流程只消费结果，不重复判断同一件事。
