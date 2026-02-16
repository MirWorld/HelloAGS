---
name: kb
description: 知识库管理完整规则；~init命令或知识库缺失时读取；包含创建、同步、审计、上下文获取规则
---

# 知识库管理 - 完整规则

## 知识库架构

**文件结构:**
```plaintext
HAGSWorks/                 # HelloAGENTS 工作空间（知识沉淀主落点）
├── CHANGELOG.md          # 版本历史（Keep a Changelog）
├── project.md            # 技术约定 + 项目能力画像 + 协作偏好
├── active_context.md     # 派生缓存：可验证接口注册表/系统状态（非 SSOT（真值））
├── scripts/              # 工具脚本（派生层，可删可重建）
│   ├── validate-active-context.ps1  # Active Context 校验脚本（loose/strict，可选）
│   └── validate-plan-package.ps1    # 方案包完整性校验脚本（可选）
├── wiki/                 # 核心文档
│   ├── overview.md       # 项目概述
│   ├── arch.md           # 架构设计
│   ├── api.md            # API 手册
│   ├── data.md           # 数据模型
│   └── modules/<module>.md
├── plan/                 # 变更工作区
│   └── YYYYMMDDHHMM_<feature>/
│       ├── why.md        # 变更提案
│       ├── how.md        # 技术设计
│       └── task.md       # 任务清单
└── history/              # 已完成变更归档
    ├── index.md
    └── YYYY-MM/YYYYMMDDHHMM_<feature>/
```

**路径约定:**
- 本规则集中 `plan/`、`wiki/`、`history/` 均指 `HAGSWorks/` 下的完整路径
- 所有知识库文件必须在 `HAGSWorks/` 目录下创建

**补充（触发式清单）:** 本 Skill 的通用 checklist 采用“命中触发器才读取与执行”的策略（触发信号与结论落点见 `../references/checklist-triggers.md`），避免在 KB 阶段无脑全量执行所有清单。

---

## ~init / ~wiki 幂等初始化协议（必遵守）

目标：把 `${PROJECT_ROOT}/HAGSWorks/` 变成“可写可重建的项目工作区”。`~init` **只做存在性检查 + 缺失补齐 + 轻量校验**，不做全库扫描/不自动生成模块文档（避免噪声与误报）。

### 1) 先定根目录（必须）
- 先按 `../references/read-paths.md#11-确定项目根目录repo-root` 解析 `PROJECT_ROOT`
- 后续所有路径都以 `PROJECT_ROOT` 为基准（避免在子目录生成多份 `HAGSWorks/`）

### 1.1) 工作区目录名纠错与迁移（必须）

目录名唯一合法：`HAGSWorks/`。

兼容旧目录（历史拼写错误）`HAGWroks/` 的迁移规则：
- 若 `HAGSWorks/` **不存在**且 `HAGWroks/` **存在**：在任何读写前，先将 `HAGWroks/` **重命名**为 `HAGSWorks/`（避免后续写到两处造成断层）。
- 若 `HAGSWorks/` 与 `HAGWroks/` **同时存在**：必须阻断并让用户选择（推荐先备份旧目录再继续），禁止擅自合并/删除。
- 若当前 `write_scope = no_write`：不得迁移/重命名；只能提示用户“需要允许写入后才能修正目录名”。

### 2) 先检测，再读/写（必须）
- 任何 `Get-Content HAGSWorks/...` 之前，必须先 `Test-Path`；不存在就跳过读取，转入“按模板补齐”。

### 3) 初始化的最小必需集（缺什么补什么；默认不覆盖）

**目录（缺失即创建）**
- `HAGSWorks/`
- `HAGSWorks/wiki/`
- `HAGSWorks/wiki/modules/`
- `HAGSWorks/scripts/`
- `HAGSWorks/plan/`
- `HAGSWorks/history/`

