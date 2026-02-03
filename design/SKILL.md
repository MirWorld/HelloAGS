---
name: design
description: 方案设计阶段详细规则；进入方案设计时读取；包含方案构思、任务拆解、风险评估、方案包创建
---

# 方案设计 - 详细规则

**目标:** 构思可行方案并制定详细执行计划，生成 plan/ 目录下的方案包

**前置条件:** 满足任一即可：
- 已完成需求分析（评分≥7分）
- 或需求足够明确，且通过本文件的“方案设计入场门槛”（用于 Quick Fix/轻量迭代/明确改动型需求，避免小事强制走完整需求分析）

**重要:** 只有在通过“方案设计入场门槛”后才创建方案包；一旦进入创建阶段，方案设计必须创建新方案包，适用于所有模式（交互确认/全授权/规划命令）

**路径约定（避免歧义）:** 本文件中 `plan/` 代表项目根目录下的 `HAGWroks/plan/`（同理 `history/` → `HAGWroks/history/`），与 G11 保持一致。

**执行流程:**
```
入场门槛（必要时追问并等待） → 方案构思 → [用户确认/推进模式下连续] → 详细规划（创建新方案包）
```

---

## 0) 规划域护栏（Plan-only）

目标：把 `~plan` 明确为“只规划不执行”，减少审批噪声与上下文膨胀，避免在未对齐前就动手改代码导致返工与跑偏。

在方案设计阶段（规划域）：
- ✅ 允许：只读扫描/读取项目文件，形成方案；写入 `HAGWroks/` 工作区（`plan/`、`project.md`、`active_context.md`、`wiki/` 等）
- ✅ 允许：运行**只读命令**辅助定位与取证（定义见 `references/command-policy.md`）
- 🚫 禁止：修改业务代码/配置（`HAGWroks/` 工作区之外的文件）
- 🚫 禁止：运行**有副作用命令**（定义见 `references/command-policy.md`）；如确需验证，留到开发实施阶段执行

补充（写入范围 `write_scope`，见 `references/routing.md`）：
- 若 `write_scope = no_write`：本阶段不得写入 `HAGWroks/` 工作区；只在对话中给方案/清单（必要时进入等待态）
- 若用户希望“方案落盘以便续作/执行”：将写入范围提升为 `helloagents_only`（只写 `HAGWroks/`，不改业务代码）

当用户在规划域要求“直接改代码/直接执行命令”时：
- 必须先阻断并请求确认是否切换到开发实施（建议使用 `references/routing.md` 的“上下文确认”交互格式）

如需并行侦察/独立审查以减少不确定性：
- 只在命中触发器时启用（见 `references/checklist-triggers.md`）
- 严格按 `references/subagent-orchestration.md`（子代理只读、不写入、不再分裂；产出带 `[SRC:CODE]` 证据指针）

---

## 0.1) 方案设计入场门槛（Design Entry Gate）

目标：避免“改一个参数也被迫走完整需求分析”的摩擦，同时不牺牲对齐与可验证性——**不满足门槛就阻断、追问、等待**，绝不产出可执行方案包。

适用：
- 当前进入方案设计，但上一阶段并未形成可用的 Intent Model（例如用户直接 `~plan`、或明确改动型需求但希望快速出方案）
- Quick Fix / 轻量迭代等“小而明确”的改动型需求

硬规则（不满足任一即停）：
- **不通过门槛，不创建方案包**（避免 `plan/` 出现半成品误导后续 `~exec`）
- **最多追问 3 个高信息增益问题**；追问后必须进入等待态（输出 `回复契约` + `<helloagents_state status: awaiting_user_input>`）
- **遇到完整研发信号就升级**：需求模糊/架构决策/多方案/EHRB 未确认时，不要试图用门槛“硬推进”，应回到需求分析（读取 `../analyze/SKILL.md` 的追问与评分规则）

门槛判定（必须能写出 `why.md##对齐摘要` 的最小集合）：
1. 目标：1 句话能说清“改什么/为谁/解决什么”
2. 成功标准：至少 1 条可验收信号（行为差异/用例/指标/最小验证动作）
3. 非目标：至少 1 条（这次明确不做什么，防止顺手扩大）
4. 约束/风险容忍度：至少 1 条（允许/禁止改哪些层、是否允许重构、是否必须补测试/回滚方式等）

执行方式：
- 若已满足门槛 → 继续“方案构思”，按模板创建方案包并推进
- 若不满足门槛 → 只输出追问并等待用户补充；**不得**创建方案包、不得输出方案摘要

**追问示例（必须进入等待态，不创建方案包）：**
```
❓【HelloAGENTS】- 方案设计入场门槛

当前信息不足，无法生成可执行方案包（`why.md##对齐摘要` 最小集合尚不完整）。

