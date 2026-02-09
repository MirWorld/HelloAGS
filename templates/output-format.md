# 输出规范（G6.1 ~ G6.4）

本文件为输出规范的单一来源，用于快速引用与复用示例。

`SKILL.md` 与各阶段规则（`analyze/`、`design/`、`develop/`、`kb/`）应引用本文件，而不是在多处重复维护输出规范。

---

## G6.1 | 统一输出格式

<output_format>

⚠️ **CRITICAL - 强制执行规则:**

**1. MUST使用规范格式** - 任何代码/文档改动完成后，ALWAYS使用以下格式之一输出:
   - 微调模式完成
   - 轻量迭代完成
   - 开发实施完成
   - 命令完成（~auto/~plan/~exec/~init）

**2. NO自由文本** - NEVER使用无格式的自由文本描述任务完成

**3. 验证步骤** - 输出前MUST自检:
   ```
   [ ] 确认当前模式
   [ ] 确认使用正确的格式模板
   [ ] 确认包含【HelloAGENTS】标识
   [ ] 确认包含状态符号(✅/❓/⚠️/🚫/❌)
   [ ] 确认文件清单使用纵向列表
   ```

**4. 验证要求** - 任何写入操作后MUST重述:
   - 改动了什么
   - 在哪里改动（文件清单）
   - 验证结果

---

⚠️ **CRITICAL - 清单显示规范（MUST遵守）:**

**所有清单MUST使用纵向列表格式:**

```
文件清单:
📁 变更:
  - {文件路径1}
  - {文件路径2}
  ...
（无变更时: 📁 变更: 无）

遗留方案清单:
📦 遗留方案: 检测到 X 个未执行的方案包:
  - {方案包名称1}
  - {方案包名称2}
  ...
是否需要迁移至历史记录?

其他清单（已符合规范）:
- 追问问题: 1. {问题}...
- 用户选项: [1] {选项}...
- 失败任务: - [X] {任务}...
```

---

**模板方法模式:** 所有阶段完成时的唯一输出结构。

**渲染结构：**
```
{状态符号}【HelloAGENTS】- {阶段名称}

[阶段输出: ≤5条结构化要点]

────
📁 变更:
  - {文件路径1}
  - {文件路径2}
  ...

🔄 下一步: [≤2句建议]

[📦 遗留方案: (按G11规则显示，如有)]
```

**状态符号映射:**
- ✅ : 阶段成功完成
- ❓ : 等待用户输入/选择
- ⚠️ : 警告/部分失败/需要用户决策
- 🚫 : 操作已取消
- ❌ : 严重错误/路由失败
- 💡 : 咨询问答（技术咨询、概念解释）

**阶段名称:**
- 需求分析、方案构思、方案设计、开发实施
- 微调模式完成、轻量迭代完成
- 全授权命令完成、规划命令完成、执行命令完成、知识库命令完成
- 咨询问答

**遗留方案提醒:**
  触发场景: 方案设计/轻量迭代/开发实施/规划命令/执行命令/全授权命令完成时
  执行规则: 按G11扫描并显示
  显示位置: 输出格式末尾的可选插槽

**适用范围:** 阶段最终完成时的总结输出（不适用于追问、中间进度）

**语言规则:** 遵循G1，所有自然语言文本按{OUTPUT_LANGUAGE}生成
</output_format>

---

## G6.2 | 异常状态输出格式

<exception_output_format>
**适用范围:** 非正常完成的阶段输出（取消、错误、警告、中断等）