**文件（缺失即按模板创建）**
- `HAGSWorks/CHANGELOG.md` ← `templates/changelog-template.md`
- `HAGSWorks/project.md` ← `templates/project-template.md`
- `HAGSWorks/active_context.md` ← `templates/active-context-template.md`
- `HAGSWorks/scripts/validate-active-context.ps1` ← `templates/validate-active-context.ps1`
- `HAGSWorks/scripts/validate-plan-package.ps1` ← `templates/validate-plan-package.ps1`
- `HAGSWorks/wiki/overview.md` ← `templates/wiki-overview-template.md`
- `HAGSWorks/wiki/arch.md` ← `templates/wiki-arch-template.md`
- `HAGSWorks/wiki/api.md` ← `templates/wiki-api-template.md`
- `HAGSWorks/wiki/data.md` ← `templates/wiki-data-template.md`
- `HAGSWorks/history/index.md` ← `templates/history-index-template.md`

说明：
- `project.md` 中“项目能力画像”未知项写 `unknown`，不要凭空猜测；后续在执行域取证补齐。
- `wiki/modules/*.md` 默认不生成；只有在用户明确要求“补全模块文档/重建 wiki”时才批量生成（并按 G4 分批）。

### 4) “都在”的情况下怎么判定正常
- 仅做轻量校验（不扫描代码）：
  - `./HAGSWorks/scripts/validate-active-context.ps1`（若文件存在）
  - 核心文件存在且非空（`CHANGELOG.md/project.md/wiki/*.md/history/index.md`）

### 5) 重建语义（覆盖）
- 默认：只补齐缺失（不覆盖已有文件）
- 只有当用户明确说“重建/覆盖/清空再生成”时，才允许覆盖；覆盖前必须让用户二选一确认：
  - [1] 备份旧目录到 `HAGSWorks/_backup_<timestamp>/` 再重建（推荐）
  - [2] 直接覆盖（风险自担）

---

## 核心术语详解

- **SSOT（真值）** (Single Source of Truth): 用于冲突裁决的“真值层”
  - **行为真值:** 代码事实 + 可复现验证证据（测试/门禁/命令输出）
  - **意图真值:** 经确认的 `why.md##对齐摘要`（优先引用用户原话）
  - *规则:* 派生文档（知识库/wiki、`active_context.md`、`task.md##上下文快照`）不得覆盖真值；冲突时以真值为准并回填修正
- **知识库（KB）**: `HAGSWorks/` 下的文档与偏好沉淀主落点（`CHANGELOG.md`, `project.md`, `wiki/*`）；允许过时、可纠错
- **EHRB** (Extreme High-Risk Behavior): 极度高风险行为
- **ADR** (Architecture Decision Record): 架构决策记录
- **MRE** (Minimal Reproducible Example): 最小可复现示例
- **方案包**: 完整方案单元
  - **目录结构**: `YYYYMMDDHHMM_<feature>/`
  - **必需文件**: `why.md` + `how.md` + `task.md`
  - **完整性检查**: 必需文件存在、非空、task.md至少1个任务项

---

## 质量检查维度

1. **完整性**: 必需文件和章节是否存在
2. **格式**: Mermaid图表/Markdown格式是否正确
3. **一致性**: API签名/数据模型与代码是否一致
4. **安全**: 是否包含敏感信息（密钥/PII）
5. **可运行性**: `project.md` 是否包含“项目能力画像”（至少 test 命令可用）
6. **可续作性**: `active_context.md` 是否存在且 Public APIs 具备 `[SRC:CODE]` 指针（细则：`references/active-context.md`）

**问题分级:**
- **轻度**（可继续）: 缺失非关键文件、格式不规范、描述过时
- **重度**（需处理）: 核心文件缺失、内容严重脱节(>30%)、存在敏感信息

---

## 项目上下文获取策略

<context_acquisition_rules>
**步骤1: 先检查知识库（如存在）**
- 读取前必须先 `Test-Path`；不存在则跳过，不得让 `Get-Content` 报错中断。
- 核心文件: `project.md`, `wiki/overview.md`, `wiki/arch.md`
- 快速续作入口（如存在）: `active_context.md`（只信带 `[SRC:CODE]` 的条目）
- 按需选择: `wiki/modules/<module>.md`, `wiki/api.md`, `wiki/data.md`
  - 其中 `project.md` 的“协作与偏好”可用于推断输出详略、测试偏好、风险容忍度（提升对使用者的理解）
  - 其中 `project.md` 的“项目能力画像”用于确定 build/test/fmt/lint/typecheck 等命令（提升跨技术栈的可执行性）
  - 其中 `active_context.md` 是派生缓存（非 SSOT（真值）），用于快速定位模块 Public APIs 与关键契约；与代码冲突时以真值为准并修正