1. 目标是什么？（1 句话：改什么/为谁/解决什么）
2. 成功标准是什么？（至少 1 条可验收信号/用例/最小验证动作）
3. 约束/非目标是什么？（至少 1 条：明确不做什么 + 允许/禁止改哪些层）

请按序号回答，或回复 `取消` 终止。
回复契约: 按序号逐条回答（例如 `1) ... 2) ... 3) ...`），或回复 `取消`

<helloagents_state>
version: 1
mode: plan
phase: design
status: awaiting_user_input
awaiting_kind: questions
package:
next_unique_action: "等待用户补充入场门槛信息/取消"
</helloagents_state>
```

---

## 方案构思

### 动作步骤

**0. 读取并固化“对齐摘要”**
- 基于上一阶段（需求分析）整理的 Intent Model（如有），或基于本阶段“入场门槛”补齐后的信息，形成可验收的对齐摘要（目标/成功标准/非目标/约束/风险容忍度/偏好）
- 对齐摘要将写入方案包 `why.md` 的 `## 对齐摘要`，作为后续任务清单与测试的最高约束
- 如对齐摘要缺失或仍含糊（尤其缺成功标准/边界/约束），按需读取 `../references/cognitive-core.md` 并优先用高信息增益问题补齐

**1. 检查知识库状态并处理**
- 按 G10 快速决策树判定
- 如需创建/重建知识库 → 读取 `../kb/SKILL.md` 执行完整流程

**2. 读取知识库**
- 按 G10 快速流程执行（先检查知识库 → 不足则扫描代码库）
- 如需详细规则 → 读取 `../kb/SKILL.md`

**2.1 建立/更新项目能力画像（Project Profile）**
- 目的：在不预设技术栈的前提下，确认“怎么跑/怎么测/怎么检查”，让后续任务与验证可执行
- 规则：
  - 优先复用 `HAGWroks/project.md#项目能力画像` 中已有命令矩阵
  - 不足则探测并补齐（方案设计允许写入 `HAGWroks/project.md`）
  - 多栈/monorepo 时按子目录分别记录（避免误跑全仓）
- 细则：`../references/project-profile.md`、`../references/stack-detection.md`

**2.2 建立/更新 Active Context（可验证接口注册表）**
- 目的：为续作提供稳定入口，避免接口命名漂移与“瞎编调用”
- 规则：
  - `HAGWroks/active_context.md` 不存在 → 使用 `../templates/active-context-template.md` 创建（允许写入）
  - 存在但明显不合格（>120行/缺结构/大量无来源条目）→ 重建为模板结构（内容后续在开发实施阶段补齐）
  - 与代码冲突的内容：以代码为准；本阶段可先标注风险，开发实施阶段修正
- 细则：`../references/active-context.md`

**3. 判定项目规模**
- 按 G4 规则执行

**4. 判定需求类型并选择模板**
- 按G8判定是否触发产品设计原则
- Quick Fix（≤2文件≤30行、无 EHRB、无架构影响）：
  - 仍需创建完整方案包（`why.md` + `how.md` + `task.md`），但允许极简
  - 优先使用 quickfix 模板（见第 3 步的模板列表）
  - 关键取证与防翻车清单：`../references/quickfix-protocol.md`
- 技术变更（未触发G8）: 使用基础模板
- 产品功能（触发G8）: 使用完整模板（包含产品分析章节）

**5. 产品视角分析（步骤4判定为"产品功能"时执行）**
- 用户画像、场景分析、痛点分析
- 价值主张、成功指标
- 人文关怀考量

**6. 任务复杂度判定**

满足任一条件为复杂任务:
```yaml
- 需求属于"新项目初始化"或"重大功能重构"
- 涉及架构决策
- 涉及技术选型
- 存在多种实现路径
- 涉及多个模块(>1)或影响文件数>3
- 用户明确要求多方案
```

**7. 方案构思**

<solution_design>
**方案评估标准:**
- 优点
- 缺点
- 性能影响
- 可维护性
- 实现复杂度
- 风险评估（含EHRB）
- 成本估算
- 是否符合最佳实践
 - 结构质量：边界清晰、低耦合、避免重复

**方案构思推理过程（内部完成，不输出给用户）：**

```
1. 列举所有可能的技术路径
2. 逐一评估每个路径的优缺点、风险、成本
3. 筛选出 2-3 个最可行的方案
4. 确定推荐方案及理由
```

**基于推理结果执行：**

**复杂任务（强制方案对比）:**
- 生成 2-3 个可行方案
- 详细评估每个方案
- 确定推荐方案和理由
- 输出格式: 推荐方案标题后加"推荐"标识
  - 例: "方案1（最小变更修复-推荐）" vs "方案2（完整重构）"
- 交互确认模式: 输出方案对比，询问用户选择
- 推进模式: 选择推荐方案（不输出对比）

