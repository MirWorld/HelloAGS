---
name: develop
description: 开发实施阶段详细规则；进入开发实施时读取；包含执行流程、代码规范、一致性审计、方案包迁移
---

# 开发实施 - 详细规则

**目标:** 按方案包中任务清单执行代码改动，同步更新知识库，迁移到 history/

**前提:** `plan/` 目录中存在待执行的方案包

**路径约定（避免歧义）:** 本文件中 `plan/`、`history/`、`wiki/` 均指项目根目录下的 `helloagents/` 子路径（例如 `plan/` → `helloagents/plan/`），与 G11 保持一致。

**备份保护:** 执行前建议创建 Git 备份分支或手动备份代码目录

**版本控制护栏:** 除非用户明确要求，否则禁止执行 `git add/commit/push/merge/rebase/reset/tag` 等写操作（口径见 `references/command-policy.md`）

---

## 强制前置检查

<p3_entry_gate>
**说明：** 即使路由判定进入开发实施，此检查仍会验证合法性（双重保险）

**开发实施的唯一合法条件（满足任一即可）：**

```yaml
条件A - 方案设计完成后确认:
  验证方法: 会话历史中上一条AI输出为方案设计完成 且 当前用户输入为明确确认

条件B - 全授权命令:
  验证方法: MODE_FULL_AUTH状态=true

条件C - 执行命令:
  验证方法: MODE_EXECUTION状态=true
```

**验证失败处理：**
```
IF 不满足任何条件:
  输出: "❌ 路由错误: 进入开发实施需满足前置条件。当前条件不满足，已重新路由。"
  执行: 将当前用户消息按路由优先级重新判定
  终止: 开发实施流程
```
</p3_entry_gate>

---

## 执行步骤

**重要:** 所有文件操作遵循G5静默执行规范

### 步骤1: 确定待执行方案包

```yaml
全授权命令(MODE_FULL_AUTH=true):
  - 读取CREATED_PACKAGE变量（方案设计阶段设置的方案包路径）
  - 检查该方案包是否存在且完整
    - 存在且完整 → 使用该方案包，设置CURRENT_PACKAGE = CREATED_PACKAGE
    - 不存在或不完整 → 按G6.2输出错误格式并停止
  - 忽略plan/中的其他遗留方案包

交互确认模式/执行命令(MODE_EXECUTION=true):
  - 扫描plan/目录下所有方案包
  - 不存在方案包 → 按G6.2输出错误格式并停止
  - 方案包不完整 → 按G6.2输出错误格式并停止
  - 单个完整方案包 → 设置CURRENT_PACKAGE，继续执行
  - 多个方案包 → 列出清单，等待用户选择
    - 用户输入有效序号(1-N) → 设置CURRENT_PACKAGE，继续执行
    - 用户输入取消/拒绝 → 按G6.2输出取消格式，流程终止
    - 无效输入 → 再次询问

异常输出示例:
  方案包不存在:
    ```
    ❌【HelloAGENTS】- 执行错误

    错误: 未找到可执行的方案包
    - 原因: plan/目录为空或不存在

    ────
    🔄 下一步: 请先使用 ~plan 命令创建方案，或进入方案设计阶段
    ```

  方案包不完整:
    ```
    ❌【HelloAGENTS】- 执行错误

    错误: 方案包不完整
    - 方案包: [方案包名称]
    - 缺失文件: [why.md/how.md/task.md]

    ────
    🔄 下一步: 请补充缺失文件或重新创建方案包
    ```
```

补充（可选但高收益，确定性校验）：
- 如存在 `helloagents/scripts/validate-plan-package.ps1`：优先运行对 `CURRENT_PACKAGE` 做完整性校验；失败则停止并按G6.2输出“方案包不完整/校验失败”错误。

### 步骤2: 检查知识库状态并处理

执行方式:
- 按 G10 快速决策树判定
- 如需创建/重建知识库 → 读取 `../kb/SKILL.md` 执行完整流程

### 步骤3: 读取知识库并获取项目上下文

执行方式:
- 按 G10 快速流程执行（先检查知识库 → 不足则扫描代码库）
- 如需详细规则 → 读取 `../kb/SKILL.md`
- 优先读取 `helloagents/active_context.md`（如存在）作为公共接口入口清单：
  - 只信带 `[SRC:CODE]` 的 Public APIs 条目（无来源不得当作事实引用）
  - 与代码冲突时以代码为准，并在开发实施阶段修正文档缓存（见 `../references/active-context.md`）

### 步骤4: 读取当前方案包

读取 `plan/YYYYMMDDHHMM_<feature>/task.md`、`why.md` 和 `how.md`

