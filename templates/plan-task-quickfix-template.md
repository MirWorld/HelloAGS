# Quick Fix - 任务清单（task.md）

目录：`HAGSWorks/plan/YYYYMMDDHHMM_quickfix_<slug>/task.md`

---

## 0. 对齐与取证（必做）

- [ ] 0.1 阅读 `why.md##对齐摘要`，确认目标/成功标准/非目标/约束无误
- [ ] 0.2 按 `references/quickfix-protocol.md` 执行“参数变更微清单”（如适用），并把结论写入 `## 上下文快照`；同时确定至少 1 条 `verify_min`（最小验证动作）
- [ ] 0.3 执行域声明：按 `references/execution-guard.md` 明确 Allow/Deny/NewFiles/Refactor，并写入 `## 上下文快照` 的决策区
- [ ] 0.4 写检查点：在 `## 上下文快照` 更新 Workset + 下一步唯一动作（防断层）

## 1. 实施

- [ ] 1.1 在 `[path/to/file]` 将参数从 `A` 改为 `B`

## 2. 验证（verify_min，最小-最快-最高信号）

- [ ] 2.1 运行：`[command]`，预期：[…]

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

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=... head=... dirty=... diffstat=...
<!-- 推荐采集: git rev-parse --abbrev-ref HEAD / git rev-parse --short HEAD / git status --porcelain / git diff --stat -->

### 用户原话（验收/约束/偏好）
- [SRC:USER] “...”

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|USER|TOOL] 决策: …
  - 理由: …
  - 影响: …

### 待确认 / 假设（推断必须在此）
- [SRC:INFER][置信度: 中] 假设: …
- [SRC:TODO] 缺失信息: …

### 待用户输入（Pending）
<!-- 无则留空 -->

### 错误与尝试（防重复，按需）

提示：若遇到“输出不完整/压缩或续作异常”（例如 `response.incomplete`、工具输出被截断），先按失败协议记录证据并执行断层恢复（避免重复修改与越界）。

| 错误/症状 | 尝试 | 结果/证据 | 结论（避免重复） |
|---|---:|---|---|
| | 1 | | |

### 下一步唯一动作（可执行）
- 下一步唯一动作: `...` 预期: ...

---

## Active Context 更新记录
（如本次影响公共接口/契约/数据流，在此记录更新摘要；每条 Public API 必须带 `[SRC:CODE] path symbol`（行号可选））

---

## Review 记录
（实现完成后填写：发现的问题/采取的修复/复测结果）

