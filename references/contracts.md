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

---

## 4) 当前方案包指针：`HAGSWorks/plan/_current.md`

指针文件属于公共 API（被恢复协议引用）：
- 文件：`HAGSWorks/plan/_current.md`
- 键：`current_package: <path>`

合法性规则（协议层约束）：
- 允许为空：`current_package:`（视为无指针）
- 非空时必须指向 `HAGSWorks/plan/` 下的目录
- 禁止指向 `HAGSWorks/history/` 或任意包外路径

来源：`references/plan-lifecycle.md`（生命周期）与 `references/resume-protocol.md`（选包协议）。

---

## 5) Active Context：`HAGSWorks/active_context.md`

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

