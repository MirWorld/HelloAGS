# HelloAGENTS（Codex CLI Skill）

<p align="center">
  <a href="https://github.com/MirWorld/HelloAGS/actions/workflows/validate-skill-pack.yml"><img src="https://github.com/MirWorld/HelloAGS/actions/workflows/validate-skill-pack.yml/badge.svg" alt="validate-skill-pack" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="License Apache-2.0" /></a>
  <a href="LICENSE-CC-BY-4.0"><img src="https://img.shields.io/badge/docs-CC%20BY%204.0-blue.svg" alt="Docs CC BY 4.0" /></a>
</p>

把“用户自然语言需求”转成“可对齐、可执行、可验证、可追溯”的工程交付流程与产物：意图建模 → 方案包（why/how/task）→ 开发实施与质量门禁 → 知识库同步 → 历史归档。

这不是一个业务应用；这是一个给 Codex CLI 使用的 Skill 包（规则、模板与校验脚本），用于把一次次对话变成可验收的工程交付。

## Features（你会得到什么）

- 需求对齐：6 槽 Intent Model + 假设账本 + `why.md##对齐摘要`（防跑偏/防返工）
- 续作能力：中期落盘（上下文快照）+ Active Context（可验证接口注册表）
- 质量闭环：失败升级协议 + 两段式 Review（规格一致性 → 结构与质量）
- 小改动不翻车：Quick Fix 快路径协议（改一个参数也先取证 + 最小验证）

## Quick Start（在你的项目里用起来）

1. 安装：把本仓库放入 Codex CLI 的 skills 搜索路径（例如 `~/.codex/skills/helloagents/`）
2. 初始化：在你的项目根目录对话中输入 `~init`（生成 `HAGWroks/` 工作区/知识库骨架）
3. 日常使用：直接提需求即可（默认 `~auto`；也可显式用 `~plan` / `~exec`）

## 工作流（核心概念）

在目标项目中，Skill 会把一次需求落成三份可追溯文件（统称“方案包”）：

- `why.md`：对齐摘要与成功标准（SSOT：意图真值）
- `how.md`：技术设计、边界、验证与回滚
- `task.md`：可执行任务清单（含上下文快照与 Review 记录）

并把长期记忆落盘到 `HAGWroks/`（建议纳入版本库）：

```text
HAGWroks/
├── active_context.md              # Active Context：可验证接口注册表（≤120行）
├── project.md                     # 项目能力画像/协作偏好（unknown 允许）
├── wiki/                          # 项目知识库
├── plan/YYYYMMDDHHMM_<feature>/   # 方案包（进行中）
└── history/YYYY-MM/...            # 方案包归档（已完成）
```

关于“真值分层”：代码事实 + 可复现验证证据 + `why.md##对齐摘要` 为 SSOT；与派生文档（wiki/active_context/task 快照）冲突时，以 SSOT 为准并回填修正文档。

## 仓库结构（本仓库）

- `SKILL.md`：总入口（硬约束、路由、核心协议）
- `analyze/`、`design/`、`develop/`、`kb/`：分阶段规则
- `templates/`：方案包/知识库模板与校验脚本模板
- `references/`：协议、门禁与安全准则（单一来源）
- `scripts/`：本仓库自检脚本
- `examples/`：使用示例

## 验证与维护

- 本仓库自检（CI 同款）：`pwsh -NoProfile -File ./scripts/validate-skill-pack.ps1`
- 目标项目 Active Context 校验：`pwsh -NoProfile -File ./HAGWroks/scripts/validate-active-context.ps1`
- 目标项目方案包完整性校验：`pwsh -NoProfile -File ./HAGWroks/scripts/validate-plan-package.ps1`

说明：本仓库脚本与文档包含大量 UTF-8 中文内容，建议使用 PowerShell 7（`pwsh`）执行校验脚本。

## Acknowledgments

- https://github.com/nightwhite/helloagents
- https://github.com/hellowind777/helloagents

## License

双许可：代码 Apache-2.0 / 文档 CC BY 4.0。详见 `LICENSE`、`LICENSE-CC-BY-4.0`、`LICENSE-SUMMARY.md` 与 `NOTICE`。
