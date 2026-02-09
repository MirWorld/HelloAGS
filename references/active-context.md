# Active Context 协议（可验证接口注册表）

目标：把“项目当前状态/公共接口表面（public surface）/关键契约”压缩成一份**可验证、可续作**的缓存，降低长会话/多轮迭代中的接口幻觉与命名漂移。

定位：`HAGSWorks/active_context.md` 是**派生层缓存**（Derived Cache），不是 SSOT（真值）。
- **SSOT（真值）** 是：代码事实 + 可复现验证证据（测试/门禁/命令输出）+ 经确认的 `why.md#对齐摘要`
- active_context 允许重写、允许清空重建；与代码冲突时必须以代码为准并修正 active_context

---

## 1) 写到哪里

- 文件路径：`HAGSWorks/active_context.md`
- 体积约束：**≤120 行**（推荐 80–120 行）
- 写作风格：高密度、列表化、只写“可验证事实”，禁止写流水账

---

## 2) 什么是 Public API（栈无关定义）

Public API = “其他模块/调用方”依赖的外部表面（任一即算）：
- 导出的函数/类/方法（库/包对外入口）
- HTTP/GraphQL/RPC 接口（对外或对内）
- CLI 命令与参数
- 事件/消息 Topic 与 payload 结构
- 数据契约入口（Schema/Migration 约束对外影响面）

原则：只要“改了会破坏调用方”，就必须在 active_context 里登记。

---

## 3) 来源标签与可验证性（硬规则）

### 3.1 `[SRC:CODE]` 指针（强制）

**每一条 Public API 登记必须包含 `[SRC:CODE]` 指针**，格式：
- `[SRC:CODE] path/to/file.ext:123 symbol`

其中：
- `path`：仓库相对路径（可点击/可打开）
- `:123`：行号（1-based）
- `symbol`：**可检索键（无空格）**，用于从代码中快速回找（例如函数/类/方法/handler 名）；避免使用 `GET /path` 这类可能无法在代码中稳定命中的文本

约束：
- `symbol` 必须能在指向文件中命中（建议尽量指向定义处）
- 若符号存在但不在指向行号附近出现：视为**行号漂移**，需要更新指针

允许的替代格式（脚本与人工均可接受）：
- `[SRC:CODE] path/to/file.ext#L123 symbol`

### 3.2 推断隔离（强制）

- active_context 的“事实区”**禁止**出现 `[SRC:INFER]`
- 无法给出 `[SRC:CODE]` 的条目：只能进入“待确认/假设”区，并标注 `[SRC:TODO]` 或 `[SRC:INFER][置信度: 中/低]`

### 3.3 与上下文快照的关系

- `task.md##上下文快照`（见 `references/context-snapshot.md`）负责：决策/失败/下一步/待确认
- `HAGSWorks/active_context.md` 负责：稳定的公共表面与关键契约索引
- 禁止把快照里的推断直接沉淀为全局事实；必须先变成可验证证据（通常是代码事实）

---

## 4) 什么时候必须更新（触发条件）

命中任一条件即必须更新 `HAGSWorks/active_context.md`：
- 新增/修改/删除 Public API（函数/类/路由/CLI/事件）
- 修改跨模块数据结构/契约（DTO/schema/response shape）
- 影响核心数据流承诺（例如鉴权方式、幂等策略、错误码语义）
- 修复导致公共行为变化的 bug（对调用方可见）

最终输出前（Review 前）必须完成一次“漂移校验”（见第 6 节）。

---

## 5) 固定结构（推荐模板）

active_context 建议严格按以下结构组织（模板见 `templates/active-context-template.md`）：
- `## Modules (Public Surface)`：模块 → Public APIs（每条必须 `[SRC:CODE]`）
- `## Contracts Index`：列出契约载体位置（OpenAPI/Proto/SQL schema/types…）
- `## Data Flow Guarantees`：只写“已确认承诺”（必须有证据来源）
- `## Known Gaps / Risks`：只写风险/债务/待确认（允许 `[SRC:TODO]`）
- `## Next`：下一步可执行动作（命令/文件/任务号）

---

## 6) 漂移校验（必须）

目标：保证 active_context 不会“看起来很像真的”但其实早已过时。

校验清单：
- Public APIs 是否 **每条都有** `[SRC:CODE] path:line symbol`
- `path` 是否存在；`line` 是否为有效行号
- `symbol` 是否能在指向文件中命中，且在指向行号附近命中（否则视为漂移）

漂移处理：
- 若指针失效：优先 `rg` 搜索 symbol，定位新位置并更新行号
- 若 API 已删除/改名：更新 active_context（删旧、补新），并在“Known Gaps / Risks”记录一次破坏性变化（如适用）

### 6.1 漂移优先级（必须修 vs 允许欠账）

目标：避免 active_context 变成“看起来很像真的、但不可用”的缓存，同时不把维护成本无限抬高。

- **必须当轮修复（阻断交付）**：本次变更影响 Public API/契约/数据流承诺（见第 4 节触发条件）时，必须当轮修复对应条目的 `[SRC:CODE]` 指针；未修复不得宣称“完成/可交付”
- **允许欠账（必须落盘）**：仅涉及内部实现细节、且不影响 Public Surface 时，可暂时不更新细节；但必须在 `## Known Gaps / Risks` 写明缺口，并在 `## Next` 给出“下一步唯一动作”用于补齐

可选工具：`HAGSWorks/scripts/validate-active-context.ps1`（如项目启用）。

