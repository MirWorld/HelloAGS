<!-- CONTRACT: plan-lifecycle v1 -->

# 方案包生命周期（G11 细则）

目标：让每次变更都可追溯：方案包 → 执行记录 → 归档索引。

<plan_lifecycle_contract>
version: 1
history_overwrite: deny
history_conflict_suffix: _v2
current_pointer_file: HAGSWorks/plan/_current.md
current_pointer_key: current_package
archive_readiness_gate: required
archive_script: HAGSWorks/scripts/archive-plan-package.ps1
</plan_lifecycle_contract>

---

## 1) 任务状态符号

- `[ ]` 待执行
- `[√]` 已完成
- `[X]` 执行失败（需备注原因）
- `[-]` 已跳过（需备注原因）
- `[?]` 待确认

---

## 2) 创建新方案包

- 路径：`HAGSWorks/plan/YYYYMMDDHHMM_<feature>/`
- 冲突：同名目录存在则追加 `_v2/_v3/...`
- 完整性：必须包含 `why.md` + `how.md` + `task.md` 且非空（`task.md` 至少 1 条任务）
- （推荐默认）更新当前方案包指针：写入 `HAGSWorks/plan/_current.md` 的 `current_package: HAGSWorks/plan/YYYYMMDDHHMM_<feature>/`

---

## 3) 归档就绪门禁（Archive Readiness Gate）

核心原则：**本轮执行结束 ≠ 方案包完成**。长任务、多轮任务、被压缩/中断后的任务，只要仍有未完成项或收尾证据不足，就必须继续保留在 `HAGSWorks/plan/`，并保持 `_current.md` 指向它。

只有同时满足以下条件，才允许迁移到 `HAGSWorks/history/`：
1. `task.md` 中不存在 `- [ ]` / `- [X]` / `- [?]` 任务项；未做项只能明确标为 `[-]` 并写备注。
2. `### 待用户输入（Pending）` 为空。
3. `progress_phase: final` 已作为结构字段写入 `task.md##上下文快照`；任务说明、模板文字、Review 文案里的同名文本不算数。
4. `verify_min` 是具体可执行命令/脚本/可复现手动步骤，且与已触发门禁已有可追溯结果；`unknown` / `无` / 模板占位不允许进入归档。
5. `## Review 记录` 已填写本轮 Review / 修复 / 复测摘要，并能追溯到验证/复测证据；不能只保留模板占位。
6. 若存在 `HAGSWorks/scripts/archive-plan-package.ps1`，归档迁移必须交给该脚本执行；脚本会先运行 Archive Readiness Gate，再迁移目录、更新索引、按需清空 `_current.md`：
   - `pwsh -NoProfile -File HAGSWorks/scripts/archive-plan-package.ps1 -Package <CURRENT_PACKAGE>`
7. 若归档脚本不存在但存在 `HAGSWorks/scripts/validate-plan-package.ps1`，迁移前必须运行：
   - `pwsh -NoProfile -File HAGSWorks/scripts/validate-plan-package.ps1 -Mode archive -Package <CURRENT_PACKAGE>`

门禁未通过时：
- 禁止迁移到 `history/`
- 禁止清空 `HAGSWorks/plan/_current.md`
- 必须把当前进度、剩余任务、下一步唯一动作写回 `task.md##上下文快照`
- 最终输出应说明“本轮已完成哪些，方案包仍保持 active”，等待下一轮继续，而不是临时重规划

---

## 4) 完成态迁移（仅 Archive Readiness Gate 通过后）

默认执行方式：
- 优先使用 `HAGSWorks/scripts/archive-plan-package.ps1` 完成迁移；不要手动拼 `Move-Item`、手动更新 `history/index.md`、手动清空 `_current.md`。
- 脚本返回失败时，视为 Archive Readiness Gate 未通过；脚本应自动回滚到 `HAGSWorks/plan/`，并保留方案包 active；若回滚失败，必须把“半迁移风险”显式写入检查点，再按第 3 节补快照与下一步唯一动作。

1. 回写 `task.md`：所有任务标注真实状态；非 `[√]` 的任务必须写 `> 备注: ...`
2. 迁移目录：`HAGSWorks/history/YYYY-MM/YYYYMMDDHHMM_<feature>/`
   - 冲突：**禁止覆盖**既有 history 目录；如目标目录已存在，则追加 `_v2/_v3/...`
3. 更新索引：追加到 `HAGSWorks/history/index.md`（包含时间戳、功能标识、类型、状态、链接）
   - 推荐同时补“轻量检索元数据”（见 `templates/history-index-template.md` / `references/lightweight-memory.md`）：`tags`、`touched_files`、`decisions`、`verify`、`signals`
   - 元数据只写高价值事实；没有命中可跳过，不要复制方案包正文
4. （推荐默认）清空当前方案包指针：将 `HAGSWorks/plan/_current.md` 的 `current_package` 置空（避免断层恢复误选已归档包）

---

## 5) 遗留方案扫描与清理（可选交互）

触发：
- 方案设计/轻量迭代结束后（新包创建）
- 开发实施/执行命令/全授权命令结束后（迁移完成）

规则：
- 扫描 `HAGSWorks/plan/` 下的方案包目录（忽略 `_current.md` 等文件），但遗留清单必须先过滤候选，不能原样列出所有目录。
- 必须排除 `HAGSWorks/plan/_current.md` 指向的当前 active 包与本次 `CURRENT_PACKAGE`；清除内存变量不等于清空 `_current.md`。
- 必须排除已执行/半执行/完成态但未归档的包；只要存在任务终态、Review/验证记录、运行时事件、压缩事件或 touched files / verify 结果，就应按恢复协议或 Archive Readiness Gate 处理，不能按“未执行清理”迁移。
- 只有完整、非 active、无执行证据、且用户明确放弃执行的包，才可作为“未执行清理”候选；归档时需优先使用 `HAGSWorks/scripts/abandon-plan-package.ps1`，写入 `archive_intent: abandoned_unexecuted`，并明确“未执行验证不是完成证据”。
- 如存在遗留包：在完成输出末尾提示，并提供迁移选择流程（见 `kb/SKILL.md` 的遗留方案迁移规则）
