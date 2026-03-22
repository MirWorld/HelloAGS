<!-- CONTRACT: codex-upstream-leverage v1 -->

# Codex 上游能力借力清单（HelloAGENTS）

目标：不改变用户“自然对话”的使用方式，通过借力 Codex CLI 的上游能力，进一步降低：
- 自动压缩/续作后的 **重复执行**（No-Redo 失效）
- 运行时信号的 **漏记/误记**（跨 thread 污染、误归因）
- 权限/审批导致的 **交互噪声**（影响“无感闭环”）

非目标：
- 不做版本推荐；只标注“能力存在/需要的最低版本/是否实验性”
- 不扩展跨平台支持（PowerShell 为中心）
- 不改变你当前的“结构校验为主、文案不绑死”的维护策略

---

## 0) 当前基线（事实快照）

### 0.1 如何确认本机 Codex 版本

```bash
codex --version
```

### 0.2 HelloAGENTS 当前策略（与本清单相关的部分）
- **No-Redo SSOT**：以 `task.md` 状态为准；任务全完成且无 Pending 时，续作默认“已完成→等待新需求”
- **结构化事件**：把 `model_event: model_rerouted|response_incomplete` 等写入 `task.md##上下文快照`
- **高风险硬门禁**：出现 `response_incomplete` 但缺少事件后的恢复检查点（`repo_state` + `下一步唯一动作`）时，禁止进入执行域

---

## 1) 上游能力 → 可借力点（只列“能修你痛点”的）

> 说明：这里不展开所有 release 内容，只关注“减少跑偏/重做/噪声”的能力。

### 1.1 `trace_id`（用于回填防串线/去重）
- **上游能力**：每个 turn 产生 `trace_id`
- **能解决的痛点**：回填脚本在缺 thread_id 时容易误归因；或同一事件重复落盘
- **建议落点**：
  - 在快照里记录 `trace_id`（若可得），作为“同一轮/同一输出”的去重键
  - 回填脚本优先用 `thread_id`，其次用 `trace_id`（可选），两者都缺则 **SKIP**

### 1.2 `request_permissions` + 授权持久化（减少审批噪声）
- **上游能力**：运行中可请求额外权限；授权可以跨 turns 持久；并与 `apply_patch` 等写操作一致
- **能解决的痛点**：为了跑一个脚本/写一个文件，反复卡在审批对话，破坏“无感”
- **建议落点**：
  - 在 `references/command-policy.md` 补一条：若工具链支持 `request_permissions`，优先使用；否则走“用户确认→继续/停止”的协议

### 1.3（实验性）Hooks Engine：`SessionStart` / `Stop`（自动回填的最薄入口）
- **上游能力**：会话生命周期 hooks（实验性）
- **能解决的痛点**：你现在的事件回填不是 CLI 原生 hook，只能 best-effort；hooks 可把“回填触发”变成更稳定的系统事件
- **建议落点**：
  - 用 `Stop` hook 触发“无感回填”（只写结构：`model_event`/`repo_state`/`下一步唯一动作`）
  - 用 `SessionStart` hook 注入/确认当前 `CURRENT_PACKAGE`（或至少检查 `_current.md` 指针是否有效）
- **硬风险线**：
  - hook 输入可能包含 `last_assistant_message`；**禁止把它当脚本执行**（只当数据解析）

---

## 2) P0 / P1 可执行清单（按优先级）

> 约定：每条都写清 “改哪里 / 怎么验收 / 风险边界”。  
> 清单本身是 SSOT；其它文档如需提到这些能力，只做链接引用，避免口径漂移。

### P0（优先：低风险、直接减少重做/误归因）

- [x] P0.1 增补一页“上游能力矩阵”（本文件已覆盖，但需要被引用到 SSOT Map）
  - 改哪里：
    - `references/terminology.md`：补充条目指向 `references/codex-upstream-leverage.md`
    - （如有）SSOT Map 文件：把本文件纳入“口径类概念唯一来源”
  - 验收：
    - `scripts/validate-skill-pack.ps1` 通过（结构校验）

