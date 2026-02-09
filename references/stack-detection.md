# 技术栈探测与命令启发式（Stack Detection）

目标：在不预设语言/框架的情况下，从仓库结构与哨兵文件推断“怎么跑/怎么测/怎么检查”，并把结果固化到 `HAGSWorks/project.md` 的“项目能力画像”。

> 重要：启发式仅作兜底。**优先使用项目配置声明的命令**（scripts/配置文件/CI）。

---

## 1) 探测优先级（从强证据到弱证据）

1. 明确的构建入口/脚本：`Makefile`、`justfile`、`Taskfile.yml`、`scripts/*`
2. 语言/包管理哨兵：`package.json`、`pyproject.toml`、`Cargo.toml`、`go.mod`、`pom.xml`、`build.gradle`、`*.csproj`、`CMakeLists.txt`
3. CI 配置：`.github/workflows/*`、`azure-pipelines.yml`、`.gitlab-ci.yml`
4. README 指令：`README*`（如果存在）

---

## 2) Node/TypeScript（`package.json`）

### 包管理器判定（优先顺序）

- `pnpm-lock.yaml` → `pnpm`
- `yarn.lock` → `yarn`
- 否则 → `npm`

### 命令提取（优先从 scripts）

从 `package.json` 的 `scripts` 中优先找：
- `test` / `test:unit` / `test:ci`
- `lint`
- `format` / `fmt`
- `typecheck`
- `build`
- `dev` / `start`

常见兜底（仅在 scripts 缺失时考虑）：
- `test`: `npm test` / `pnpm test` / `yarn test`
- `typecheck`: `tsc -p .`（前提：存在 `tsconfig.json`）
- `lint`: `eslint .`（前提：存在 eslint 配置）
- `fmt`: `prettier -w .`（前提：存在 prettier 配置）

版本线索（可记录到画像）：
- `.nvmrc` / `.node-version` / `package.json#engines`

---

## 3) Python（`pyproject.toml` / `requirements.txt`）

### 典型测试/检查工具线索

- `pytest`：`python -m pytest`
- `ruff`：`ruff check .`
- `black`：`black .`
- `mypy`：`mypy .`

从 `pyproject.toml` 中优先读取工具配置（例如 `[tool.pytest.ini_options]`、`[tool.ruff]`）。

常见兜底（在无更好信息时）：
- `test`: `python -m pytest`
- `fmt`: `python -m black .`
- `lint`: `python -m ruff check .`
- `typecheck`: `python -m mypy .`

版本线索：
- `pyproject.toml` 的 python 版本约束、`.python-version`

---

## 4) Go（`go.mod`）

优先：
- `test`: `go test ./...`
- `fmt`: `gofmt -w .`

可选：
- `lint`: `golangci-lint run`（仅在配置/依赖存在时）

---

## 5) Rust（`Cargo.toml`）

优先：
- `test`: `cargo test`
- `fmt`: `cargo fmt --check`（不改文件；如需自动修复则用 `cargo fmt`）
- `lint`: `cargo clippy -- -D warnings`（可选，视项目约束/耗时）

语言实现 Playbook（命中 Rust 时建议读取）：
- `references/stacks/rust.md`

推荐最小闭环（通用，兜底）：
- **快路径（最快验证）**：`cargo test`
- **标准路径（更强信号）**：`cargo fmt --check` → `cargo clippy -- -D warnings` → `cargo test`

---

## 6) Java（Maven/Gradle）

- Maven（`pom.xml`）：
  - `test`: `mvn test`
  - `build`: `mvn package`
- Gradle（`build.gradle*` / `gradlew`）：
  - `test`: `./gradlew test`
  - `build`: `./gradlew build`

---

## 7) .NET（`*.csproj` / `*.sln`）

优先：
- `test`: `dotnet test`（通常会先 build）
- `build`: `dotnet build`（仅当需要快速验证“能编译”或定位编译错误时单跑）

可选：
- `fmt`: `dotnet format --verify-no-changes`（若项目已配置且命令可用；否则跳过/unknown）

语言实现 Playbook（命中 .NET 时建议读取）：
- `references/stacks/dotnet.md`

推荐最小闭环（通用，兜底）：
- **快路径（最快验证）**：`dotnet test`
- **标准路径（更强信号）**：`dotnet build` → `dotnet test`（必要时再加 `dotnet format --verify-no-changes`）

---

## 8) Delphi / RAD Studio（`*.dproj` / `*.dpr`）

> 说明：Delphi 的“怎么编译/怎么测”高度依赖项目工程与本机安装（RAD Studio 版本、环境变量、平台 Win32/Win64）。因此：**优先使用项目自带脚本/CI 声明的命令**；没有明确入口时，不要瞎猜，先把缺口写为 `unknown` 并请用户给出可用命令。

探测线索（从强到弱）：
- 工程文件：`*.dproj`（最强）/ `*.dpr`
- 构建脚本：`build*.bat` / `compile*.bat` / `scripts/*.bat|*.ps1`
- CI：`.github/workflows/*`（是否包含 `msbuild` / `dcc32` / `dcc64`）

语言实现 Playbook（命中 Delphi 时建议读取）：
- `references/stacks/delphi.md`

常见可用入口（仅作候选，需用户/环境确认）：
- `build`: `msbuild <project>.dproj /t:Build /p:Config=Release /p:Platform=Win32`（或 Win64）
- `build`: `dcc32 -B <project>.dpr`（或 `dcc64`）

推荐最小闭环（Delphi 兜底）：
- **快路径**：只做 `build`（能编译就是最高信号）
- **测试**：如果仓库里有 DUnit/DUnitX 测试工程或脚本入口，则以该入口作为 `test`（否则 `unknown`）

---

## 9) C/C++（`CMakeLists.txt`）

优先（需根据实际 build 目录约定调整）：
- `build`: `cmake -S . -B build` + `cmake --build build`
- `test`: `ctest --test-dir build`

---

## 10) 多栈/Monorepo 处理

如果存在多个哨兵文件：
- 先按目录划分子项目（例如 `apps/*`、`packages/*`、`services/*`）
- 为每个子项目分别记录命令矩阵（写入 `project.md` 的“多工作区”）
- 执行任务时只在目标子项目中运行相应命令，避免误跑全仓

