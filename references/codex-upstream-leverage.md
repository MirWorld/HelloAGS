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

### 0.3 0.130.0 稳定版可直接借力的能力
- **persisted `/goal` workflows**：更适合表达持久化目标与阶段推进；在 HelloAGENTS 里只能作为辅助目标容器，不能替代 `why/how/task`
- **permission profiles / sandbox CLI profiles**：可把执行边界从模糊授权收紧到显式 profile；同时弱化旧式 `--full-auto` 思路
- **plugin-bundled hooks / hook enablement state**：可把 hooks 作为可分发、可启用的外部增强；压缩生命周期由 `PreCompact/PostCompact` 单独接线
- **`PreCompact` / `PostCompact` hooks**：可在压缩边界前后触发脚本；HelloAGENTS 用它写 `compact_event: pre_compact|post_compact` 快照，保留压缩前任务进度
- **external agent session import / background imports**：可作为外部会话接入或迁移入口，但恢复真值仍以磁盘事实为准
- **MultiAgentV2 显式配置**：thread caps、wait-time controls、root/subagent hints 已显式化，可作为多代理调参参考
- **background computer use / in-app browser / image generation**：Codex 能处理更多非纯代码交付，但 HelloAGENTS 只在任务明确命中 UI/浏览器/图片场景时触发，不写成默认流程
- **plugins / skills / MCP integrations**：可把外部能力作为可选工具来源；HelloAGENTS 仍保持“路由与交付协议”定位，不把所有插件知识塞进主上下文
- **automations / reusable thread context**：可承接周期性任务与重复工作；HelloAGENTS 仍以方案包为任务 SSOT，automations 只负责触发，不负责裁决进度
- **memory preview / proactive suggestions**：可辅助记住偏好与主动建议后续动作；长期事实仍以 `HAGSWorks/project.md`、`history/index.md`、验证证据为准
- **remote devboxes / multiple terminals / summary pane**：可降低远程开发与多任务界面摩擦；协议层只吸收“固定 CWD、摘要不作真值、任务边界落盘”
- **resume / interruption 修复**：更适合把 resume 当成稳定恢复入口，而不是“记忆继续”
- **`codex update`**：可作为维护与升级辅助动作，但不应写成协议真值
- **边界**：`PreCompact` 是压缩发生前一刻的 hook，不等于上下文比例/剩余 token 阈值预警；阈值预警仍靠外部消费者调用 `helloagents-context-threshold.ps1`

### 0.4 本机 0.130 功能位快照（来自 `codex features list`）
- **可直接使用（stable / true）**：`hooks`、`plugins`、`apps`、`computer_use`、`browser_use`、`browser_use_external`、`in_app_browser`、`image_generation`、`multi_agent`、`personality`、`shell_snapshot`、`tool_search`、`tool_suggest`、`workspace_dependencies`
- **谨慎观察（experimental / under development）**：`goals`、`memories`、`remote_control`、`remote_compaction_v2`、`runtime_metrics`、`request_permissions_tool`、`plugin_hooks`、`skill_env_var_dependency_prompt`
- **吸收原则**：stable 能力可进入“按需触发”；experimental / under development 只写成候选方案，不进入硬协议、不作为验收前提

---

## 1) 上游能力 → 可借力点（只列“能修你痛点”的）

> 说明：这里不展开所有 release 内容，只关注“减少跑偏/重做/噪声”的能力。

### 1.1 `turn_id`（用于按轮次绑定回填）
- **上游能力**：`Stop` / `UserPromptSubmit` hooks payload 带 `turn_id`
- **能解决的痛点**：当前回填主要按 thread/package 绑定，压缩/续作后仍可能把别轮事件归到当前轮
- **建议落点**：
  - hooks 把 `turn_id` 传给 `capture-runtime-events.ps1`
  - 快照里可选记录 `turn_id`
  - 事件去重优先使用 `kind + turn_id`（或更强的 `kind + ts + turn_id`）

### 1.2 `trace_id`（用于回填防串线/去重）
- **上游能力**：每个 turn 产生 `trace_id`
- **能解决的痛点**：回填脚本在缺 thread_id 时容易误归因；或同一事件重复落盘
- **建议落点**：
  - 在快照里记录 `trace_id`（若可得），作为“同一轮/同一输出”的去重键
  - 回填脚本优先用 `thread_id + turn_id`，其次用 `thread_id + trace_id`，再其次用 `trace_id`；两者都缺则 **SKIP**

### 1.3 `request_permissions` + 授权持久化（减少审批噪声）
- **上游能力**：运行中可请求额外权限；授权可以跨 turns 持久；并与 `apply_patch` 等写操作一致
- **能解决的痛点**：为了跑一个脚本/写一个文件，反复卡在审批对话，破坏“无感”
- **建议落点**：
  - 在 `references/command-policy.md` 补一条：若工具链支持 `request_permissions`，优先使用；否则走“用户确认→继续/停止”的协议

### 1.4（实验性）Hooks Engine：`SessionStart` / `Stop`（自动回填的最薄入口）
- **上游能力**：会话生命周期 hooks（实验性）
- **能解决的痛点**：你现在的事件回填不是 CLI 原生 hook，只能 best-effort；hooks 可把“回填触发”变成更稳定的系统事件
- **建议落点**：
  - 用 `Stop` hook 触发“无感回填”（只写结构：`model_event`/`repo_state`/`下一步唯一动作`）
  - 用 `SessionStart` hook 注入/确认当前 `CURRENT_PACKAGE`（或至少检查 `_current.md` 指针是否有效）
