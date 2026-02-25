# 断层恢复协议（Resume Protocol）

目标：当会话被压缩/中断、或你无法依赖聊天上下文继续推进时，基于磁盘中的方案包/知识库/代码事实，在 3 分钟内恢复到“可继续执行”的状态。

核心原则：
- 恢复不靠“记忆”，靠**固定读取顺序 + 可验证证据**
- 恢复的产出必须落到**下一步唯一动作**（命令/任务号/文件修改），避免空泛“继续排查”
- 恢复完成前，必须做一次 **5 问 Reboot Check**，强制把“我在哪/要去哪/下一步是什么”说清楚（见第 2 节第 5 步）

---

## 1) 什么时候触发

命中任一即触发恢复流程：
- 用户输入包含“继续/接着/上次/刚才/中断/上下文没了”等续作意图，但当前会话不处于“追问/选择/确认”状态
- 会话明显不连续（例如中断后重进）或你无法解释“当前任务目标/下一步”
- 检测到模型切换/以不同模型继续/明显 reroute（例如收到 `model/rerouted` 通知；此时禁止依赖“记忆”，必须按磁盘状态恢复）
- 发现“输出不完整/压缩异常”（例如 `response.incomplete`、工具输出被截断），无法确认已完成内容与下一步
- 工具调用密集或失败反复，怀疑上下文即将被压缩（可参考 `references/context-budget.md`）

---

## 2) 固定恢复顺序（只读优先）

按顺序执行，禁止跳步（除非目录不存在）：

0. **确定项目根目录（Repo Root）**
   - 优先使用 `git rev-parse --show-toplevel` 作为 `PROJECT_ROOT`
   - 若失败（非 git 仓库/权限/工具不可用）：以当前工作目录作为 `PROJECT_ROOT`（并在快照“待确认/假设”区标注 `[SRC:INFER][置信度: 中]`）
   - 后续所有 `HAGSWorks/...` 路径（plan/wiki/history/active_context/project 等）都必须相对 `PROJECT_ROOT` 定位与读取
   - monorepo/多子项目：若用户明确指定“以某子目录为工作区根目录”，以用户指定为准，并写入 `HAGSWorks/project.md#项目能力画像`

1. **定位方案包**
   - 优先使用已知 `CURRENT_PACKAGE/CREATED_PACKAGE`（如会话中可得）

   <!-- CONTRACT: resume-package-selection v1 -->
   <resume_package_selection_contract>
   version: 1
   plan_scan_dirs_only: true
   current_pointer_file: HAGSWorks/plan/_current.md
   current_pointer_key: current_package
   current_marker: （current）
   list_current_first: true
   list_sort: timestamp_desc
   list_timestamp_source: dirname_prefix_YYYYMMDDHHMM
   list_tiebreaker: dirname_desc
   </resume_package_selection_contract>

   <!-- CONTRACT: resume-current-package-pointer v1 -->
    - 否则检查 `${PROJECT_ROOT}/HAGSWorks/plan/_current.md`（若存在）：
      - 读取其中的 `current_package: ...` 路径；若为空则视为不存在
      - 约束：`current_package` 必须指向 `HAGSWorks/plan/` 下的方案包目录（禁止指向 history/ 或任意路径）
      - 若该目录存在且看起来是完整方案包（why/how/task 齐全）→ 直接选中（减少断层恢复时的“选包”交互）
      - 若路径无效/目录不存在/不完整 → 忽略该指针，继续按下述规则扫描 `plan/`；并在允许写入时将 `_current.md` 的 `current_package` 置空（自愈，避免下次断层误选）

   - 否则扫描 `${PROJECT_ROOT}/HAGSWorks/plan/`（只看目录；忽略 `_current.md` 等文件）：
      - 0 个：
        - 若存在 `${PROJECT_ROOT}/HAGSWorks/history/index.md` 且非空：视为“无可续作包（可能已归档完成）”，下一步唯一动作应收口为“等待新需求”（或用户明确要做新 Delta/修正时再 `~plan` 新建方案包）
        - 否则：提示用户先 `~plan` 创建方案
      - 1 个：直接选中；若允许写入，则更新 `_current.md` 指针（必要时先创建；自愈）
      - 多个：先尝试“唯一候选自动选包”（仅在确定性唯一时启用）；否则列出清单让用户选（禁止擅自猜）
        - 唯一候选自动选包（确定性规则）：
          - 先对每个包做最小完整性检查：`why.md/how.md/task.md` 均存在且非空
         - 再做“完成态判定”（引用第 3 步的完成态规则；只做判断，不做归档）：
           - 若任务全为 `[√]/[-]` 且 Pending 为空 → 该包视为完成态（不作为续作候选）
           - 否则 → 该包视为可续作候选
         - 候选数 = 1 → 自动选中该包并继续（减少选包交互）
         - 候选数 = 0 → 视为“无可续作包”，按原因分流（默认更无感）：
           - 若存在“不完整/损坏包”（未通过最小完整性检查：`why.md/how.md/task.md` 缺失或为空）：不得擅自归档/删除；提示用户选择：修复该包 / 新建方案 / 放弃续作
           - 若所有包均为“完整且完成态”（任务全为 `[√]/[-]` 且 Pending 为空）：
             - 若允许写入（`write_scope != no_write`）：默认下一步唯一动作=按 `references/plan-lifecycle.md` 将这些包迁移到 `HAGSWorks/history/` 并清空 `_current.md`（防止下次续作误选）
             - 若不允许写入（`write_scope = no_write`）：直接输出“已完成/无需续作”，等待新需求（或用户明确要做新 Delta/修正时再 `~plan` 新建方案包）
         - 候选数 ≥ 2 → 必须走交互选择（不要猜）
       - 排序：若 `_current.md` 指向其中一个包，则该项置顶并标注 `（current）`；其余按目录名时间戳前缀倒序（`YYYYMMDDHHMM`）
       - 若允许写入：在用户选中后更新 `_current.md` 指针（必要时先创建）

