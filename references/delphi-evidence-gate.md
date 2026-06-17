<!-- CONTRACT: delphi-evidence-gate v1 -->

# Delphi 工具调用证据门禁（Delphi Evidence Gate）

目标：Delphi/Pascal 任务可以优先使用 CodexMonitor Delphi 语义工具，但必须把“准备好了”和“实际调用了”分开。没有真实工具调用证据时，不得把 `rg` / `Get-Content` 文本搜索 fallback 说成语义查询。

适用：涉及 `.pas/.dpr/.dfm/.fmx/.lfm/.inc`、Delphi 单元、窗体事件、类/方法/字段定义、引用、签名变更或影响面判断的分析、方案和执行阶段。

---

## 1) 证据等级

从强到弱：

1. **真实调用证据（可声明已使用）**
   - 当前对话/运行时出现 native tool call：`delphi.find_symbols`、`delphi.find_definition`、`delphi.find_references`、`delphi.impact_analysis`、`delphi.get_symbols_overview`、`delphi.index_workspace`、`delphi.refresh_index`。
   - 或 CodexMonitor / runtime 日志、probe 记录出现 `item/tool/call namespace=delphi`，并能对应到本次任务。
2. **工具返回证据（可引用结果）**
   - 上述真实调用返回了结构化结果，如 symbol、definition、references、impact、warnings、risks。
   - 可作为定位和影响面证据；若返回 `partial` / `warnings` / `risks`，必须同步记录限制。
3. **工具可见/准备证据（不能声明已使用）**
   - `dynamicTools` 注入、工具列表里存在 `delphi.*`、索引状态为 `ready`、代码里实现了 executor。
   - 这些只说明“可能可以调用”，不能证明本轮已经调用过。
4. **文本 fallback 证据（必须标注降级）**
   - 只看到 shell、`rg`、`Get-Content`、`Select-String`、普通文件读取。
   - 只能说“未观察到 Delphi 语义工具调用，已降级到文本搜索 fallback”，不得说“已使用 Delphi 语义工具/语义查询完成”。

---

## 2) 输出口径

- 只有满足等级 1 或等级 2，才能写：
  - “已使用 Delphi 语义工具定位/查引用/做影响分析”
  - “Delphi 语义工具结果显示……”
- 只有等级 3 时，只能写：
  - “Delphi 工具看起来已注入/索引已准备，但本轮尚无真实调用证据”
- 只有等级 4 时，必须写：
  - “未观察到 Delphi 语义工具调用，已降级到文本搜索 fallback”
  - 并说明降级原因：工具不可见、调用失败、未暴露给当前 runtime、任务非 Delphi 语义范围，或原因未知。

---

## 3) 流程要求

Delphi/Pascal 任务优先尝试语义路径：

1. `delphi/getIndexStatus`
2. `delphi/indexWorkspace` 或 `delphi/refreshIndex`（仅在 `missing/stale` 时）
3. `delphi/getSymbolsOverview`
4. `delphi/findDefinition`
5. `delphi/findReferences`
6. `delphi/impactAnalysis`

若任一步没有真实 `delphi.*` tool call 证据，就按 fallback 处理；可以继续用 `rg` / 精读少量代码完成任务，但最终必须如实标注证据来源。

---

## 4) 禁止事项

- 禁止把 `dynamicTools` 注入、hooks 提醒、索引 ready、代码里有实现，当成“本轮已经用过 Delphi 工具”。
- 禁止在实际工具调用只有 `pwsh rg` / `Get-Content` 时，输出“语义工具已查询”“已查定义/引用/影响面”。
- 禁止用 fallback 结果覆盖方案包状态、代码事实或验证证据。
- 禁止为了证明工具有效而改 CodexMonitor、daemon、parser、runtime；本规则只约束 HelloAGENTS skill 的分析与输出口径。
