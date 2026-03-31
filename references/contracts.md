<!-- CONTRACT: protocol-api v1 -->

# 协议公共 API 清单（Contract Surface）

目标：把“哪些文字/结构不能随便改”明确成一份清单，降低维护时的误改与返工成本。

定义：本仓库中的部分**标题/键名/标记块/契约注释**会被校验脚本当作“公共接口（API）”对待；随意改名会导致 `validate-skill-pack.ps1` 或目标项目校验脚本失败。

原则：
- 只把“结构与契约”列为公共 API（避免自然语言措辞绑定）。
- 需要改名/改结构时：同步更新校验脚本，并（必要时）提升契约版本号（`v1 → v2`）。

---

## 1) 契约注释（CONTRACT markers）

这些注释用于标识“协议单一来源（SSOT）”的稳定边界，并被 `scripts/validate-skill-pack.ps1` 强校验存在性：

| Marker | 位置（SSOT） | 含义 |
|---|---|---|
| `<!-- CONTRACT: terminology v1 -->` | `references/terminology.md` | 术语口径与 SSOT Map |
| `<!-- CONTRACT: signal-severity v1 -->` | `references/signal-severity.md` | 轻量信号分级（Green/Yellow/Red） |
| `<!-- CONTRACT: plan-lifecycle v1 -->` | `references/plan-lifecycle.md` | 方案包生命周期与 `_current.md` 指针键名 |
| `<!-- CONTRACT: resume-package-selection v1 -->` | `references/resume-protocol.md` | 断层恢复选包规则（含排序/扫描约束） |
| `<!-- CONTRACT: resume-current-package-pointer v1 -->` | `references/resume-protocol.md` | `_current.md` 指针合法性约束 |
| `<!-- CONTRACT: resume-no-redo v1 -->` | `references/resume-protocol.md` | 完成态判定（防重复执行） |
| `<!-- CONTRACT: skill-no-redo v1 -->` | `SKILL.md` | Skill 总入口的 No‑Redo 硬约束 |
| `<!-- CONTRACT: develop-no-redo v1 -->` | `develop/SKILL.md` | 执行域对 No‑Redo 的强化约束 |
| `<!-- CONTRACT: quickfix-protocol v1 -->` | `references/quickfix-protocol.md` | Quick Fix 快路径协议 |
| `<!-- CONTRACT: triage-pass v1 -->` | `references/triage-pass.md` | Triage Pass 与 `verify_min` 口径 |
| `<!-- CONTRACT: pre-implementation-checklist v1 -->` | `references/pre-implementation-checklist.md` | 预实现检查与 `verify_min` 约束 |
| `<!-- CONTRACT: quality-gates v1 -->` | `references/quality-gates.md` | 质量门禁与最小验证策略 |
| `<!-- CONTRACT: hook-bridge-protocol v1 -->` | `references/contracts.md` | Codex hooks → HelloAGENTS 桥接输出面 |

---

## 2) 交互等待态标记块：`<helloagents_state>`

当输出需要用户输入/选择/确认（即下一轮必须只处理用户回复）时，必须包含：
- 文件中出现 `回复契约:`（reply contract）一行
- 输出末尾出现 `<helloagents_state>...</helloagents_state>` 标记块

`<helloagents_state>` 的键名属于公共 API（结构契约，不校验文案）：

必需字段：
- `version: 1`
- `mode: plan|exec|auto|init|qa`（单值）
- `phase: routing|analyze|design|develop|kb`（单值）
- `status: awaiting_user_input`
- `awaiting_kind: questions|choice|confirm`（单值）
- `package:`（可空或真实路径；不得使用 `...` 占位）
- `next_unique_action:`（必须非空；不校验具体措辞）

可选稳定扩展字段：
- `awaiting_topic:`（用于标记专门的等待主题；推荐枚举之一：`feature_removal_guard`）

来源：`templates/output-format.md`（交互输出格式）与 `scripts/validate-skill-pack.ps1`（结构校验）。

---

## 3) 方案包（why/how/task）的结构契约

方案包目录结构属于公共 API：
- `HAGSWorks/plan/YYYYMMDDHHMM_<feature>/`
- 必需文件：`why.md`、`how.md`、`task.md`（均非空）

最低章节要求（用于 `HAGSWorks/scripts/validate-plan-package.ps1`）：
- `why.md`：必须包含 `## 对齐摘要`
- `how.md`：必须包含 `## 执行域声明（Allow/Deny）`，并包含 `verify_min: ...`
- `task.md`：必须包含 `## 上下文快照` 与 `### 下一步唯一动作（可执行）`，并包含至少 1 行 `下一步唯一动作: ...`

执行域（`-Mode exec`）的额外硬约束（高风险点）：
- `task.md` 必须至少存在 1 条 Pending 任务（`- [ ] ...`）
- `### 待用户输入（Pending）` 必须为空（否则视为仍在等待态，不得继续执行）
- git 可用时：`### Repo 状态` 下必须有非占位的 `repo_state: ... head=<sha> dirty=<true/false> ...`

### 3.1 上下文快照的运行时/模型事件（结构化，可选）

为降低“续作/压缩/异常后重复执行”的概率，允许在 `task.md##上下文快照` 中记录**结构化事件**：