**EHRB安全警告:**
```
⚠️【HelloAGENTS】- 安全警告

检测到高风险操作: [风险类型]
- 影响范围: [描述]
- 风险等级: [EHRB级别]

────
⏸️ 等待确认: 是否继续执行?（确认/取消）
回复契约: 只回复 `确认` 或 `取消`

<helloagents_state>
version: 1
mode: auto               # plan|exec|auto|init|qa（运行态必须单值）
phase: routing            # routing|analyze|design|develop|kb（运行态必须单值）
status: awaiting_user_input
awaiting_kind: confirm    # questions|choice|confirm（运行态必须单值）
package:                  # 无方案包则留空；有则填写 HAGSWorks/plan/YYYYMMDDHHMM_<feature>/
next_unique_action: "等待用户回复 确认/取消"
</helloagents_state>
```

**风险升级(从简化模式升级):**
```
⚠️【HelloAGENTS】- 风险升级

检测到EHRB信号，已从[微调模式/轻量迭代]升级至[标准开发/完整研发]。
- 风险类型: [具体风险]

────
🔄 下一步: 将按[目标模式]流程继续处理
```

**用户取消操作:**
```
🚫【HelloAGENTS】- 已取消

已取消: [操作名称]
────
🔄 下一步: [后续建议，如有]
```

**流程终止(用户主动终止):**
```
🚫【HelloAGENTS】- 已终止

已终止: [阶段名称]
- 进度: [已完成/未完成的工作简述]

────
🔄 下一步: 可重新开始或进行其他操作
```

**路由/验证错误:**
```
❌【HelloAGENTS】- 执行错误

错误: [错误描述]
- 原因: [具体原因]

────
🔄 下一步: [修复建议]
```

**任务部分失败询问:**
```
⚠️【HelloAGENTS】- 部分失败

执行过程中部分任务失败:
- [X] [任务1]: [失败原因]
- [X] [任务2]: [失败原因]

[1] 继续 - 跳过失败任务，完成后续步骤
[2] 终止 - 停止执行，保留当前进度

────
🔄 下一步: 请输入序号选择
回复契约: 只回复 `1` 或 `2`

<helloagents_state>
version: 1
mode: exec                # plan|exec|auto|init|qa（运行态必须单值）
phase: develop            # routing|analyze|design|develop|kb（运行态必须单值）
status: awaiting_user_input
awaiting_kind: choice     # questions|choice|confirm（运行态必须单值）
package:                  # 无方案包则留空；有则填写 HAGSWorks/plan/YYYYMMDDHHMM_<feature>/
next_unique_action: "等待用户输入序号 1-2"
</helloagents_state>
```

**无效输入再次询问:**
```
❓【HelloAGENTS】- [当前阶段]

输入无效，请重新选择。
[原选项列表]

────
🔄 下一步: 请输入有效选项
回复契约: 只回复一个有效选项（例如 `1`）

<helloagents_state>
version: 1
mode: auto                # plan|exec|auto|init|qa（运行态必须单值）
phase: routing            # routing|analyze|design|develop|kb（运行态必须单值）
status: awaiting_user_input
awaiting_kind: choice     # questions|choice|confirm（运行态必须单值）
package:                  # 无方案包则留空；有则填写 HAGSWorks/plan/YYYYMMDDHHMM_<feature>/
next_unique_action: "等待用户输入有效选项"
</helloagents_state>
```

**评分不足追问(推进模式打破静默):**
```
❓【HelloAGENTS】- 需求分析

[推进模式] 需求完整性评分 X/10 分，需补充信息后继续。

1. [问题1]
2. [问题2]
...

请补充后回复，或输入"取消"终止当前命令。
回复契约: 按序号逐条回答（例如 `1) ... 2) ...`），或回复 `取消`

<helloagents_state>
version: 1
mode: auto
phase: analyze
status: awaiting_user_input
awaiting_kind: questions
package:
next_unique_action: "等待用户补充需求信息或取消"
</helloagents_state>
```
</exception_output_format>

---

## G6.3 | 咨询问答输出格式

<qa_output_format>

**适用范围:** 所有直接回答场景（技术咨询、问候、确认等非开发流程交互）

**核心约束:**
- MUST使用 `💡【HelloAGENTS】- 咨询问答` 格式
- 长度约束: 简单≤2句 | 典型≤5要点 | 复杂=概述+≤5要点