### 步骤4.0: 触发器与检查清单（写代码前必做）

目标：把“开工前检查/跨层一致性/复用去重/收尾”做成可重复动作，减少遗漏、返工与耦合回潮。

执行规则（渐进式加载）：
- 必做：执行 `../references/pre-implementation-checklist.md`
- 其余按触发执行（触发信号与落盘位置见 `../references/checklist-triggers.md`）：
  - 跨层一致性：`../references/cross-layer-checklist.md`
  - 复用与去重：`../references/code-reuse-checklist.md`
  - 子代理侦察/独立审查（如支持多代理）：`../references/subagent-orchestration.md`（子代理只读/禁止写入/禁止再分裂；输出带 `[SRC:CODE]` 指针并写回快照）
  - 执行期护栏（越界保护）：`../references/execution-guard.md`（写域声明 Allow/Deny；失败先 Fail→Narrow，再升级）
  - 卡住破局：`../references/break-loop-checklist.md`（通常与失败协议联动）
  - 交付前收尾：`../references/finish-checklist.md`（最终输出前）

落盘要求（最小）：
- 关键决策/约束/下一步唯一动作：写入 `task.md##上下文快照`（事实/推断隔离 + 来源标签）
- 复用/边界/重构预算：写入 `how.md` 对应章节
- Public API/契约变化：更新 `helloagents/active_context.md`（每条必须 `[SRC:CODE] path:line symbol`）

补充（执行期护栏，推荐强制）：
- 开始改代码前：按 `../references/execution-guard.md` 写一次“执行域声明”（Allow/Deny/NewFiles/Refactor），并落盘到 `task.md##上下文快照`（决策区）

### 步骤4.1: 对齐检查（理解用户的最后防线）

在开始改代码前，先对齐用户意图与执行计划，避免“做完才发现做错”：
- 检查 `why.md` 是否包含 `## 对齐摘要`，并提取：目标、成功标准、非目标、约束条件、风险容忍度、偏好
- 检查 `task.md` 是否包含“对齐确认”类任务（建议引用 `why.md#对齐摘要`）
- 检查 `how.md` 是否包含结构质量约束（边界/复用/重构预算/质量门禁），并在执行中遵守
- 如发现对齐摘要与任务/实现路径明显冲突：
  - 交互确认模式/执行命令：将相关任务标记为 `[?]` 并发起确认（按G6.4交互格式）
  - 全授权命令：优先采取更保守路径（补齐对齐摘要与约束，必要时降级为更小影响面的实现）

### 步骤4.2: 结构与重构约束检查（降耦合/防重复）

在实现前读取 `how.md` 的以下章节（如缺失则补齐或在风险提示中标注）：
- `边界与依赖`：明确代码落点与依赖方向，避免跨层 import（参考 `../references/architecture-boundaries.md`）
- `复用与去重策略`：先复用再新增，避免重复造轮子与 utils 膨胀（参考 `../references/code-reuse-checklist.md`、`../references/architecture-boundaries.md`、`../references/refactoring-anti-coupling.md`）
- `重构范围与不变量`：允许顺手理顺结构，但必须不影响对齐摘要目标（参考 `../references/refactoring-anti-coupling.md`）

### 步骤4.3: 中期落盘（上下文快照，触发式必做）

目标：防止“关键决策/约束/下一步唯一动作”只存在于聊天上下文里；同时避免把推断当事实固化。

执行方式（按需读取细则）：`../references/context-snapshot.md`
- 当出现“上下文预算风险”（工具调用密集/排查分叉/可能中断）：先按 `../references/context-budget.md` 写一次检查点快照（Workset + 下一步唯一动作），再继续推进
- 确认 `task.md` 存在 `## 上下文快照` 章节（缺失则创建）
- 在以下触发点追加/更新快照（不要求重写整段）：
  - 关键决策点（技术路径、模块落点、重构范围、降级策略）
  - 约束/验收变化（成功标准/非目标/风险容忍度变化）
  - 阻断性失败（构建/类型检查/核心测试/安全红线/环境阻断）
  - 会话可能中断/跨时段续作（长排查/多人交接/工具调用密集）
  - 最终输出前（Review 前必须最新）
- 每条快照必须带来源标签；推断只能写进“待确认/假设”区（禁止混入事实区）

### 步骤4.4: Active Context（可验证接口注册表，触发式必做）

目标：把“公共接口表面/关键契约入口”稳定落到 `helloagents/active_context.md`，防止续作时接口幻觉。

