# 任务清单: [功能名称]

目录: `HAGSWorks/plan/YYYYMMDDHHMM_<feature>/`

最小闭环（建议只盯这几项，其他按触发/推荐执行）：
- 必做：0.1（对齐）/ 0.2（verify_min 绑定）/ 0.6（快照）/ 0.8（执行域声明）/ 5.0（verify_min）/ 6.x（Review）

---

## 0. 对齐确认
- [ ] 0.1 阅读 `why.md#对齐摘要`，确认目标/成功标准/边界/约束无误；如有偏差先修正 why.md 再执行后续任务
- [ ] 0.2 确认 `HAGSWorks/project.md#项目能力画像` 已包含可用命令矩阵（test/fmt/lint/typecheck 等）；并为核心成功标准绑定至少 1 条 `verify_min`（最小验证动作，命令/测试/脚本/可复现手动步骤皆可）；如缺失则补齐后再继续
- [ ] 0.3（推荐）执行复用检索：按 `references/code-reuse-checklist.md` 搜索现有相似实现与可复用组件，避免重复造轮子；在 how.md 的“复用与去重策略”记录结论
- [ ] 0.4（推荐）确认边界与依赖方向：新增/修改代码应落在正确模块层，避免跨层 import；在 how.md 的“边界与依赖”记录约束

## 0.5 跨层一致性（触发式）
- [ ] 0.5.1 触发判定：按 `references/checklist-triggers.md` 判断是否命中跨层触发器（≥3层/改契约/多消费者/语义承诺变化等）
- [ ] 0.5.2 如触发：按 `references/cross-layer-checklist.md` 清点受影响层/契约/消费者；补齐 how.md 的契约与兼容策略；必要时同步更新 `HAGSWorks/active_context.md`

## 0.6 上下文快照（中期落盘，触发式必做）
- [ ] 0.6.1 初始化：确认文末存在 `## 上下文快照` 区块（缺失则创建）
- [ ] 0.6.2 触发式维护：关键决策/需求变更/阻断失败/会话可能中断/最终输出前，按 `references/context-snapshot.md` 追加/更新快照并标注来源标签；每次快照更新必须包含“下一步唯一动作”；推断只能写入“待确认/假设”区

## 0.7 Active Context（可验证接口注册表，触发式必做）
- [ ] 0.7.1 阅读 `HAGSWorks/active_context.md`：把它当作公共接口入口清单（派生层，非 SSOT（真值）），只信带 `[SRC:CODE]` 的 Public APIs 条目
- [ ] 0.7.2 如本次变更影响公共接口/契约/数据流：更新 `HAGSWorks/active_context.md`（每条 Public API 必须包含 `[SRC:CODE] path symbol`；行号可选），并在 Review 前完成校验（可选运行 `HAGSWorks/scripts/validate-active-context.ps1 -Mode loose|strict`）

## 0.8 执行期护栏（执行域声明 + Fail→Narrow）
- [ ] 0.8.1 写域声明（必须）：按 `references/execution-guard.md` 明确 Allow/Deny/NewFiles/Refactor，并把结论写入 `task.md##上下文快照` 的“决策”区（作为可恢复检查点）
- [ ] 0.8.2 失败即收敛：当 Patch/修改不符合预期或开始扩大范围时，先按 `references/execution-guard.md` 执行 Fail→Narrow（最多 1 轮），并把失败证据/已尝试/下一步唯一动作写入 `task.md##上下文快照`；禁止直接扩大边界继续“硬修”

## 0.9 子代理侦察/独立审查（触发式，可选）
- [ ] 0.9.1 触发判定：按 `references/checklist-triggers.md` 判断是否命中“子代理侦察/独立审查”
- [ ] 0.9.2 如触发：按 `references/subagent-orchestration.md` 进行只读侦察/独立审查（子代理禁止写入/禁止再分裂），并将“结论+证据指针+风险/不确定点+下一步唯一动作”写入 `task.md##上下文快照`