**输出结构:**
```
💡【HelloAGENTS】- 咨询问答

[回答内容 - 遵循长度约束]
```

**示例:**
```
💡【HelloAGENTS】- 咨询问答

客户端错误在 src/services/process.ts:712 的 connectToServer 函数中处理。连接失败后会重试3次，全部失败则标记为 failed 状态。
```

</qa_output_format>

---

## G6.4 | 交互询问输出格式

<interactive_output_format>

**适用范围:** 需要用户选择/确认的交互场景（非阶段完成、非异常状态）

**交互状态标记块（必须）**

当本轮输出需要用户输入/选择/确认（即“下一轮必须只处理用户回复”）时，必须在输出末尾追加以下标记块，用于路由稳定识别“等待状态”（细则：`references/routing.md`）：

**运行态渲染规则（硬约束，防跑偏/防断层）**
- `mode/phase/awaiting_kind` 必须填**单值**（不得出现 `|`）
- `package` 必须为空或真实路径（不得出现 `...`）
- `next_unique_action` 必须以“等待用户”开头，且与“回复契约”一致（下一轮只处理用户回复）
- 允许用户在**满足回复契约后**追加“Delta 纠偏行”（例如 `新增约束:` / `纠偏:` / `非目标:` / `允许:` / `禁止:`），系统会先处理 Delta 再处理回复（细则：`references/routing.md` 的“等待态输入解析”）

```
<helloagents_state>
version: 1
mode: plan                 # plan|exec|auto|init|qa
phase: routing              # routing|analyze|design|develop|kb
status: awaiting_user_input
awaiting_kind: choice        # questions|choice|confirm
package:                     # 无方案包则留空；有则填写 HAGSWorks/plan/YYYYMMDDHHMM_<feature>/
next_unique_action: "等待用户输入序号 1-2"
</helloagents_state>
```

约束：
- 必须放在输出最后（不插入到正文中）
- `status=awaiting_user_input` 时，`next_unique_action` 必须是“等待用户输入/选择/确认”的单一动作
- 如果用户回复与 `awaiting_kind` 不匹配：
  - 若用户是在追加 Delta（纠偏/新增约束）：按 `references/routing.md` 的“等待态输入解析”先采纳/落盘 Delta，并保持等待态重发原问题
  - 若既不匹配也不包含 Delta：必须按本节“无效输入再次询问”重试，并保留/更新标记块

**通用模板:**
```
❓【HelloAGENTS】- {场景名称}

[情况说明 - ≤3句]

[1] {选项1} - {说明}
[2] {选项2} - {说明}

────
🔄 下一步: {引导文字}
回复契约: {先按契约回复；可选另起一行追加 Delta（新增约束:/纠偏:/非目标:/允许:/禁止:）}

<helloagents_state>
version: 1
mode: plan                 # plan|exec|auto|init|qa
phase: routing              # routing|analyze|design|develop|kb
status: awaiting_user_input
awaiting_kind: choice        # questions|choice|confirm
package:                     # 无方案包则留空；有则填写 HAGSWorks/plan/YYYYMMDDHHMM_<feature>/
next_unique_action: "等待用户输入序号 1-2"
</helloagents_state>
```

**核心约束:** ❓状态符号 | 选项2-4个 | 说明≤1句 | 必须包含“回复契约”与 `<helloagents_state>`

**特殊场景补充:**

1. **需求变更提示** (Feedback-Delta规则触发):
   ```
   ⚠️【HelloAGENTS】- 需求变更

   检测到重大需求变更: {变更类型}
   ────
   🔄 下一步: 将重新执行需求分析
   ```

2. **上下文确认/命令确认** - 格式见路由机制章节

3. **其他交互场景** - 格式见对应规则文件（方案构思选择、测试失败、代码质量询问等）

</interactive_output_format>

