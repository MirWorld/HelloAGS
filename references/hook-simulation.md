# Hook 思想吸收：生命周期映射（Hook Simulation）

目标：把 Claude Code 的 “Hooks + Skills + Commands + Agents” 里最有确定收益的部分，**在不引入 hooks/运维系统**的前提下，落到 helloagents 的“阻断式路由 + 触发器清单 + 触发式落盘 + 收尾 Review”里，让 Skill 在 Codex CLI 环境更稳定、更不跑偏。

结论先说清：
- Claude Code 的 `.claude/hooks/*` 属于 Claude 工具链的生命周期钩子机制；
- **Codex CLI（当前 skill 包）不依赖、也不假设存在等价 hooks API**；
- **hooks 不是 helloagents 自带能力**；它们是 Codex 提供时可选接入的外部能力，本仓库只负责提供桥接脚本与模板；
- **一旦接了 hooks，就应该让它们承担重复性守卫**：Pending 阻断、`_current.md` 预检、功能删减等待态提示、`model_event` 回填，主流程只消费结果，不重复解释；
- hooks 的稳定输出字段（`systemMessage` / `decision` / `reason` / `hookSpecificOutput.*`）以 `references/contracts.md` 中的 `<!-- CONTRACT: hook-bridge-protocol v1 -->` 为唯一口径；
- 我们通过“协议化强制步骤 + 自检/CI 门禁”实现 **Hook 等价效果**：把“该做什么”变成每轮都必须遵守的确定性流程。

---

## 1) 你想要的到底是什么（从 Hook 视角翻译成工程约束）

文章里 Hooks 做的事，本质是三类“制度化”：

1. **强制评估（Forced Eval）**：回答/写代码前先判断要不要用规范（Skills），不能直接开写  
2. **工具门禁（PreToolUse Guard）**：执行命令/写文件前做安全检查，避免危险操作/污染状态  
3. **收尾复盘（Stop Hook）**：任务结束时强制总结变更与下一步，并建议独立审查/验证

在 helloagents 里，对应的“确定性锚点”是：
- 路由先行（阻断式）：`references/routing.md`
- 命令分级门禁：`references/command-policy.md`
- 执行期边界与 Fail→Narrow：`references/execution-guard.md`
- 触发式落盘（快照/Pending/下一步唯一动作）：`references/context-snapshot.md`、`references/context-budget.md`
- 断层恢复（Reboot Check）：`references/resume-protocol.md`
- 交付前收尾与两段式 Review：`references/finish-checklist.md`、`references/review-protocol.md`
- 统一输出格式（含等待状态标记）：`templates/output-format.md`

---

## 2) 四个“生命周期 Hook”到 helloagents 的映射表（可执行版）

> 你可以把下面这张表当成“没有 hooks 的 hooks”：每次推进到这个生命周期点，都必须做相同的动作，且必须落盘到可恢复位置。

| Claude Hook（概念） | helloagents 等价锚点（必须做） | 必读文件（最小集合） | 必须落盘（最小） | 停止条件（避免无限加戏） |
|---|---|---|---|---|
| SessionStart（会话启动） | 若是续作/不确定，或检测到 `model/rerouted` / `response.incomplete`：按恢复协议重建进度；否则只做最小环境确认 | `references/resume-protocol.md`、`references/read-paths.md` | `task.md##上下文快照`：Workset + 下一步唯一动作（必要时） | 3 分钟内恢复到“下一步唯一动作” |
| UserPromptSubmit（用户提交问题） | **先路由**：命令/等待回复/只给方案/执行缺方案包/EHRB → 命中即阻断 | `references/routing.md`、`templates/output-format.md` | 需要等待用户时：写 `Pending` + 输出末尾 `<helloagents_state>` | 路由明确且下一步唯一动作清晰 |
| PreToolUse（执行工具前） | 规划域只读；执行域先写执行域声明；失败走 Fail→Narrow | `references/command-policy.md`、`references/execution-guard.md` | `task.md##上下文快照`：决策（Allow/Deny/NewFiles/Refactor）+ 下一步唯一动作 | 边界清晰、命令分级清晰、可验证动作已绑定 |
| Stop（任务结束） | 收尾清单 + 两段式 Review + 统一输出；必要时迁移 history | `references/finish-checklist.md`、`references/review-protocol.md`、`templates/output-format.md` | `task.md##Review 记录`：门禁证据；`task.md##上下文快照`：最终检查点 | 输出包含：改动了什么/在哪里/验证结果 |

