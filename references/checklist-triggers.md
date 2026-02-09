# 触发器与清单（Trigger Matrix）

目标：把“什么时候该做哪些检查”从模糊经验变成可复用规则；在不引入 hooks/运维系统的前提下，用**触发式清单**提升对齐与交付质量。（若你来自 hooks 心智模型，可先读 `references/hook-simulation.md` 看生命周期映射。）

原则：
- 清单是“思考脚手架”，**仅在触发时读取与执行**（渐进式加载）
- 不需要逐条复述清单；只需把关键结论落盘到 `how.md` / `task.md` / `HAGSWorks/active_context.md`
- 栈无关：具体命令来自 `HAGSWorks/project.md#项目能力画像`

---

## 1) 触发矩阵（命中即执行）

| Checklist | 触发信号（任一即算） | 执行时机 | 读取文件 | 结论落点（最小） |
|---|---|---|---|---|
| 开工前检查 | 准备开始写/改代码 | 第一次改代码前（开发实施） | `references/pre-implementation-checklist.md` | `how.md`（边界/复用/重构预算）+ `task.md##上下文快照` |
| 状态机强化（任务拆分/状态/决策落盘） | 影响文件>5 或跨模块/跨层（≥3 层）；或需求 Delta（成功标准/非目标/约束变化）；或连续失败≥2 | 命中即执行（优先于继续实现） | `references/context-snapshot.md` + `references/failure-protocol.md` | `task.md`（任务拆分+状态更新）+ `task.md##上下文快照`（决策/失败证据/下一步唯一动作） |
| 跨层一致性 | 变更涉及 ≥3 层；或改契约/Schema/DTO；或多消费者；或改变错误语义/幂等/鉴权等承诺 | 实现前（必要时实现后复核一次） | `references/cross-layer-checklist.md` | `how.md##API设计/##数据模型` + `HAGSWorks/active_context.md` |
| 复用与去重 | 准备新增 util/helper；或同类改动散落多文件；或新增文件/模块但不确定落点 | 实现前（必要时 Review 时复核） | `references/code-reuse-checklist.md` | `how.md##复用与去重策略` |
| 子代理侦察/独立审查 | 大型项目（G4）/跨模块/跨层（≥3 层）/信息缺口大/需要方案对比/需要独立 Review/连续失败≥2 | 方案设计（收集信息/方案对比）或开发实施（动手前/Review 前/破局时） | `references/subagent-orchestration.md` | `task.md##上下文快照`（事实/推断隔离 + 下一步唯一动作） |
| 执行期护栏 | Patch/修改不符合预期；或开始扩大修改范围；或状态漂移；或多 Agent/多人协作有冲突风险 | 实现前（写域声明）+ 失败时（Fail→Narrow） | `references/execution-guard.md` | `task.md##上下文快照`（决策/下一步唯一动作）+ `how.md##重构范围与不变量` |
| 交付前收尾 | 准备输出最终总结/交付；或准备合并/提交/发版 | 最终输出前（Review 前后均可） | `references/finish-checklist.md` | `task.md##Review 记录` + 输出“验证结果”证据 |
| 断层恢复（Resume/Reboot） | 用户说“继续/接着/上次…”但当前不处于追问/确认；或会话不连续/被压缩；或你无法解释“当前目标/下一步” | 任何阶段开始前（优先于继续执行） | `references/resume-protocol.md` | `task.md##上下文快照`（检查点 + 下一步唯一动作） |
| 破局（停止空转） | 连续阻断失败达到阈值；或同一错误反复出现且原因不明 | 达到阈值立即执行 | `references/break-loop-checklist.md` + `references/failure-protocol.md` | `task.md##上下文快照` + 向用户给 2–3 个决策选项 |

---

## 2) 落盘规则（避免把推断固化为事实）

- **关键决策/约束/下一步唯一动作/失败证据**：写入 `task.md##上下文快照`（事实/推断隔离 + 来源标签）
- **Public API/契约入口**：写入 `HAGSWorks/active_context.md`（每条必须 `[SRC:CODE] path symbol`；行号可选；禁止无来源事实）
- **复用/边界/重构预算**：写入 `how.md` 对应章节（作为后续 Review 的结构质量约束）

---

## 3) 不确定时的默认策略（保守但可推进）

1. 先执行 `references/pre-implementation-checklist.md`，把缺口收敛到 1–3 个高信息增益问题
2. 无法给出可验证事实的内容 → 进入 `task.md##上下文快照` 的“待确认/假设”区（带 `[SRC:INFER]`）
3. 连续失败≥3 → 停止继续试错，按 `references/failure-protocol.md` 升级为用户决策