**简单任务:**
- 直接确定唯一可行方案
- 简要说明方案
</solution_design>

### 方案构思 输出格式（等待用户选择方案时）

行首: `❓【HelloAGENTS】- 方案构思`

**输出内容(≤5条要点):**
```
❓【HelloAGENTS】- 方案构思

- 📚 上下文: [项目规模] | [知识库状态]
- 📋 需求类型: [技术变更/产品功能]
- 🔍 复杂度: [复杂任务] - [判定依据]
- 💡 方案对比:
  - 方案1: [名称-推荐] - [一句话说明]
  - 方案2: [名称] - [一句话说明]
- ⚠️ 风险提示: [如有EHRB或重大风险]

────
🔄 下一步: 请输入方案序号(1/2/3)选择方案
回复契约: 只回复一个方案序号（例如 `1`）

<helloagents_state>
version: 1
mode: plan
phase: design
status: awaiting_user_input
awaiting_kind: choice
package:                        # 方案包尚未创建则留空
next_unique_action: "等待用户输入方案序号"
</helloagents_state>
```

**详细方案说明:** 如用户需要详细对比，可追问后展开

### 方案构思 子阶段转换

```yaml
复杂任务:
  交互确认模式:
    - 用户选择有效序号(1-N) → 进入详细规划
    - 用户拒绝所有方案 → 输出重新构思询问格式
      - 确认重新构思: 返回方案构思，重新构思
      - 拒绝: 提示"已取消方案设计"，流程终止
      - 其他输入: 再次询问
  推进模式:
    - 选择推荐方案 → 立即静默进入详细规划

简单任务: 直接进入详细规划
```

**重新构思方案询问格式:**
```
❓【HelloAGENTS】- 方案确认

所有方案均被拒绝。

[1] 重新构思 - 基于反馈重新设计方案
[2] 取消 - 终止方案设计

────
🔄 下一步: 请输入序号选择
回复契约: 只回复 `1` 或 `2`

<helloagents_state>
version: 1
mode: plan
phase: design
status: awaiting_user_input
awaiting_kind: choice
package:
next_unique_action: "等待用户输入序号 1-2"
</helloagents_state>
```

---

## 详细规划

**前提:** 用户已选择/确认方案（来自方案构思）

**重要:** 必须创建新方案包，使用当前时间戳，不得复用 plan/ 中的遗留方案

### 动作步骤

**所有文件操作遵循G5静默执行规范**

**1. 创建新方案包目录**

```yaml
路径: plan/YYYYMMDDHHMM_<feature>/
冲突处理:
  1. 检查 plan/YYYYMMDDHHMM_<feature>/ 是否存在
  2. 如不存在 → 直接创建
  3. 如存在 → 使用版本后缀: plan/YYYYMMDDHHMM_<feature>_v2/
     (如 _v2 也存在，则递增为 _v3, _v4...)
示例:
  - 首次创建: plan/202511181430_login/
  - 同名冲突: plan/202511181430_login_v2/
```

**2. 新库/框架文档查询（如需要）**
```yaml
触发条件: 方案涉及项目中从未使用过的第三方库/框架，或涉及重大版本升级
执行方式: 按 `../references/external-knowledge.md` 查询最新文档（联网/MCP/Context7 等）
记录位置: how.md 的 `## 外部知识与版本绑定（如使用）`
```

**3. 生成方案文件（按需读取模板，避免整库灌上下文）**

按需读取以下模板文件并生成：
- Quick Fix（优先）：
  - `../templates/plan-why-quickfix-template.md` → `why.md`
  - `../templates/plan-how-quickfix-template.md` → `how.md`
  - `../templates/plan-task-quickfix-template.md` → `task.md`
- `../templates/plan-why-template.md` → `why.md`（变更提案/产品提案，含对齐摘要）
- `../templates/plan-how-template.md` → `how.md`（技术设计 + ADR + 质量门禁）
- `../templates/plan-task-template.md` → `task.md`（任务清单，含 Review 记录）

生成要求（理解用户的关键落点）：
- `why.md` 必须包含 `## 对齐摘要`，并写清：目标、成功标准、非目标、约束条件、风险容忍度、偏好
- `how.md` 必须落地结构质量约束：
  - `边界与依赖`（依赖方向/公共入口，避免横向耦合）→ 参考 `../references/architecture-boundaries.md`
  - `复用与去重策略`（复用检索与去重决策，避免重复与 utils 膨胀）→ 参考 `../references/architecture-boundaries.md`
  - `重构范围与不变量`（允许顺手重构但不影响目标）→ 参考 `../references/refactoring-anti-coupling.md`
  - `执行域声明（Allow/Deny）`（执行前明确修改边界，失败时避免扩大范围自证）→ 参考 `../references/execution-guard.md`
  - `质量门禁`（fmt/lint/typecheck/test/security 分级与顺序）→ 参考 `../references/quality-gates.md`
  - （触发式）`跨层一致性`：当变更涉及 ≥3 层/改契约/多消费者时，按 `../references/cross-layer-checklist.md` 补齐契约/兼容/验证要点（触发条件见 `../references/checklist-triggers.md`）