1.1 **方案包完整性校验（存在即硬闸）**
   - 若存在 `HAGSWorks/scripts/validate-plan-package.ps1`：**必须**对选中的方案包运行一次完整性校验（`-Mode plan`）
   - 若校验失败：视为“方案包不完整/损坏/未达到可续作门槛”，停止继续执行恢复流程，并要求用户决定：修复该方案包 / 重新 `~plan` 创建新包 / 放弃续作

2. **读取对齐摘要（防跑偏）**
   - 读 `{package}/why.md#对齐摘要`：目标/成功标准/非目标/约束/风险容忍度/偏好

3. **读取任务状态与检查点（找回进度）**
   - 读 `{package}/task.md`：
     - 任务状态分布（[ ]/[√]/[X]/[-]/[?]）
     - `## 上下文快照` 的最新检查点（Workset + 下一步唯一动作）
     - 若存在 `### 待用户输入（Pending）` 且有内容：视为“等待状态”，优先按 Pending 继续（不要凭感觉继续执行）

   <!-- CONTRACT: resume-no-redo v1 -->
   - 完成态判定（防重复执行，硬规则）：
     - 条件：`task.md` 中**所有任务**均为 `[√]` 或 `[-]`，且 `### 待用户输入（Pending）` 为空
     - 行为：判定该方案包已完成；**禁止**再次执行/重复修改任何任务
     - 下一步唯一动作（按 write_scope 自动收口）：
       - 若允许写入（`helloagents_only|code_write`）：按 `references/plan-lifecycle.md` 迁移到 `HAGSWorks/history/` 并更新索引（防止后续压缩/续作误选中）
         - 同时清空 `${PROJECT_ROOT}/HAGSWorks/plan/_current.md` 的 `current_package`（避免指向已归档包）
       - 若不允许写入（`no_write`）：本轮不做任何写入，只输出“已完成/无需续作”，等待新需求（或等待用户允许归档）
     - 例外：若用户提出新问题/必须修正既有结论 → 作为新 Delta 处理（先写 `task.md##上下文快照` 决策，再新增任务或新建方案包），禁止无说明地“二次重做”

   > 例外（允许提前结束恢复）：若 `Pending` 已明确“等待用户输入/选择/确认”的下一步唯一动作，可在此停止继续读取 how.md/active_context 等步骤，直接输出交互询问并等待用户回复。

4. **读取执行约束（防重复/防耦合）**
   - 读 `{package}/how.md`：边界与依赖 / 复用与去重策略 / 重构范围与不变量 / 质量门禁
   - **verify_min（最小验证动作，SSOT）**：
     - 以 how.md 中的 `verify_min: ...` 作为本次变更的最小验证动作（Single Source of Truth）
       - 推荐写在 `## 变更请求（Change/Verify/Don't）`（或同义章节）的 Verify 行，便于快速定位与中途纠偏
     - 若 how.md 缺失 `verify_min`：将其视为闭环缺口
       - 允许写入时：优先补齐到 how.md（可为 `unknown`，但必须写“获取路径”）
       - 不允许写入时（`write_scope=no_write`）：在本轮输出中明确“verify_min 尚缺失”，并把“获取 verify_min 的下一步唯一动作”写到对话结论（等待允许写入后再回填）
     - 若 `task.md##上下文快照` 记录了更晚的纠偏/Delta（例如新增约束导致验证路径变化）：以快照中的最新决策为准，并在允许写入时回填更新 how.md 的 `verify_min`（避免续作时读到两套命令）