---

## 3) “强制技能激活（Forced Eval）”在本项目里的等价实现

Claude 用 Hook 强制“先评估技能再实现”。helloagents 的等价实现是：

1. **阻断式路由（先判定再做事）**
   - 入口：`references/routing.md`
   - 目的：把“是否能进入执行/是否要追问/是否只给方案”变成互斥决策树，禁止直接开写

2. **触发器矩阵（该读哪个清单）**
   - 入口：`references/checklist-triggers.md`
   - 目的：把“什么时候要做跨层一致性/复用去重/子代理/破局”等从经验变成触发式读取

3. **触发式落盘（防失忆/防跑偏）**
   - 入口：`references/context-snapshot.md`、`references/context-budget.md`
   - 目的：在关键点把事实/决策/约束/下一步唯一动作写入方案包，断层也能恢复

4. **等待状态结构化（下一轮只处理回复）**
   - 入口：`templates/output-format.md`（`回复契约` + `<helloagents_state>`）
   - 目的：把“追问/选择/确认”变成可路由的状态机，避免下一轮误以为是新需求

---

## 4) hooks 我们能不能“用”？怎么“用”才不跑偏

### 4.1 直接用 Claude 的 `.claude/hooks/*` 这种 hooks？

不建议把它当成 Codex CLI 的前提能力：本 skill 包的设计目标是 **在没有 hooks 的情况下也稳定**。

你可以把 helloagents 的这些机制当成“内置 hook”：
- “UserPromptSubmit hook” = `references/routing.md`（阻断式路由）
- “PreToolUse hook” = `references/command-policy.md` + `references/execution-guard.md`
- “Stop hook” = `references/finish-checklist.md` + `references/review-protocol.md` + `templates/output-format.md`

### 4.2 能否做“外壳级 hooks”（可选增强，不是 SSOT）

可以，但要明确它的定位：**加速器，不是正确性来源**。推荐两类：

1) **CI hooks（推荐，确定性）**  
用 GitHub Actions 跑自检脚本（本仓库已包含）：`.github/workflows/validate-skill-pack.yml` → `scripts/validate-skill-pack.ps1`。  
它解决的是“文档/模板漂移”，不会改变运行时行为。

2) **本地 git hooks（可选）**  
用 `core.hooksPath` 把 pre-commit 之类的检查挂上（例如提交前自动跑 `scripts/validate-skill-pack.ps1`）。  
注意：git hooks 默认不随仓库分发自动安装；它只能减少本地误提交，**不能替代** `task.md##上下文快照` 的落盘与恢复协议。

### 4.3 可选实验桥接：Codex hooks → HelloAGENTS

当外部环境确实提供 hook 调用时，本仓库现在提供一层**最薄桥接**，但仍坚持“hooks 只是加速器，不是真值来源”：

- `scripts/hooks/helloagents-stop.ps1`
  - 输入：stdin JSON（或 `-InputFile`）
  - 行为：**只解析数据**，识别 `model_rerouted` / `response_incomplete`，然后转调项目内 `HAGSWorks/scripts/capture-runtime-events.ps1`
  - 增强：若 `last_assistant_message` 含结构化 `<helloagents_state>` 且 `awaiting_topic: feature_removal_guard`，输出“当前仍在等待功能删减批准”的提醒
  - 约束：不执行 `last_assistant_message` 或任何动态内容；只解析结构化块；无法识别输入时直接 `SKIP`

- `scripts/hooks/helloagents-sessionstart.ps1`
  - 输入：stdin JSON（或 `-InputFile`）
  - 行为：校验 `HAGSWorks/plan/_current.md` 的 `current_package` 是否仍指向 `HAGSWorks/plan/` 下的完整方案包；若当前包已完成且无 Pending，或存在未恢复的 `response_incomplete`，输出 WARN 提示下一步
  - 推荐输出：通过 `hookSpecificOutput.additionalContext` 结构化写出 `signal / severity / current_package / next_unique_action / package_status`
  - 约束：只输出 JSON（`systemMessage` 仅在 WARN 时提示）；**不自动修复、不自动改指针**