执行方式（按需读取细则）：`../references/active-context.md`
- 检查 `helloagents/active_context.md` 是否存在：
  - 不存在：在允许写入时使用 `../templates/active-context-template.md` 创建空壳（后续按任务逐步补齐）
  - 存在：作为入口清单使用，但只信 `[SRC:CODE]` 条目
- 预期规则：
  - 本次变更如新增/修改/删除 Public APIs：必须在任务执行后更新 `helloagents/active_context.md`
  - 每条 Public API 必须包含 `[SRC:CODE] path:line symbol` 指针；推断只能写入风险区

### 步骤5: 按任务清单执行代码改动

```yaml
执行规则:
  - 严格按 task.md 逐项执行

任务成功处理:
  - 每个任务执行成功后，立即将状态从 [ ] 更新为 [√]
  - 如本任务影响公共接口/契约/数据流:
      - 更新 `helloagents/active_context.md`（补齐/修正 Public APIs 的 `[SRC:CODE]` 指针）
      - 如存在 `helloagents/scripts/validate-active-context.ps1`，优先运行进行漂移校验

任务跳过处理(状态更新为 [-]):
  - 任务依赖的前置任务失败
  - 任务条件不满足
  - 任务已被其他任务的实现覆盖

任务失败处理(状态更新为 [X]):
  - 记录错误信息（用于迁移前添加备注）
  - 继续执行后续任务
  - 所有任务完成后，如存在失败:
    - 交互确认模式/执行命令: 列出失败清单，询问用户决定
      - 用户选择继续 → 继续后续步骤
      - 用户选择终止 → 输出"已终止开发实施"，流程终止
    - 全授权命令: 在总结中列出失败任务，清除MODE_FULL_AUTH状态

代码编辑技巧:
  - 大文件处理(≥2000行): Grep定位 → Read(offset,limit) → Edit精确修改
  - 每次Edit只修改单个函数/类
```

### 步骤5.1: 失败即收敛（Fail→Narrow，防止越界自证）

当出现以下任一情况，必须先执行 `../references/execution-guard.md` 的 Fail→Narrow（最多 1 轮），再决定继续/升级/终止：
- Patch/写入失败或修改未按预期生效
- 修改后与成功标准不一致或无法验证
- 开始倾向扩大修改范围（函数 → 文件 → 模块）
- 状态漂移（读到的代码与先前分析依据不一致）

禁止：因失败而直接扩大修改边界继续“硬修”。

### 步骤6: 代码安全检查

检查内容:
- 不安全模式（eval、exec、SQL拼接等）
- 敏感信息硬编码
- EHRB风险规避

### 步骤7: 质量检查与测试

```yaml
质量门禁执行（顺序建议）:
  - fmt → lint → typecheck → test → security
  - 命令优先来自 helloagents/project.md#项目能力画像；不足则按需探测并在允许写入时固化（参考 `../references/project-profile.md`）

测试执行: 运行task.md中定义的测试任务，或项目已有测试套件
测试覆盖: 测试用例应覆盖 why.md 中的成功标准与核心场景（否则视为验证不足）

测试失败处理规则（严格执行）:
  ⛔ 阻断性测试（核心功能）:
    - 失败必须立即停止执行
    - 输出关键错误格式
    - 等待用户明确决策（修复/跳过/终止）
    - 禁止自动跳过

  ⚠️ 警告性测试（重要功能）:
    - 失败时在总结中标注
    - 继续执行后续步骤

  ℹ️ 信息性测试（次要功能）:
    - 失败时在总结中记录
    - 继续执行后续步骤

失败协议（仅阻断性失败计数）:
  - 任一阻断性门禁/环境阻断失败: 视为 1 次失败
  - 维护 CONSECUTIVE_FAILURES（连续失败次数），默认阈值=3
  - 任一阻断点修复并通过（或获得用户明确决策导致路径变化）: 重置为 0
  - 达到阈值: 停止继续尝试，先执行 `../references/break-loop-checklist.md` 收敛信息，再按 `../references/failure-protocol.md` 升级为用户决策（避免反复空转）
  - 记录要求（强烈建议使用快照格式）:
      - 每次阻断性失败至少写入 `task.md##上下文快照`（失败点/错误摘要/已尝试/下一步），并标注来源标签（见 `../references/context-snapshot.md`）
      - 备选：在 task.md 对应任务下追加 `> 备注: ...`（或写入 how.md 的“不确定性”）
```

**⛔阻断性测试失败输出格式:**
```
❌【HelloAGENTS】- 阻断性测试失败

⛔ 核心功能测试失败，必须处理后才能继续:
- 失败测试: [测试名称]
- 错误信息: [错误摘要]

