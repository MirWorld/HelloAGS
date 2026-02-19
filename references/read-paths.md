# 最短读取路径（Read Paths）与停止条件

目标：在规则与协议较多的情况下，仍能通过“只读 2–3 个入口文件”快速进入正确路径，减少漏读导致的跑偏与重复。

原则：
- **只读当前场景所需的最小集合**；不做“整库灌上下文”
- 每次读取都必须有明确目的：为了得到**下一步唯一动作**
- 满足“停止条件”就立刻停读并推进（避免越读越散）

补充（来自 hooks 思维的对齐）：如果你习惯用 Claude Code 的生命周期 hooks（SessionStart/UserPromptSubmit/PreToolUse/Stop）来理解流程，可读 `references/hook-simulation.md` 获取与 helloagents 协议的对应关系。

---

## 1) 新一轮开始：先路由（永远第一步）

读取：
- `references/routing.md`

停止条件：
- 已确定本轮属于：命令模式 / 续作恢复 / 等待状态回复 / 开发模式 / 咨询问答
- 已明确写入范围 `write_scope`（`no_write` / `helloagents_only` / `code_write`）

---

## 1.1) 确定项目根目录（Repo Root）

适用：除纯问答外的所有场景（需要读/写项目文件、扫描 `HAGSWorks/` 工作区、运行项目命令等）。

只读命令（优先）：
- `git rev-parse --show-toplevel` → 作为 `PROJECT_ROOT`
- 若失败（非 git 仓库/权限/工具不可用）→ 以当前工作目录作为 `PROJECT_ROOT`（并在假设账本标注 `[SRC:INFER][置信度: 中]`）

规则：
- 所有 `HAGSWorks/...` 路径（plan/wiki/history/active_context/project 等）都必须以 `PROJECT_ROOT` 为基准定位与写入
- monorepo/多子项目：若用户明确指定“以某子目录为工作区根目录”，以用户指定为准，并写入 `HAGSWorks/project.md#项目能力画像`

停止条件：
- 已得到唯一的 `PROJECT_ROOT`
- 已明确：本轮所有读写都相对 `PROJECT_ROOT` 执行（避免在子目录生成多份 `HAGSWorks/`）

---

## 1.2) 提示词/规则优化（Prompt/Rules）

适用：用户明确要求“优化提示词/系统提示/规则文件/输出格式控制”。

读取：
- `references/prompt-optimization.md`

停止条件：
- 已收敛 RTCF（Role/Task/Constraints/Format）最小闭包
- 已给出：诊断要点 + 三档交付（Quick/Standard/Deep）+ 至少 2 个测试用例（主用例+边缘用例）

---

## 2) 上一轮处于等待状态（追问/选择/确认）

读取：
- `templates/output-format.md`（`<helloagents_state>` 定义）
- `references/routing.md`（“上下文状态判定”）

停止条件：
- 已从 `<helloagents_state>` 判定 `awaiting_kind`，并知道本轮只需处理用户回复
- 已生成下一步唯一动作（通常是“等待用户输入/选择/确认”或“用户已给出选择→进入下一阶段”）

---

## 3) Quick Fix（微调 / 改一个参数）

读取：
- `references/quickfix-protocol.md`
- （按需）`templates/plan-why-quickfix-template.md`、`templates/plan-how-quickfix-template.md`、`templates/plan-task-quickfix-template.md`

停止条件：
- 已确认是否满足 Quick Fix 判定（≤2文件≤30行、无 EHRB、无架构影响）
- 已把“真值源/单位边界/消费者/最小验证”收敛成可追溯条目（准备写入 `task.md##上下文快照`）

---

## 4) 方案设计（规划域 / ~plan）

读取：
- `design/SKILL.md`
- （边界）`references/command-policy.md`
- （触发器）`references/checklist-triggers.md`

停止条件：
- 若未经过需求分析：已通过“方案设计入场门槛”（缺口则追问并进入等待态）
- 已选定模板与方案包目录
- 已明确：规划域只允许只读命令；验证动作留到执行域（写入“下一步唯一动作”）

---

## 5) 开发实施（执行域 / ~exec）

读取：
- `develop/SKILL.md`
- `references/pre-implementation-checklist.md`
- （失败收敛）`references/execution-guard.md`

停止条件：
- 已定位 `CURRENT_PACKAGE`（优先读 `HAGSWorks/plan/_current.md`；否则按 `develop/SKILL.md` 的“步骤1: 确定待执行方案包”定位）
- 已完成“开工前检查”（对齐/取证/边界/验证绑定）
- 已明确执行域声明（Allow/Deny/NewFiles/Refactor）并准备落盘

---

## 6) 续作/断层恢复（用户说“继续/接着/上次…”）

同样适用：检测到模型切换/明显 reroute（例如收到 `model/rerouted` 通知）、或出现“输出不完整/压缩异常”（例如 `response.incomplete`）导致你无法稳定解释当前进度。

读取：
- `references/resume-protocol.md`

停止条件：
- 能在 3 分钟内恢复到：当前目标 + 当前进度 + 下一步唯一动作

---

## 7) 连续失败/空转（需要破局）

读取：
- `references/failure-protocol.md`
- `references/break-loop-checklist.md`

停止条件：
- 已把失败证据/已尝试/下一步唯一动作写入 `task.md##上下文快照`
- 已升级为用户决策（给 2–3 个选项）或收敛到单一可疑点

---

## 8) 需要并行侦察/独立审查（如支持多代理）

读取：
- `references/subagent-orchestration.md`

停止条件：
- 已明确子代理边界（只读/不写入/不再分裂/不跑副作用命令）
- 已定义合并落盘位置（`task.md##上下文快照`）

---

## 9) 最终输出前（必须对齐输出规范）

读取：
- `templates/output-format.md`
- （结构审查）`references/review-protocol.md`

停止条件：
- 输出中包含：改动了什么 / 改在哪里（纵向文件清单）/ 验证结果