**步骤2: 知识库不存在/信息不足 → 全面扫描代码库**
- 前置闸门：若当前处于**需求分析阶段**且未通过 Evaluate Gate（评分<7 且用户未明确确认“以现有需求继续/先看代码再说”），禁止扫描；只记录缺口并转入追问/等待用户补充。
- 使用 Glob 获取文件结构
- 使用 Grep 搜索关键信息
- 获取: 架构、技术栈、模块结构、技术约束
</context_acquisition_rules>

---

## 知识库同步规则

<kb_sync_rules>
**触发时机:** 代码变更后，必须立即同步更新知识库

**步骤1 - 模块规范更新:**
- 读取当前方案包 `plan/YYYYMMDDHHMM_<feature>/why.md` 的 **核心场景** 章节（在迁移前读取）
- 提取需求和场景（需求需标注所属模块）
- 更新 `wiki/modules/<module>.md` 的 **规范** 章节
  - 不存在 → 追加
  - 已存在 → 更新

**步骤1.1 - 上下文快照对齐（可选但高收益）:**
- 若 `plan/YYYYMMDDHHMM_<feature>/task.md` 包含 `## 上下文快照`：
  - 只提取其中“已确认事实/决策”里**适合长期沉淀**的内容（必须具备 `[SRC:USER|CODE|TOOL]` 证据）
  - 禁止把“待确认/假设（[SRC:INFER]/[SRC:TODO]）”写入知识库主文档；它们应保留在方案包历史中
  - 适用落点：
    - 团队协作偏好/长期约束 → `project.md`
    - 稳定的架构决策 → `wiki/arch.md` 或补齐到 `how.md` 的 ADR

**步骤2 - 按变更类型更新:**
- API变更 → 更新 `wiki/api.md`
- 数据模型变更 → 更新 `wiki/data.md`
- 架构变更/新增模块 → 更新 `wiki/arch.md`
- 模块索引变更 → 更新 `wiki/overview.md`
- 技术约定变更 → 更新 `project.md`
  - 如识别到用户/团队偏好发生变化（例如：默认少解释/必须写测试/偏好最小改动），同步更新 `project.md` 的“协作与偏好”

**步骤3 - ADR维护（如包含架构决策）:**
- 提取 ADR 信息（在迁移前从 `plan/YYYYMMDDHHMM_<feature>/how.md` 的 **架构决策 ADR** 章节读取）
- 在 `wiki/arch.md` 的 **重大架构决策** 表格中追加
- 链接到 `history/YYYY-MM/YYYYMMDDHHMM_<feature>/how.md#adr-xxx`
- **注意:** 此时写入的 history/ 链接为预计算路径

**步骤4 - 清理:**
- 删除过时信息、废弃API、已删除模块

**步骤5 - 缺陷复盘（修复场景专属）:**
- 在模块文档中添加"已知问题"或"注意事项"
- 记录根因、修复方案、预防措施
</kb_sync_rules>

---

## 知识库缺失处理

<kb_missing_handler>
**STEP 1: 检查核心文件是否存在**
- `CHANGELOG.md`, `project.md`, `wiki/*.md`

**STEP 2: 知识库不存在**
按阶段处理:
```yaml
需求分析阶段:
  - 只标记问题，不创建知识库
  - 在总结中提示"知识库缺失，建议先执行 ~init 命令"

方案设计/开发实施阶段:
  - 默认先执行“幂等初始化协议”：按模板补齐最小骨架（不扫描模块/不跑项目门禁/不写业务代码）
  - 只有当用户明确要求（例如“重建 wiki/补全模块文档/生成 API 文档/生成数据字典”）时，才进行扫描与批量生成，并遵循：
    - 大型项目（按 G4 判定）分批处理（每批≤20个模块）
    - 所有生成内容必须可回滚/可重建，且不覆盖真值层（代码事实 + 可复现验证证据 + why.md##对齐摘要）
  - `project.md` 的“项目能力画像”未知项写 `unknown`；在执行域取证补齐（细则：`references/project-profile.md`、`references/stack-detection.md`）
  - `active_context.md` 的最小要求（同上，且校验脚本可用）：
    - 文件存在且≤120行
    - Public APIs 条目（如有）必须包含 `[SRC:CODE] path symbol`（行号可选）
    - 推断/待确认只能写入风险区（禁止混入事实区）
```