[1] 修复后重试 - 尝试修复问题后重新测试
[2] 跳过继续 - 风险自负，忽略此错误继续执行
[3] 终止执行 - 停止开发实施

────
🔄 下一步: 请输入序号选择
回复契约: 只回复 `1` / `2` / `3`

<helloagents_state>
version: 1
mode: exec
phase: develop
status: awaiting_user_input
awaiting_kind: choice
package: helloagents/plan/YYYYMMDDHHMM_<feature>/   # 有方案包则填写
next_unique_action: "等待用户输入序号 1-3"
</helloagents_state>
```

### 步骤7.1: Review（必做）

最终输出前必须执行 Review（两段式 + 轮次上限），细则见：`../references/review-protocol.md`

```yaml
两段式 Review:
  1) 规格一致性:
     - 对齐摘要（目标/成功标准/非目标/约束）是否被偏离
     - 成功标准是否有对应验证证据（命令/测试/复现步骤）
     - `task.md##上下文快照` 是否已覆盖关键决策/约束/下一步唯一动作，且来源标签齐全（见 `../references/context-snapshot.md`）
     - `helloagents/active_context.md` 是否可续作：Public APIs 是否完整且每条具备 `[SRC:CODE]` 指针（见 `../references/active-context.md`）
  2) 结构与质量:
     - 边界/依赖方向是否被破坏（跨层 import、隐藏耦合）
     - 是否新增重复逻辑或 utils 膨胀
     - 命名/抽象是否可读且贴近领域语义
     - 快照中“事实区”不得混入推断（推断必须在待确认区）
     - active_context 不得出现“无来源事实”；漂移必须修正而不是继续堆叠

修复轮次上限（默认3轮）:
  - Review → 修复 → 复测 = 1 轮
  - 超过 3 轮仍不通过: 按 `../references/failure-protocol.md` 升级为用户决策（收敛范围/补充信息/终止）

复测要求:
  - Review 引入代码改动后，至少重跑受影响的门禁（通常为 fmt/lint/typecheck/test）

Review 记录:
  - 写入 task.md 末尾 `## Review 记录`（问题≤5条/修复≤5条/复测摘要）
```

### 步骤8: 同步更新知识库

**重要:** 必须在步骤12迁移方案包前完成方案包内容读取

执行方式: 读取 `../kb/SKILL.md` 执行完整知识库同步规则

### 步骤9: 更新 CHANGELOG.md

按G7版本管理规则确定版本号

### 步骤10: 一致性审计

<consistency_audit>
**审计时机:** P3阶段完成知识库操作后立即执行

**审计内容:**
1. **完整性**: 文档涵盖所有模块，必备文件和图表齐全
2. **一致性**: API/数据模型与代码一致，无遗漏、重复、死链

**真实性优先级（冲突解决机制）:**
```
1. 代码是执行真实性的唯一来源 (Ground Truth)
   → 运行时行为、API签名、数据结构以代码为准

2. 默认修正方向: 修正知识库以符合代码
   → 发现不一致时，必须更新文档以反映代码的客观事实

3. 例外（修正代码）:
   - 知识库是最近P2/P3方案包（刚设计好的方案）
   - 代码有明显错误（Bug）
   - 错误信息指向代码问题

4. 存疑时: 双向验证，优先信任最近的代码变更
```
</consistency_audit>

### 步骤11: 代码质量检查（可选）

```yaml
执行内容: 分析代码文件，识别质量问题

如发现问题:
  交互确认模式:
    - 输出优化建议询问格式
    - 用户确认 → 执行优化、更新文档、重测
    - 用户拒绝 → 跳过优化，继续后续步骤
  全授权命令/执行命令:
    - 在总结中列出建议（不执行）

版本控制: 默认不执行提交/推送/合并；仅当用户明确要求时才执行，并先确认目标分支/远端/提交规范（见 `references/command-policy.md`）
```

**代码质量优化建议询问格式:**
```
❓【HelloAGENTS】- 代码质量

发现以下可优化项:
1. [优化建议1] - [影响范围/文件]
2. [优化建议2] - [影响范围/文件]

[1] 执行优化 - 应用上述优化建议
[2] 跳过 - 保持现状，继续后续步骤

────
🔄 下一步: 请输入序号选择
回复契约: 只回复 `1` 或 `2`

