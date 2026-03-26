# 任务清单: [功能名称]

目录: `HAGSWorks/plan/YYYYMMDDHHMM_<feature>/`

最小默认闭环（先做这些，其他只在命中时展开）：
- 必做：0.1（对齐）/ 0.2（verify_min 绑定）/ 0.6（快照）/ 0.8（执行域声明）/ 5.0（verify_min）/ 6.x（Review）
- 触发再展开：复用检索 / 跨层一致性 / Active Context / 子代理 / 安全检查 / 文档更新 / 额外门禁

---

## 0. 对齐确认
- [ ] 0.1 阅读 `why.md#对齐摘要`，确认目标/成功标准/边界/约束无误；如有偏差先修正 why.md 再执行后续任务
- [ ] 0.2 确认 `HAGSWorks/project.md#项目能力画像` 已包含可用命令矩阵（build/test/fmt/lint/typecheck 等）；并为核心成功标准绑定至少 1 条 `verify_min`（最小验证动作，命令/测试/脚本/可复现手动步骤皆可）；如缺失则补齐后再继续
- [ ] 0.3（触发式推荐）如存在相似实现、公共入口或边界风险，再按 `references/code-reuse-checklist.md` / `references/architecture-boundaries.md` 补齐复用与依赖结论；未命中可标 `[-]`

## 0.5 跨层一致性（仅触发时展开）
- [ ] 0.5.1 仅当涉及 ≥3 层 / 改契约 / 多消费者 / 语义承诺变化时，按 `references/checklist-triggers.md` 与 `references/cross-layer-checklist.md` 补齐受影响层、契约、兼容策略与消费者；未命中可标 `[-]`

## 0.6 上下文快照（中期落盘，触发式必做）
- [ ] 0.6.1 初始化：确认文末存在 `## 上下文快照` 区块（缺失则创建）
- [ ] 0.6.2 触发式维护：关键决策/需求变更/阻断失败/会话可能中断/最终输出前，按 `references/context-snapshot.md` 追加/更新快照并标注来源标签；每次快照更新必须包含“下一步唯一动作”；推断只能写入“待确认/假设”区

## 0.7 Active Context（仅触发时展开）
- [ ] 0.7.1 仅当本次变更影响公共接口 / 契约 / 数据流时，更新 `HAGSWorks/active_context.md` 并补齐 `[SRC:CODE] path symbol`；未命中可标 `[-]`

## 0.8 执行期护栏（执行域声明 + Fail→Narrow）
- [ ] 0.8.1 写域声明（必须）：按 `references/execution-guard.md` 明确 Allow/Deny/NewFiles/Refactor，并把结论写入 `task.md##上下文快照` 的“决策”区（作为可恢复检查点）
- [ ] 0.8.2 失败即收敛：当 Patch/修改不符合预期或开始扩大范围时，先按 `references/execution-guard.md` 执行 Fail→Narrow（最多 1 轮），并把失败证据/已尝试/下一步唯一动作写入 `task.md##上下文快照`；禁止直接扩大边界继续“硬修”

## 0.9 子代理侦察/独立审查（仅触发时展开）
- [ ] 0.9.1 仅当存在高不确定性且需要并行侦察 / 独立审查时，按 `references/checklist-triggers.md` 与 `references/subagent-orchestration.md` 执行；未命中可标 `[-]`

## 1. 执行任务
- [ ] 1.1 在 `path/to/file.ts` 中实现 [具体功能]，验证 why.md#[需求标题anchor]-[场景标题anchor]
- [ ] 1.2 在 `path/to/file.ts` 中实现 [具体功能]，验证 why.md#[需求标题anchor]-[场景标题anchor]，依赖任务1.1

## 3. 安全检查（仅触发时展开）
- [ ] 3.1 仅当涉及外部输入 / 权限 / 支付 / 生产变更 / 敏感信息等信号时，执行安全检查（输入验证、敏感信息处理、权限控制、EHRB 风险规避）；未命中可标 `[-]`