- `scripts/hooks/helloagents-userpromptsubmit.ps1`
  - 输入：stdin JSON（或 `-InputFile`）
  - 行为：若当前方案包 `task.md##上下文快照### 待用户输入（Pending）` 非空：为模型注入最小“等待态约束”（additionalContext）；并在用户试图提交 `~` 命令/空输入时阻断（decision=block）
  - 增强：当检测到未恢复的 `response_incomplete`、已完成方案包被误续作、或结构化字段 `feature_removal_risk: suspected` 且未批准时，可直接 `decision=block`，把守卫前移到继续执行之前；只有结构信号缺失时才回退到更强约束的 prompt 启发式
  - 约束：只读磁盘事实（`_current.md` / `task.md` / `how.md`），不依赖自然语言措辞；不执行任何动态内容（payload 只当数据）

- 本地 dry-run 夹具：
  - `templates/hooks/stop-hook-fixture.json`
  - `templates/hooks/stop-hook-feature-removal-fixture.json`
  - `templates/hooks/sessionstart-hook-fixture.json`
  - `templates/hooks/userpromptsubmit-hook-fixture.json`

若你使用的 Codex 版本支持 hooks engine（实验性），本仓库提供最小“接线模板”（仅复制即可）：
- `.codex/config.toml`：合并 `templates/hooks/config.toml.snippet`
- `.codex/hooks.json`：复制 `templates/hooks/hooks.json`

重要：
- 不接线 hooks，不影响 helloagents 的核心流程与正确性
- 接了 hooks，就应优先用 hooks 承担这些重复性守卫；主流程只消费 `_current.md` / `task.md##上下文快照` / `capture-runtime-events.ps1` 的结果
- hooks 让提示/回填/守卫更无感；**不是**把正确性真值从协议层转移到 hooks
- hooks / sidecar 的写入纪律见 `references/lightweight-memory.md`：stdout 只输出结构化结果，写 `task.md` 前必须加锁并在锁内去重

消费原则（很重要）：
- 只要 hooks 已把事实写成结构化结果（例如 `_current.md`、`task.md##上下文快照`、`capture-runtime-events.ps1` 的输出），主流程就直接消费这些事实
- 主流程不再对同一件事重复做“人工解释版判断”；只有 hooks 缺失、失效或结构不完整时才回退到人工判定
- **不重复解释预算**：同一轮里 hooks 已输出 `signal / severity / next_unique_action` 时，主流程最多用 1 句话说明处理结果，剩余篇幅用于真正的下一步动作

这层桥接的目标只有两个：
- 让“运行时事件 → 快照落盘”更无感
- 让“续作开场 → `_current.md` 指针检查”更稳定

一旦输入形态不支持、路径不可达、或项目尚未初始化到可回填状态，脚本必须降级为 `SKIP`，不能阻断正常对话。

### 4.4 非 Hook 的外部阈值守卫（推荐给监控/sidecar）

有一类能力不是 Codex hooks engine 直接提供的，但仍然很值：**在接近自动压缩阈值前，先把当前方案包的恢复检查点落盘**。

本仓库提供：
- `scripts/hooks/helloagents-context-threshold.ps1`

它的定位很窄：
- 输入：外部消费者提供的结构化 JSON（`source / used_tokens / auto_compact_threshold / remaining_to_compact / compact_pre_tokens?`）
- 行为：只 append 到当前 `task.md##上下文快照`
- 输出：`OK:` / `SKIP:` 纯文本

它不是 Codex hook，也不是 Skill 主流程的前提；更适合作为：
- CodexMonitor
- 自建 sidecar
- 日志消费器

来调用。

这样做的价值是：
- 在**压缩前**就把 `repo_state + 下一步唯一动作` 固化下来
- 即使后续真的发生自动压缩，也更容易按磁盘检查点续作，而不是重开任务/重复修改

注意：
- 若官方 Codex hooks 未提供压缩前事件，不要把第三方项目里的 `PreCompact` 写法当作 Codex 官方能力。
- 真正可用的压缩前防线仍是外部消费者读取上下文阈值后调用 `helloagents-context-threshold.ps1`。

---

## 5) 与本项目目标的对齐（避免“为了 hooks 而 hooks”）

本项目目标是“让 Codex 更聪明地做任务”，而不是搭建运维系统；因此：
- **制度化的核心 SSOT 在方案包/知识库/代码事实**（见 `references/context-snapshot.md`）
- “hooks/外壳脚本/CI”最多是辅助门禁与提示，不允许成为唯一依赖
- 一切机制最终必须收敛到：下一步唯一动作 + 可复现证据 + 可恢复进度