- [x] P0.2 将 `trace_id` 纳入回填/快照的“去重与防串线规则”（不强依赖）
  - 改哪里：
    - `references/context-snapshot.md`：增加“可选字段：trace_id（若可得）”
    - `HAGSWorks/scripts/capture-runtime-events.ps1`：可选增加 `-TraceId` 参数；若缺 `thread_id` 且缺 `trace_id` 则 SKIP（保持你现在的策略）
  - 验收：
    - `pwsh -NoProfile -File HAGSWorks/scripts/capture-runtime-events.ps1 -Mode detect -DryRun` 输出明确的 SKIP/OK（不落盘）

- [x] P0.3 把 `request_permissions` 写入“命令策略”作为可选能力（不改变默认流程）
  - 改哪里：
    - `references/command-policy.md`
  - 验收：
    - `scripts/validate-skill-pack.ps1` 通过

### P1（可选：收益高，但依赖上游实验能力）

- [x] P1.1 Stop Hook：自动触发事件回填（无感）
  - 改哪里：
    - 新增 `scripts/hooks/helloagents-stop.ps1`（只解析 stdin JSON，不执行任何动态代码）
    - 新增 `templates/hooks/stop-hook-fixture.json`
    - `references/hook-simulation.md`：补一段“Codex hooks → HelloAGENTS 回填”的映射（只描述结构，不绑措辞）
  - 验收：
    - 提供一个本地 JSON fixture（`templates/hooks/stop-hook-fixture.json`）可 `pwsh` dry-run
    - hook 失败时必须降级为 SKIP，不阻断正常对话

- [x] P1.2 SessionStart Hook：自动校验/修复 `_current.md` 指针（无感防跑偏）
  - 改哪里：
    - 新增 `scripts/hooks/helloagents-sessionstart.ps1`
    - 新增 `templates/hooks/sessionstart-hook-fixture.json`
    - `HAGSWorks/scripts/validate-plan-package.ps1`：仅做结构提醒（WARN），不做“自动修复”硬耦合
  - 验收：
    - 当 `_current.md` 指向不存在目录时：输出 WARN + 建议下一步，不自动乱写

### P2（接线：让 hooks 真能调用本仓库脚本）

- [x] P2.1 提供 `.codex/hooks.json` 模板（仅接线，不引入额外系统）
  - 改哪里：
    - 新增 `templates/hooks/hooks.json`（复制到目标项目 `.codex/hooks.json`）
  - 验收：
    - hooks 文件中包含 `SessionStart` / `Stop` / `UserPromptSubmit` 三个事件入口（结构校验）

- [x] P2.2 提供 `codex_hooks` 最小开关片段（config 模板）
  - 改哪里：
    - 新增 `templates/hooks/config.toml.snippet`（合并进 `.codex/config.toml` 或 `~/.codex/config.toml`）
  - 验收：
    - 仅包含 `[features] codex_hooks=true`（不绑定其它配置）

### P3（强 Guard：Pending 时禁止跑偏）

- [x] P3.1 UserPromptSubmit hook：在 `Pending` 状态下阻断无效输入（减少跑偏/减少上下文噪声）
  - 改哪里：
    - 新增 `scripts/hooks/helloagents-userpromptsubmit.ps1`
    - （可选）新增 `templates/hooks/userpromptsubmit-hook-fixture.json` 用于 dry-run
  - 验收：
    - 检测到 `task.md##上下文快照### 待用户输入（Pending）` 非空且用户输入不满足最小回复形态时：返回 `decision=block`
    - 不依赖自然语言正则（只做结构与极少量高信号规则）

---

## 3) 最小闭环（verify_min）建议

当你开始执行本清单里的改动时，推荐最小闭环顺序：
1. `pwsh -NoProfile -File scripts/validate-skill-pack.ps1`
2. `pwsh -NoProfile -File HAGSWorks/scripts/validate-plan-package.ps1 -Mode plan`