- 建议使用键：`model_event: <kind>`（该键名属于公共 API；不校验自然语言文案）
- 建议放在可选小节：`### 运行时/模型事件（可选）`
- 建议来源标签：`[SRC:TOOL]`（因为它来自 CLI/UI/工具链信号）

`<kind>` 建议使用下列稳定枚举（推荐默认）：
- `model_rerouted`：对应 Codex 的 `model/rerouted`（模型被重定向/以不同模型继续）
- `response_incomplete`：对应 Codex 的 `response.incomplete`（输出不完整；属于高风险信号）

可选元数据（推荐默认，不做硬校验）：
- `turn_id: <id>`：若 Codex hooks/运行时可稳定提供，优先记录；用途是把事件绑定到**当前 turn**，降低续作/压缩后的跨轮误归因
- `trace_id: <id>`：若可从 Codex 运行时/日志稳定取得，可一并记录；用途仅限去重与防串线，不作为真值字段

执行域门禁（`-Mode exec`）的高风险约束：
- 若快照中出现 `model_event: response_incomplete`，则必须在其**之后**追加一条“恢复检查点”（至少包含 `repo_state:` 与 `下一步唯一动作:`）；否则不得继续执行（防止在不确定状态下重做/二次修改）。

### 3.2 功能删减风控键（结构化，可选）

当方案包需要表达“当前是否命中删功能风险”时，可使用稳定键：
- `feature_removal_risk: clear|suspected|approved`
- `feature_removal_approved: yes|no`

用途：
- 供 hooks / 主流程优先消费结构事实，而不是反复依赖 prompt 启发式猜测
- 其中 `feature_removal_risk: suspected` 且 `feature_removal_approved: no` 时，应优先视为 Red 信号

---

<!-- CONTRACT: hook-bridge-protocol v1 -->

## 4) Hook 桥接输出契约（Codex hooks → HelloAGENTS）

适用对象：
- `scripts/hooks/helloagents-userpromptsubmit.ps1`
- `scripts/hooks/helloagents-stop.ps1`
- `scripts/hooks/helloagents-sessionstart.ps1`

目标：
- 让 hooks 输出成为**结构化结果**，供主流程直接消费
- 避免每个 hook 各自发明字段名或只靠自然语言提示

顶层输出字段（稳定）：
- `systemMessage`：给用户/模型的简短提示；允许省略
- `decision`：当前仅约定 `block`（阻断）；未阻断时允许省略
- `reason`：与 `decision: block` 配套的简短原因；允许省略
- `hookSpecificOutput`：结构化附加信息容器；允许省略

`hookSpecificOutput` 的稳定字段：
- `hookEventName`：推荐固定为当前 hook 名（如 `UserPromptSubmit` / `Stop` / `SessionStart`）
- `additionalContext`：供模型消费的最小结构化上下文
- `hookMessage`：dry-run / 诊断 / 回填预览文本；不给模型做真值，只做辅助说明

`additionalContext` 中推荐使用的稳定键：
- `current_package: ...`
- `current_turn_id: ...`
- `next_unique_action: ...`
- `signal: response_incomplete|feature_removal_guard|package_completed`
- `signal: response_incomplete`
- `signal: feature_removal_guard`
- `signal: package_completed`
- `severity: Red|Yellow`
- `package_status: completed`
- `feature_removal_risk: clear|suspected|approved`
- `feature_removal_approved: yes|no`

约束：
- hooks 只输出结构化结果，不执行 payload 中的动态内容
- `feature_removal_risk` 若由 prompt 启发式首次识别，也应**先归一化为** `suspected` 再输出，避免主流程只能依赖自然语言猜测
- `response_incomplete` 命中时，hooks 应优先输出 `signal: response_incomplete` + `severity: Red`
- `Stop` hook 的事件回填预览应显式提示“恢复检查点”存在（至少含 `repo_state` + `下一步唯一动作`）

来源：
- `references/hook-simulation.md`
- `references/feature-removal-guard.md`
- `references/context-snapshot.md`

---

## 5) 当前方案包指针：`HAGSWorks/plan/_current.md`

指针文件属于公共 API（被恢复协议引用）：
- 文件：`HAGSWorks/plan/_current.md`
- 键：`current_package: <path>`

合法性规则（协议层约束）：
- 允许为空：`current_package:`（视为无指针）
- 非空时必须指向 `HAGSWorks/plan/` 下的目录
- 禁止指向 `HAGSWorks/history/` 或任意包外路径

来源：`references/plan-lifecycle.md`（生命周期）与 `references/resume-protocol.md`（选包协议）。

---

## 6) Active Context：`HAGSWorks/active_context.md`

Active Context 的标题结构属于公共 API（被校验脚本依赖）：
- `## Modules (Public Surface)`
- `## Contracts Index`
- `## Data Flow Guarantees`
- `## Known Gaps / Risks`
- `## Next`

Public API 条目的指针格式属于公共 API：
- `[SRC:CODE] path symbol`
- 可选行号：`path:line symbol` 或 `path#Lline symbol`

来源：`templates/validate-active-context.ps1`（loose/strict 校验）。