- **硬风险线**：
  - hook 输入可能包含 `last_assistant_message`；**禁止把它当脚本执行**（只当数据解析）

### 1.5 `PreCompact` / `PostCompact`（压缩生命周期检查点）
- **上游能力**：压缩前后 hooks，payload 提供 `session_id / turn_id / cwd / transcript_path / model / trigger`
- **能解决的痛点**：自动压缩后模型靠摘要续作，容易丢失“已完成 / Pending / 下一步唯一动作”
- **已落点**：
  - `scripts/hooks/helloagents-compact.ps1`
  - `templates/hooks/hooks.json`
  - `templates/hooks/precompact-hook-fixture.json`
  - `templates/hooks/postcompact-hook-fixture.json`
- **恢复规则**：
  - `compact_event: pre_compact` 优先视为“官方压缩前最后检查点”
  - `compact_event: post_compact` 触发 Reboot Check，不允许凭聊天摘要直接继续

### 1.6 0.130 体验层能力（只吸收原则，不增默认流程）
- **上游能力**：background computer use、in-app browser、image generation、plugins/skills/MCP、automations、memory preview、proactive suggestions、remote devboxes、multiple terminals、summary pane
- **能解决的痛点**：复杂任务可覆盖浏览器/远程环境/重复执行/多工具上下文，但这些能力容易把 skill 变重
- **建议落点**：
  - 浏览器/UI/图片：只在任务明确命中时走专项 skill 或专项方案包
  - automations：只作为“触发器”，触发后仍创建/恢复方案包
  - memory/proactive suggestions：只作为偏好提示，禁止替代 `HAGSWorks/project.md` 与 `task.md`
  - plugins/MCP：只按需启用，外部事实必须带来源并写入快照/报告
  - summary pane：只作为导航辅助，不作为已完成状态真值

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

- [x] P0.4 将 `turn_id` 纳入 hooks → 回填 → 快照链路（优先级高于 `trace_id`）
  - 改哪里：
    - `scripts/hooks/helloagents-stop.ps1`：从 hook payload 读取并转发 `turn_id`
    - `scripts/hooks/helloagents-userpromptsubmit.ps1`：在注入的最小上下文里附带 `current_turn_id`
    - `HAGSWorks/scripts/capture-runtime-events.ps1`：增加 `-TurnId` 参数与去重/过滤逻辑
    - `references/contracts.md`、`references/context-snapshot.md`：补 `turn_id` 为可选结构字段
  - 验收：
    - 带 `turn_id` 的 fixture / smoke 通过

- [x] P0.3 把 `request_permissions` 写入“命令策略”作为可选能力（不改变默认流程）
  - 改哪里：
    - `references/command-policy.md`
  - 验收：
    - `scripts/validate-skill-pack.ps1` 通过

- [x] P0.5 将 `thread/resume` 复用已持久化 `model/reasoning effort` 写入恢复协议假设
  - 改哪里：
    - `references/resume-protocol.md`
    - `references/codex-upstream-leverage.md`
  - 验收：
    - 恢复协议明确“resume 后仍以磁盘事实为准，不把模型临时漂移当成可依赖信号”

- [x] P0.6 接入官方 `PreCompact/PostCompact` 压缩生命周期 hooks
  - 改哪里：
    - `scripts/hooks/helloagents-compact.ps1`
    - `templates/hooks/hooks.json`
    - `references/context-snapshot.md`
    - `references/resume-protocol.md`
  - 验收：
    - `scripts/validate-skill-pack-smoke.ps1` 能证明 `pre_compact/post_compact` 写入当前方案包 `task.md##上下文快照`

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

### P4（0.130 可选吸收：保持轻量，不进默认路径）

- [ ] P4.1 Automations 触发方案包恢复，而不是直接执行
  - 改哪里：
    - `references/resume-protocol.md`：补一句“automation 入口等同 SessionStart + Resume”
    - `templates/plan-task-template.md`：必要时加 `automation_source:` 可选字段
  - 验收：
    - automation 触发后仍能按 `_current.md + task.md##上下文快照` 恢复，不凭线程摘要直接继续

- [ ] P4.2 Memory preview 只做偏好提示，不做事实裁决
  - 改哪里：
    - `references/lightweight-memory.md`
    - `references/cognitive-core.md`
  - 验收：
    - 文档明确 memory 可以提示用户偏好，但项目事实仍以代码/验证/方案包为准

- [ ] P4.3 Browser / computer use / image generation 按命中触发专项流程
  - 改哪里：
    - `references/checklist-triggers.md`
    - `references/project-profile.md`
  - 验收：
    - 普通代码任务不新增上下文税；UI/浏览器/图片任务能显式声明使用外部能力与验收证据

- [ ] P4.4 Plugins / MCP 接入走供应链与来源标注
  - 改哪里：
    - `references/safety.md`
    - `references/external-knowledge.md`
  - 验收：
    - 新增插件/MCP 前必须说明权限、来源、失效条件；输出事实写 `[SRC:TOOL]`

---

## 3) 最小闭环（verify_min）建议

当你开始执行本清单里的改动时，推荐最小闭环顺序：
1. `pwsh -NoProfile -File scripts/validate-skill-pack.ps1`
2. `pwsh -NoProfile -File HAGSWorks/scripts/validate-plan-package.ps1 -Mode plan`
