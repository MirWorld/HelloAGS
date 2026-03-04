# 技术栈探测（只做定位，不做猜测）

目标：在**不预设语言/框架**的前提下，从仓库结构与哨兵文件中**定位项目明确声明的命令**（build/test/fmt/lint/typecheck/security），并把结果固化到 `HAGSWorks/project.md#项目能力画像`。

> 重要：这里的“探测”指 **从仓库里找得到证据**。不要因为看到了某些哨兵文件就去猜“默认命令”。

---

## 1) 命令来源优先级（从强证据到弱证据）

1. 明确的构建入口/脚本：`Makefile`、`justfile`、`Taskfile.yml`、`scripts/*`、`tools/*`
2. 语言/包管理配置里的“命令声明”：例如 `package.json#scripts`
3. CI 配置：`.github/workflows/*`、`azure-pipelines.yml`、`.gitlab-ci.yml`
4. README 指令：`README*`（如果存在）

---

## 2) 栈线索（只用于“去哪找”，不用于“猜命令”）

常见哨兵文件（命中后，进一步去 **1) 命令来源优先级** 找“真实命令”）：
- Node/TS：`package.json`（优先读 `scripts`）
- Python：`pyproject.toml` / `requirements.txt`（优先找仓库脚本/CI/README 的入口）
- Go：`go.mod`
- Rust：`Cargo.toml`
- Java：`pom.xml` / `build.gradle*` / `gradlew`
- .NET：`*.sln` / `*.csproj`
- C/C++：`CMakeLists.txt`
- Delphi：`*.dproj` / `*.dpr`（**强依赖本机 IDE/环境**，若仓库无脚本/CI 声明：保持 `unknown`，不要瞎猜）

---

## 3) 无命令证据时的处理（强制）

当你只看到哨兵文件，但**找不到任何可执行入口**（脚本/CI/README）时：
- 将命令矩阵字段写为 `unknown`（不要编造）
- 在 `task.md##上下文快照` 记录缺口，并向用户索取 **1 条 `verify_min`（最小验证动作）**
- 若允许写入：把 `unknown` 固化到 `HAGSWorks/project.md#项目能力画像`（防止下次继续猜）

---

## 4) 多栈/Monorepo 处理

如果存在多个哨兵文件或多工作区结构：
- 先按目录划分子项目（例如 `apps/*`、`packages/*`、`services/*`）
- 为每个子项目分别记录命令矩阵（写入 `HAGSWorks/project.md` 的“多工作区”）
- 执行任务时只在目标子项目中运行相应命令，避免误跑全仓