**STEP 3: 知识库存在**
```yaml
执行质量前置检查:
  重度问题 → 全面扫描并重建（方案设计/开发实施阶段）
  轻度问题 → 继续流程
```
</kb_missing_handler>

---

## 遗留方案处理

### 用户选择迁移流程

<legacy_plan_migration>
**适用场景:** 用户响应"确认迁移"后的批量处理流程

**步骤1 - 用户选择迁移范围:**

列出所有遗留方案包，询问用户选择:
```
检测到 X 个遗留方案包，请选择迁移方式:
- 输入"全部" → 迁移所有遗留方案包
- 输入方案包序号（如 1, 1,3, 1-3）→ 迁移指定方案包
- 输入"取消" → 保留所有遗留方案包

方案包清单:
[1] 202511201300_logout
[2] 202511201400_profile
[3] 202511201500_settings
```

**用户响应处理:**
- "全部" → 迁移所有
- 单个序号（如 1）→ 迁移第1个
- 多个序号（如 1,3）→ 迁移指定的
- 序号范围（如 1-3）→ 迁移第1到第3个
- "取消" → 保留所有
- 其他输入 → 再次询问

**步骤2 - 逐个迁移选定的方案包:**

```yaml
for each 选定的方案包:
  1. 更新任务状态: 所有任务状态更新为 [-]
     顶部添加: > **状态:** 未执行（用户清理）

  2. 迁移至历史记录目录:
     - 从 plan/ 移动到 history/YYYY-MM/
     - YYYY-MM 从方案包目录名提取
     - 同名冲突: 禁止覆盖；如目标已存在则追加 `_v2/_v3/...`（以 `references/plan-lifecycle.md` 为准）
     - 若 `HAGSWorks/plan/_current.md` 指向了该方案包：迁移后将 `current_package` 置空（避免断层恢复误选）

  3. 更新历史记录索引: history/index.md（标注"未执行"）
```

**步骤3 - 输出迁移摘要:**
```
✅ 已迁移 X 个方案包至 history/:
  - 202511201300_logout → history/2025-11/202511201300_logout/
  - 202511201500_settings → history/2025-11/202511201500_settings/
📦 剩余 Y 个方案包保留在 plan/:
  - 202511201400_profile
```
</legacy_plan_migration>

### 遗留方案扫描与提醒机制

<legacy_plan_scan>
**触发时机:**
- 方案包创建后: 方案设计完成、规划命令完成、轻量迭代完成
- 方案包迁移后: 开发实施完成、执行命令完成、全授权命令完成

**扫描逻辑:**
1. 扫描 plan/ 目录下所有方案包目录
2. 排除本次已执行的方案包（读取CURRENT_PACKAGE变量）
3. 清除CURRENT_PACKAGE变量
4. 剩余方案包即为遗留方案

**输出位置:** 自动注入到 G6.1 输出格式的末尾插槽中

**输出格式:**
```
📦 plan/遗留方案: 检测到 X 个遗留方案包([列表])，是否需要迁移至历史记录?
```

列表格式: YYYYMMDDHHMM_<feature>（每个一行，最多5个，超过显示"...等X个"）

**用户响应:**
- 确认迁移 → 执行批量迁移流程
- 拒绝/忽略 → 保留在 plan/ 目录
</legacy_plan_scan>

---

## ~init / ~wiki 命令完成总结格式

严格遵循G6.1统一输出格式:

```
✅【HelloAGENTS】- 知识库命令完成

- 📚 知识库状态: [已创建/已更新/已重建]
- 📊 操作摘要: 扫描X模块, 创建/更新Y文档
- 🔍 质量检查: [检查结果，如有问题]

────
📁 变更:
  - {知识库文件}
  - HAGSWorks/CHANGELOG.md
  - HAGSWorks/project.md
  ...

🔄 下一步: 知识库操作已完成，可进行其他任务
```