<helloagents_state>
version: 1
mode: exec
phase: develop
status: awaiting_user_input
awaiting_kind: choice
package: helloagents/plan/YYYYMMDDHHMM_<feature>/   # 有方案包则填写
next_unique_action: "等待用户输入序号 1-2"
</helloagents_state>
```

### 步骤12: 迁移已执行方案包至history/

<plan_migration>

⚠️ **CRITICAL - 强制执行规则:**

**不可跳过:** 此步骤为本阶段结束的原子性操作

**执行规则:**

1. 更新task.md任务状态和备注:
   - 所有任务更新为实际执行结果（[√]/[X]/[-]/[?]）
   - 非[√]状态任务下方添加备注（格式: `> 备注: [原因]`）
   - 如有多个失败/跳过任务，可在末尾添加执行总结章节

2. 迁移至历史记录目录:
   - 将方案包目录从 plan/ 移动到 history/YYYY-MM/ 下
   - YYYY-MM 从方案包目录名提取（如 202511201200_xxx → 2025-11）
   - 迁移后完整路径: history/YYYY-MM/YYYYMMDDHHMM_<feature>/
   - 迁移操作会自动删除 plan/ 下的源目录
   - 同名冲突处理: 强制覆盖 history/ 中的旧方案包

3. 更新历史记录索引: `history/index.md`

**警告:** 此操作将导致 plan/ 下的源文件路径失效，请确保步骤8已完成内容读取
**不可跳过:** 此步骤为本阶段结束的原子性操作
</plan_migration>

### 步骤13: 交付前收尾（Finish Checklist，必做）

最终输出前执行 `../references/finish-checklist.md`，确保：
- 对齐摘要与实现/验证一致
- 质量门禁证据可复现
- `task.md` 状态/快照/Review 记录完整
- `helloagents/active_context.md`（如适用）已更新且 `[SRC:CODE]` 指针可达
- 输出格式符合 `templates/output-format.md`

---

## 代码规范要求

<code_standards>
**适用范围:** P3阶段的所有代码改动

**规范要求:**
- **注释与文档风格:** 优先遵循项目既有约定（语言/格式/TSDoc/GoDoc/Rustdoc/...）；若项目无明确约定，默认使用{OUTPUT_LANGUAGE}
- **写注释的原则:** 只写 why/不变量/陷阱/边界；避免“重复代码在做什么”的注释
- **最小噪声:** 不因“补注释”扩大改动面；注释应服务于对齐摘要与维护者理解
- **代码风格:** 遵循项目现有命名约定和格式规范
</code_standards>

---

## 开发实施 输出格式

⚠️ **CRITICAL - 强制要求:**
- ALWAYS使用G6.1统一输出格式
- NEVER使用自由文本替代规范格式
- 输出前MUST验证格式完整性

### 等待用户选择方案包时（步骤1多方案包）

```
❓【HelloAGENTS】- 开发实施

检测到多个方案包，请选择执行目标:

[1] YYYYMMDDHHMM_<feature1> - [概要描述]
[2] YYYYMMDDHHMM_<feature2> - [概要描述]
[3] YYYYMMDDHHMM_<feature3> - [概要描述]

────
🔄 下一步: 请输入方案包序号(1/2/3)
回复契约: 只回复一个方案包序号（例如 `1`）

<helloagents_state>
version: 1
mode: exec
phase: develop
status: awaiting_user_input
awaiting_kind: choice
package:
next_unique_action: "等待用户输入方案包序号"
</helloagents_state>
```

### 阶段完成时

严格调用 G6.1 统一输出格式，填充以下数据：

1. **阶段名称:** `开发实施`
2. **阶段具体内容(≤5条要点):**
   - 📚 知识库状态
   - ✅ 执行结果: 任务数量和状态统计
   - 🔍 质量验证: 一致性审计、测试结果
   - 💡 代码质量优化建议（如有）
   - 📦 迁移信息: 已迁移至 `history/YYYY-MM/YYYYMMDDHHMM_<feature>/`
3. **文件变更清单:**
   ```
   📁 变更:
     - {代码文件}
     - {知识库文件}
     - helloagents/CHANGELOG.md
     - helloagents/history/index.md
     ...
   ```
4. **下一步建议:** "请确认实施结果是否符合预期?"
5. **遗留方案提醒:** 按G11扫描 plan/ 目录，如有遗留方案包则显示

---

## 阶段转换规则

```yaml
完成所有动作后:
  交互确认模式: 输出总结 → 开发实施结束
  全授权命令: 输出整体总结 → 流程结束
  执行命令: 输出整体总结 → 流程结束
  变量清理: CURRENT_PACKAGE将在遗留方案扫描时自动清理(按G11规则)

异常情况（测试失败/用户提出问题）:
  交互确认模式: 在输出中标注，等待用户决定
  全授权命令/执行命令: 在总结中标注测试失败，流程正常结束
  后续用户消息按路由优先级处理
```