## 4. 文档更新（仅触发时展开）
- [ ] 4.1 仅当契约 / 公共接口 / 数据模型 / 架构变化时，更新对应知识库或说明文件；未命中可标 `[-]`

## 5. 质量门禁与验证
- [ ] 5.0 运行 `verify_min`（最小-最快-最高信号）：优先用能覆盖成功标准的最小验证动作收口；记录证据（命令+结果摘要），失败则按失败协议收敛升级（参考 `references/quality-gates.md`、`references/failure-protocol.md`）
- [ ] 5.1（按适用项展开）从 `fmt/lint/typecheck/build/test/security` 中只保留本次适用且项目已定义命令的项；未触发项标 `[-]` 并写明原因
  - 建议顺序：fmt → lint → typecheck → build → test → security
  - `build` 触发式推荐默认：若本次改动触及可编译/可发布路径且项目存在 build 命令，执行 build
  - `test` 默认推荐执行；若项目无测试入口则标 `[-]`，但必须保留 `verify_min` 闭环

---

## 6. Review（必做）
- [ ] 6.1 Review-规格一致性：对齐摘要（目标/成功标准/非目标/约束）与实现/任务/验证保持一致；`## 上下文快照` 覆盖关键决策/约束/下一步唯一动作且来源标签齐全；`HAGSWorks/active_context.md` 可续作且 Public APIs 具备 `[SRC:CODE]` 指针
- [ ] 6.2 Review-结构与质量：边界/依赖方向正确；不新增重复；命名与抽象可读；避免 utils 膨胀；快照“事实区”不得混入推断；active_context 不得出现“无来源事实”
- [ ] 6.3 记录 Review：在文末 `## Review 记录` 填写（问题≤5条/修复≤5条/复测摘要）
- [ ] 6.4 如 Review 引入修复：重跑受影响门禁（通常为 fmt/lint/typecheck/build/test），最多 3 轮“Review→修复→复测”
- [ ] 6.5 交付前收尾：按 `references/finish-checklist.md` 自检（证据/快照/active_context/输出格式）

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

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=... head=... dirty=... diffstat=...
<!-- 推荐采集: git rev-parse --abbrev-ref HEAD / git rev-parse --short HEAD / git status --porcelain / git diff --stat -->

### 错误与尝试（防重复，按需）

提示：若遇到“输出不完整/压缩或续作异常”（例如 `response.incomplete`、工具输出被截断），先按失败协议记录证据并执行断层恢复（避免重复修改与越界）。

| 错误/症状 | 尝试 | 结果/证据 | 结论（避免重复） |
|---|---:|---|---|
| | 1 | | |

### 用户原话（验收/约束/偏好）
- [SRC:USER] “...”

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|USER|TOOL] 决策: …
  - 理由: …
  - 影响: …

### 功能删减审批
- `feature_removal_approved: no`
- `approved_scope:`
- `approved_target:`
- `approved_reason:`
- `replacement_behavior:`

### 待确认 / 假设（推断必须在此）
- [SRC:INFER][置信度: 中] 假设: …
  - 若成立: …
  - 若不成立: …
  - 需要确认: …
- [SRC:TODO] 缺失信息: …
  - 影响: …

### 待用户输入（Pending）
<!-- 无则留空 -->
<!-- 触发“功能删减确认”时示例：- [SRC:TODO] 等待用户确认是否允许本次功能删减（影响: 未获批准前不得继续相关修改） -->

### 下一步唯一动作（可执行）
- 下一步唯一动作: `...` 预期: ...

---

## Active Context 更新记录
（如本次影响公共接口/契约/数据流，在此记录更新摘要；每条 Public API 必须带 `[SRC:CODE] path symbol`（行号可选））

---

## Review 记录
（实现完成后填写：发现的问题/采取的修复/复测结果）