## 1. [核心功能模块名称]
- [ ] 1.1 在 `path/to/file.ts` 中实现 [具体功能]，验证 why.md#[需求标题anchor]-[场景标题anchor]
- [ ] 1.2 在 `path/to/file.ts` 中实现 [具体功能]，验证 why.md#[需求标题anchor]-[场景标题anchor]，依赖任务1.1

## 2. [次要功能模块名称]
- [ ] 2.1 在 `path/to/file.ts` 中实现 [具体功能]，验证 why.md#[需求标题anchor]-[场景标题anchor]，依赖任务1.2

## 3. 安全检查
（触发式：外部输入/权限/支付/生产变更/敏感信息等信号命中时必做）
- [ ] 3.1 执行安全检查（输入验证、敏感信息处理、权限控制、EHRB 风险规避）

## 4. 文档更新
（触发式：契约/公共接口/数据模型/架构变化时必做）
- [ ] 4.1 更新 <知识库文件>

## 5. 质量门禁与验证
- [ ] 5.0 运行 `verify_min`（最小-最快-最高信号）：优先用能覆盖成功标准的最小验证动作收口；记录证据（命令+结果摘要），失败则按失败协议收敛升级（参考 `references/quality-gates.md`、`references/failure-protocol.md`）
- [ ] 5.1（推荐默认）执行 fmt（命令来自 `HAGSWorks/project.md#项目能力画像`）；若命令不存在则标记 `[-]` 并写明原因
- [ ] 5.2（推荐默认）执行 lint（命令来自 `HAGSWorks/project.md#项目能力画像`）；若命令不存在则标记 `[-]` 并写明原因
- [ ] 5.3（推荐默认）执行 typecheck（命令来自 `HAGSWorks/project.md#项目能力画像`，如适用）；若不适用/命令不存在则标记 `[-]` 并写明原因
- [ ] 5.4（推荐默认）执行 test（命令来自 `HAGSWorks/project.md#项目能力画像`）；若项目无测试入口则标记 `[-]` 并写明原因（但必须保留 `verify_min` 闭环）
- [ ] 5.5（触发式）如涉及依赖/外部输入/权限，执行 security 门禁（命令来自 `HAGSWorks/project.md#项目能力画像` 或项目既有检查）

---

## 6. Review（必做）
- [ ] 6.1 Review-规格一致性：对齐摘要（目标/成功标准/非目标/约束）与实现/任务/验证保持一致；`## 上下文快照` 覆盖关键决策/约束/下一步唯一动作且来源标签齐全；`HAGSWorks/active_context.md` 可续作且 Public APIs 具备 `[SRC:CODE]` 指针
- [ ] 6.2 Review-结构与质量：边界/依赖方向正确；不新增重复；命名与抽象可读；避免 utils 膨胀；快照“事实区”不得混入推断；active_context 不得出现“无来源事实”
- [ ] 6.3 记录 Review：在文末 `## Review 记录` 填写（问题≤5条/修复≤5条/复测摘要）
- [ ] 6.4 如 Review 引入修复：重跑受影响门禁（通常 fmt/lint/typecheck/test），最多 3 轮“Review→修复→复测”
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

### 错误与尝试（防重复，按需）

| 错误/症状 | 尝试 | 结果/证据 | 结论（避免重复） |
|---|---:|---|---|
| | 1 | | |

### 用户原话（验收/约束/偏好）
- [SRC:USER] “...”

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|USER|TOOL] 决策: …
  - 理由: …
  - 影响: …

### 待确认 / 假设（推断必须在此）
- [SRC:INFER][置信度: 中] 假设: …
  - 若成立: …
  - 若不成立: …
  - 需要确认: …
- [SRC:TODO] 缺失信息: …
  - 影响: …

### 待用户输入（Pending）
- [SRC:TODO] 等待用户回答/选择/确认: …（影响: …）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `...` 预期: ...

---

## Active Context 更新记录
（如本次影响公共接口/契约/数据流，在此记录更新摘要；每条 Public API 必须带 `[SRC:CODE] path symbol`（行号可选））

---

## Review 记录
（实现完成后填写：发现的问题/采取的修复/复测结果）