- `task.md` 必须包含：
  - 对齐确认（引用 `why.md#对齐摘要`）
  - 项目能力画像确认（引用 `HAGWroks/project.md#项目能力画像`）
  - 复用检索与边界确认
  - （如触发）跨层一致性检查：按 `../references/cross-layer-checklist.md` 清点受影响层/契约/消费者，并把结论落到 how.md 或 task.md
  - active_context（可验证接口注册表）规则：
      - 执行前阅读 `HAGWroks/active_context.md`（只信 `[SRC:CODE]` 条目）
      - 如本次变更影响公共接口/契约/数据流：必须更新 `HAGWroks/active_context.md` 并补齐 `[SRC:CODE]` 指针
  - 执行期护栏（越界保护）：
      - 执行前写域声明（Allow/Deny/NewFiles/Refactor），并落盘到 `task.md##上下文快照`（参考 `../references/execution-guard.md`）
      - Patch/修改不符合预期时先 Fail→Narrow（最多 1 轮），禁止直接扩大范围继续“硬修”（参考 `../references/execution-guard.md`）
  - 质量门禁与验证（命令来自项目能力画像）
  - Review（必做，记录到 `## Review 记录`）
  - 交付前收尾（最终输出前自检）：按 `../references/finish-checklist.md` 确保证据/快照/active_context/输出格式齐全
  - 上下文快照（中期落盘，触发式必做）：关键决策/需求变更/阻断失败/会话可能中断/最终输出前写入 `## 上下文快照`（细则：`../references/context-snapshot.md`）

**任务清单编写规则:**
```yaml
单任务代码改动量控制:
  - 常规项目: ≤3文件/任务
  - 大型项目: ≤2文件/任务
验证任务: 定期插入
安全检查: 必须包含安全检查任务
质量门禁: 必须包含 fmt/lint/typecheck/test/security（适用项）并记录结果
```

**4. 风险规避措施制定**
- 基于方案构思风险评估，按G9制定详细规避措施
- 交互确认模式: 询问用户
- MODE_FULL_AUTH=true 或 MODE_PLANNING=true: 规避风险
- 写入 `how.md` 的 安全与性能 章节

**5. 设置方案包跟踪变量**
```yaml
设置: CREATED_PACKAGE = 步骤1创建的方案包路径
用途: 在全授权命令中传递给开发实施，确保执行正确的方案包
```

---

## 方案设计 输出格式

⚠️ **CRITICAL - 强制要求:**
- ALWAYS使用G6.1统一输出格式
- NEVER使用自由文本替代规范格式
- 输出前MUST验证格式完整性

严格调用 G6.1 统一输出格式，填充以下数据：

1. **阶段名称:** `方案设计`
2. **阶段具体内容(≤5条要点):**
   - 📚 知识库状态
   - 📝 方案概要（复杂度、方案说明）
   - 📋 变更清单
   - 📊 任务清单概要
   - ⚠️ 风险评估（如检测到EHRB）
3. **文件变更清单:**
   - `HAGWroks/plan/YYYYMMDDHHMM_<feature>/why.md`
   - `HAGWroks/plan/YYYYMMDDHHMM_<feature>/how.md`
   - `HAGWroks/plan/YYYYMMDDHHMM_<feature>/task.md`
4. **下一步建议:**
   - 交互确认模式: 是否进入开发实施?（是/否）
   - 规划命令: 方案包已生成，如需执行请输入`~exec`
5. **遗留方案提醒:**
   - 按G11扫描plan/目录
   - 如检测到遗留方案包（排除本次创建的方案包），按G11规则显示

---

## 阶段转换规则

```yaml
交互确认模式:
  - 输出总结（包含"🔄 下一步: 是否进入开发实施?(是/否)"）
  - 停止并等待用户明确确认
  - 用户响应处理：
    - 明确确认("是"/"继续"/"确认"等) → 进入开发实施
    - 明确拒绝("否"/"取消"等) → 流程终止
    - Feedback-Delta(提出修改意见) → 按Feedback-Delta规则处理
    - 其他输入 → 视为新的用户需求，按路由机制重新判定

推进模式:
  - 全授权命令: 完成方案设计 → 立即静默进入开发实施
  - 规划命令: 输出整体总结 → 停止 → 清除MODE_PLANNING

关键约束（只有以下3种情况可以进入开发实施）：
  1. 方案设计完成后用户明确确认
  2. 全授权命令(~auto等)触发且已完成方案设计
  3. 执行命令(~exec等)触发且plan/中存在方案包
```
