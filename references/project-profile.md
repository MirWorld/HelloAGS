# 项目能力画像（Project Profile）

目标：在不预设技术栈的前提下，让 Codex 先“看清项目怎么跑、怎么测、怎么格式化/检查”，再动手改代码；把关键命令固化进知识库，减少反复猜测与误用。

> 设计原则：**可验证优先**。任何“成功标准/验收点”都必须能映射到至少一个验证动作（测试/命令/手动步骤）。

---

## 1) 何时创建/更新

- **允许写入时（建议执行）**：方案设计、开发实施、`~init/~wiki`（可更新 `HAGWroks/project.md`）
- **只读阶段（不写入）**：需求分析阶段只在内存中推断并在输出中标注不确定点，不创建文件

---

## 2) 画像内容（建议 schema）

写入位置：`HAGWroks/project.md` 的 `## 项目能力画像` 章节（模板见 `templates/project-template.md`）。

推荐包含以下字段（未知就写 `unknown`，不要瞎猜）：

- **工作区根目录**：项目的实际入口路径（默认应为 git 仓库根目录；monorepo 可按需指定子目录）
- **技术栈线索**：用于判定栈的哨兵文件列表（如 `package.json`, `pyproject.toml`）
- **命令矩阵**（优先从项目配置中读取，其次才用启发式）：
  - `build`：构建命令
  - `dev/run`：开发/运行命令（如果有）
  - `test`：测试命令（必须）
  - `fmt`：格式化命令（可选）
  - `lint`：静态检查命令（可选）
  - `typecheck`：类型检查命令（可选）
  - `security`：依赖/安全扫描命令（可选）
- **版本/环境约束**：如 Node/Python/Java 等版本、OS/CPU 架构要求（可从 `.nvmrc`、`pyproject.toml`、CI 配置推断）
- **多工作区（可选）**：monorepo 时按子目录分组记录（如 `apps/web`、`services/api`）

---

## 3) 获取流程（栈无关）

0. **先确定工作区根目录（Repo Root）**
   - 优先使用 `git rev-parse --show-toplevel` 作为 `PROJECT_ROOT`
   - 若失败（非 git 仓库/权限/工具不可用）：以当前工作目录作为 `PROJECT_ROOT`（并在假设账本标注 `[SRC:INFER][置信度: 中]`）
   - monorepo/多子项目：若用户明确指定“以某子目录为工作区根目录”，以用户指定为准，并将其写入 `HAGWroks/project.md#项目能力画像` 的“工作区根目录”

1. **先读知识库**：若存在 `HAGWroks/project.md` 且包含 `项目能力画像`，优先使用其中的命令矩阵
2. **不足则探测（只读）**：
   - 通过哨兵文件判定“可能的栈/子项目位置”
   - 打开哨兵文件，寻找真实可用命令（例如 `package.json` scripts、`pyproject.toml` tool 配置）
3. **选择最可信命令**：以项目声明为准；启发式仅作兜底
   - 若项目未声明且命中“高确定性栈”（例如 Rust / .NET），可直接采用 `references/stack-detection.md` 中的“推荐最小闭环（兜底）”作为候选命令矩阵，并在画像中标注“启发式兜底”（后续可被 CI/脚本替换）。
   - 对“强依赖本机环境/IDE 的栈”（例如 Delphi），除非仓库已有明确入口脚本/CI 声明，否则保持 `unknown` 并向用户索取可用命令（避免瞎猜导致误用）。
4. **记录不确定性**：无法确认时写 `unknown`，并在假设账本标注“需要用户确认/需要运行验证”
5. **允许写入时固化**：把探测结果补写进 `HAGWroks/project.md`，后续任务直接复用

栈探测细则与启发式命令表：按需读取 `references/stack-detection.md`。

---

## 4) 质量联动（必做）

一旦建立了命令矩阵：
- `task.md` 的“质量门禁”任务必须引用它（例如“运行 project.md 中定义的 test/lint/typecheck”）
- 任何“成功标准”必须在 `task.md` 中至少对应一个验证动作（测试/命令/手动步骤）

质量门禁分级与阻断规则：见 `references/quality-gates.md`。
