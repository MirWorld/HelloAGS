# Quick Fix - 任务清单（task.md）

目录：`HAGSWorks/plan/YYYYMMDDHHMM_quickfix_<slug>/task.md`

最小默认闭环：
- 默认只盯 `0. 对齐与取证` / `1. 实施` / `2. 验证` / `## 上下文快照`
- `### 功能删减审批`、`### 错误与尝试`、`## Active Context 更新记录`、`## Review 记录` 仅在命中时填写；未命中保持占位即可

---

## 0. 对齐与取证（必做）

- [ ] 0.1 阅读 `why.md##对齐摘要`，确认目标/成功标准/非目标/约束无误
- [ ] 0.2 按 `references/quickfix-protocol.md` 执行“参数变更微清单”（如适用），并把结论写入 `## 上下文快照`；同时确定至少 1 条 `verify_min`（最小验证动作）；若本包后续还会再次触碰同一 Workset，再补 1 条 `carry_forward_verify`
- [ ] 0.3 执行域声明：按 `references/execution-guard.md` 明确 Allow/Deny/NewFiles/Refactor，并写入 `## 上下文快照` 的决策区
- [ ] 0.4 写检查点：在 `## 上下文快照` 更新 Workset + 下一步唯一动作（防断层）

## 1. 实施

- [ ] 1.1 在 `[path/to/file]` 将参数从 `A` 改为 `B`

## 2. 验证（verify_min，最小-最快-最高信号）

- [ ] 2.1 运行：`[command]`，预期：[…]
- [ ] 2.2（触发式）若本次改动触及可编译/可发布路径且项目存在 build 命令，执行 build；若项目存在相关 test，则运行最贴近改动面的 test
- [ ] 2.3（同 Workset 再次触碰时）补跑 `carry_forward_verify` 或明确记录“不受影响”

---

## 任务状态符号

- `[ ]` 待执行
- `[√]` 已完成
- `[X]` 执行失败
- `[-]` 已跳过
- `[?]` 待确认

---

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] …
- [SRC:TOOL] …

### 运行时/模型事件（可选）
<!-- 仅在 UI/工具提示出现时记录（结构化）：- [SRC:TOOL] model_event: model_rerouted / response_incomplete -->
- [SRC:TOOL] turn_id: ...
- [SRC:TOOL] trace_id: ...

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=... head=... dirty=... diffstat=...
<!-- 推荐采集: git rev-parse --abbrev-ref HEAD / git rev-parse --short HEAD / git status --porcelain / git diff --stat -->

### 用户原话（验收/约束/偏好）
- [SRC:USER] “...”

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|USER|TOOL] 决策: …
  - 理由: …
  - 影响: …
- [SRC:CODE|TOOL] progress_phase: start | mid | late | final

### 结构债务（可选，明确知道是权宜实现时填写）
- [SRC:CODE|USER|TOOL] design_debt: …
- [SRC:CODE|USER|TOOL] why_now: …
- [SRC:CODE|USER|TOOL] revisit_trigger: …

### 功能删减审批
<!-- 仅在命中功能删减风险时填写；未命中保持默认占位 -->
- `feature_removal_risk: clear`
- `feature_removal_approved: no`
- `approved_scope:`
- `approved_target:`
- `approved_reason:`
- `replacement_behavior:`

### 待确认 / 假设（推断必须在此）
- [SRC:INFER][置信度: 中] 假设: …
- [SRC:TODO] 缺失信息: …

### 待用户输入（Pending）
<!-- 无则留空 -->
<!-- 触发“功能删减确认”时示例：- [SRC:TODO] 等待用户确认是否允许本次功能删减（影响: 未获批准前不得继续相关修改） -->

### 错误与尝试（防重复，按需）
<!-- 仅在实际失败/重试/需要防重复时填写；未命中可留空 -->

提示：若遇到“输出不完整/压缩或续作异常”（例如 `response.incomplete`、工具输出被截断），先按失败协议记录证据并执行断层恢复（避免重复修改与越界）。

| 错误/症状 | 尝试 | 结果/证据 | 结论（避免重复） |
|---|---:|---|---|
| | 1 | | |

### 下一步唯一动作（可执行）
- 下一步唯一动作: `...` 预期: ...

---

## Active Context 更新记录
（仅当本次影响公共接口/契约/数据流时填写；未命中留空。每条 Public API 必须带 `[SRC:CODE] path symbol`（行号可选））

---

## Review 记录
（仅在完成收尾时填写；优先记录遗漏 / 缩水 / 越界 / 返工 / contract 偏移 / 累计回归 / 设计债务及其修正。极小任务可只写 1–2 条）