5. **5 问 Reboot Check（强制）**
   - 目的：在压缩/中断后，把任务状态压缩成“可继续执行”的确定性描述，避免凭感觉继续导致跑偏
   - 特别强调：当触发原因包含“模型切换/输出不完整/压缩异常”时，Reboot Check 的回答必须以**磁盘事实 + 工具证据**为准，禁止依赖聊天记忆
   - 填写模板（允许写入 `task.md##上下文快照` 的检查点区，便于续作）：

     | 问题 | 回答（必须具体） |
     |---|---|
     | 我在哪？ | 当前阶段（需求/方案/执行/Review）+ 当前方案包（如有） |
     | 我要去哪？ | 下一阶段/剩余里程碑（≤3条） |
     | 目标是什么？ | 1 句话目标（来自 `why.md#对齐摘要`） |
     | 我学到了什么？ | 3–5 条带证据的发现（优先 `[SRC:CODE]`） |
     | 我做了什么？ | 已完成任务号/门禁/改动面（引用 `task.md`/`git diff --stat`） |

6. **读取 Active Context（如涉及公共接口/契约）**
   - 读 `HAGSWorks/active_context.md`：
     - 只信带 `[SRC:CODE]` 指针的条目
     - 需要时用 `rg` 反查 symbol，校验指针未漂移（细则见 `references/active-context.md`）

7. **对齐真实代码状态（Repo State 双证据，推荐默认）**
   - 采集当前 `repo_state`（只读命令，建议按统一格式写入快照）：
     - `git rev-parse --abbrev-ref HEAD`
     - `git rev-parse --short HEAD`
     - `git status --porcelain`
     - `git diff --stat`
   - 若 `task.md##上下文快照` 中已存在 `### Repo 状态` 的 `repo_state:`：对比当前与快照中的最近一次 `repo_state`
     - 一致 → 继续
     - 不一致（包外改动/状态漂移/执行进度未落盘）→ 在允许写入时先追加一条“纠偏检查点”到快照（`[SRC:TOOL] repo_state: ...` + 影响 + 下一步唯一动作），再决定是否需要新增任务/新建方案包（按 Feedback-Delta）
   - 若快照缺失 `repo_state:`：
     - 若允许写入（`write_scope != no_write`）：立即补一条 `[SRC:TOOL] repo_state: ...` 作为检查点（减少下次续作误重做）
     - 若不允许写入（`write_scope = no_write`）：在本轮输出中标注“repo_state 缺失”，并将“补 repo_state”作为下一步唯一动作（等待允许写入）
   - 若发现 `task.md` 的任务状态与当前代码事实/工具证据明显不一致：在 `task.md##上下文快照` 记录一次“纠偏检查点”（标注来源），禁止凭感觉继续

---

## 3) 恢复后的最小产出（必须给出）

恢复完成后必须明确：
- 当前目标（1 句话）
- 当前进度（任务号/状态摘要）
- **下一步唯一动作**（命令/任务号/文件修改，必须可执行）
- 待确认点（≤3，且标注 `[SRC:TODO]` 或 `[SRC:INFER][置信度]`）

并把“下一步唯一动作”写回 `task.md##上下文快照`（作为新的检查点）。

### 3.1 若检测到 Pending（等待用户输入）

当 `{package}/task.md##上下文快照###待用户输入（Pending）` 有内容时：
- 本轮输出必须使用 `templates/output-format.md` 的交互格式（带 `回复契约` + `<helloagents_state status: awaiting_user_input>`）
- 只复述 Pending 中的“问题/选项/影响”，并要求用户按回复契约作答
- （推荐默认）下一步唯一动作应收口为：等待用户回复（避免“继续排查”式空转）

---

## 4) 恢复失败时的处理

- **方案包缺失/不完整**：按 `develop/SKILL.md` 的“方案包不存在/不完整”错误处理；必要时建议重新 `~plan`
- **多个方案包无法判断**：必须询问用户选择（列出清单）
- **对齐摘要缺失或明显过时**：回到需求分析/方案设计补齐（或将相关任务标记为 `[?]` 等待确认）

