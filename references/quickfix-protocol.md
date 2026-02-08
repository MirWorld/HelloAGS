# Quick Fix（微调）快路径协议（Fast Lane）

目标：当任务看起来很小（例如“改一个参数/改一个阈值/改一个配置值”）时，仍能保持**对齐、可验证、可续作**，并把执行成本压到最低，避免“小改动→大返工”。

本协议解决的核心问题是：小改动的真实风险通常不在“代码量”，而在**真值源不唯一、单位/边界不一致、消费者分散、验证缺失**导致的暗坑。

> 重要：本 Skill 不再支持“只生成 `task.md` 的简化方案包”。任何进入执行（改代码/跑验证/产生变更）的路径，都必须先创建**完整方案包**（`why.md` + `how.md` + `task.md`）。  
> 相关：`references/routing.md`、`references/plan-lifecycle.md`

---

## 1) 何时使用（判定条件）

满足全部条件 → 可走 Quick Fix 快路径，否则升级到标准开发/完整研发：
- 改动型且指令明确（能写成“把 X 从 A 改成 B”）
- 预计改动 ≤2 文件且 ≤30 行
- 不涉及：新依赖/新模块/数据库迁移/契约变更/鉴权语义变更
- 无 EHRB 风险信号（见 `references/safety.md`）

若不确定是否满足：按更保守路径处理（升级到 Light Iteration/标准开发）。

---

## 2) 最小产物（仍是完整方案包，但允许极简）

创建目录：`HAGWroks/plan/YYYYMMDDHHMM_quickfix_<slug>/`

必须包含三个文件（内容允许极简，但不能缺失）：
- `why.md`：至少写 `## 对齐摘要`（目标/成功标准/非目标/约束/风险容忍度/偏好）
- `how.md`：至少写边界与依赖 + 验证计划 + 回滚方式
- `task.md`：至少包含 1 个可执行任务 + `## 上下文快照`（含“下一步唯一动作”）

推荐模板（按需读取，避免过度文档化）：
- `templates/plan-why-quickfix-template.md`
- `templates/plan-how-quickfix-template.md`
- `templates/plan-task-quickfix-template.md`

---

## 3) “改一个参数”专用微清单（避免小事翻车）

当任务属于“改一个参数/改一个阈值/改一个配置值”时，执行前用 30–90 秒完成以下检查，并把结论（带来源标签）写入 `task.md##上下文快照`：

1) **真值源是否唯一？**（同名常量/多份配置/多环境覆盖）
   - 目标：确认“哪个值最终生效”
   - 产出：`[SRC:CODE]` 指向读取入口/默认值/覆盖链路

2) **单位与边界是否一致？**（ms vs s、百分比 vs 小数、默认值与校验逻辑）
   - 目标：避免“看似改了数，实则改了语义”
   - 产出：`[SRC:CODE]` 指向校验逻辑/使用处；若不确定进入 `[SRC:INFER]` 并给验证方式

3) **消费者有哪些？**（启动时读取还是运行时读取，是否缓存）
   - 目标：确认影响面与是否需要重启/刷新
   - 产出：消费者清单（≤5条）+ 关键调用点 `[SRC:CODE]`

4) **是否需要同步文档/示例配置？**（只在项目已有规范要求时）
   - 目标：避免“代码改了但契约没同步”
   - 产出：需要同步的载体路径（README/example config/schema 等），否则明确写“不需要”

5) **验证选哪一个最小动作？**（能最快证明没破坏行为）
   - 目标：用最小成本得到最高信号（见 `references/quality-gates.md` 的“最小-最快-最高信号”）
   - 产出：1 条 `verify_min`（最小验证动作：命令/脚本/测试/可复现手动步骤）+ 预期（写入“下一步唯一动作”或单独标注 `verify_min`）

---

## 4) 快路径执行流程（最小闭包）

1. **只读取证**：定位真值源、消费者、单位/边界（本协议第 3 节）
2. **写检查点快照**：按 `references/context-snapshot.md` 写 Workset + 下一步唯一动作（防断层）
3. **执行域声明（边界收口）**：按 `references/execution-guard.md` 明确 Allow/Deny/NewFiles/Refactor，并落盘到快照决策区
4. **最小改动**：只做必要修改；默认不新增文件、不顺手重构
5. **最小验证**：按 `references/quality-gates.md` 选择最小门禁/验证（失败则按 `references/failure-protocol.md` 收敛升级）
6. **收尾与归档**：按 `references/plan-lifecycle.md` 把方案包迁移到 `HAGWroks/history/YYYY-MM/`，避免 `plan/` 堆积

若任务影响 Public API/契约/数据流：必须更新 `HAGWroks/active_context.md`（见 `references/active-context.md`）。
