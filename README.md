# HelloAGENTS（Codex CLI Skill）

<p align="center">
  <a href="https://github.com/MirWorld/HelloAGS/actions/workflows/validate-skill-pack.yml"><img src="https://github.com/MirWorld/HelloAGS/actions/workflows/validate-skill-pack.yml/badge.svg" alt="validate-skill-pack" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="License Apache-2.0" /></a>
  <a href="LICENSE-CC-BY-4.0"><img src="https://img.shields.io/badge/docs-CC%20BY%204.0-blue.svg" alt="Docs CC BY 4.0" /></a>
</p>

把“用户自然语言需求”转成“可对齐、可执行、可验证、可追溯”的工程交付流程与产物：意图建模 → 方案包（why/how/task）→ 开发实施与质量门禁 → 知识库同步 → 历史归档。

这不是一个业务应用；这是一个给 Codex CLI 使用的 Skill 包（规则、模板与校验脚本），用于把一次次对话变成可验收的工程交付。

## 一分钟上手（复制即用）

1. **安装**：把本仓库放到 Codex CLI 的 skills 搜索路径（例如 `~/.codex/skills/helloagents/`）
2. **初始化**：在你的目标项目根目录对话中输入 `~init`（生成 `HAGSWorks/` 工作区骨架）
   - 若你之前使用过旧目录名（历史拼写错误）`HAGWroks/`：执行 `~init` 会自动迁移为 `HAGSWorks/`
3. **直接开干**：在目标项目里直接提需求即可（默认 `~auto`；只想出方案用 `~plan`）
4. （维护者可选）**自检**：修改本 Skill 后先跑 `pwsh -NoProfile -File ./scripts/validate-skill-pack.ps1`

## 命令速查（只记这四个）

- `~init`：初始化/补齐 `HAGSWorks/`（可反复执行，幂等）
- `~plan`：只做对齐与方案（会产出 why/how/task），不进入改代码/跑门禁
- `~exec`：执行已有方案包（按 task 清单改代码、验证、归档）
- `~auto`：一口气跑完整链路（对齐 → 方案 → 执行）

## 常见场景怎么选

- 我只想问清楚/讨论一下（不落盘、不改代码）→ 直接提问，并明确“只问不改”
- 我想先要方案，不要实现 → `~plan`
- 我希望你直接改好并验证 → `~auto`（或：先 `~plan` 再 `~exec`）

## 写入范围（常见表述的意思）

- 你说“**不写文件/不要落盘**”→ 我不会创建/修改任何文件（包括 `HAGSWorks/`）
- 你说“**不要改业务代码，但可以写方案**”→ 只写 `HAGSWorks/`（方案包/知识库），不碰业务代码
- 你说“**直接改好**”→ 可以修改业务代码与相关配置（仍遵循方案包与验证约束）

## 中途纠偏（Enter / Tab）

当 Codex 正在执行时，你可以随时补一句“纠偏/加约束”来让它立刻收口范围：

- **按 Enter**：立即发送这条纠偏（立刻生效）
- **按 Tab**：把这条纠偏排队，等当前步骤结束后再处理

常用纠偏句式（可直接复制）：
- `新增约束：不要改 DB / 不要新增文件`
- `非目标：不要顺手重构，只改最小必要处`
- `先停一下：列出你准备改的文件，我确认后再继续`

## Features（你会得到什么）

- 需求对齐：6 槽 Intent Model + 假设账本 + `why.md##对齐摘要`（防跑偏/防返工）
- 续作能力：中期落盘（上下文快照）+ Active Context（可验证接口注册表）
- 质量闭环：失败升级协议 + 两段式 Review（规格一致性 → 结构与质量）
- 小改动不翻车：Quick Fix 快路径协议（改一个参数也先取证 + 最小验证）

## 工作流（核心概念）

在目标项目中，Skill 会把一次需求落成三份可追溯文件（统称“方案包”）：

- `why.md`：对齐摘要与成功标准（SSOT：意图真值）
- `how.md`：技术设计、边界、验证与回滚
- `task.md`：可执行任务清单（含上下文快照与 Review 记录）

并把长期记忆落盘到 `HAGSWorks/`（建议纳入版本库）：

```text
HAGSWorks/
├── active_context.md              # Active Context：可验证接口注册表（≤120行）
├── project.md                     # 项目能力画像/协作偏好（unknown 允许）
├── wiki/                          # 项目知识库
├── plan/_current.md               # 当前方案包指针（自动维护；用于断层恢复/续作选包）
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
- Windows PowerShell 5.1 兼容入口：`powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/validate-skill-pack-ps51.ps1`
- 目标项目 Active Context 校验：`pwsh -NoProfile -File ./HAGSWorks/scripts/validate-active-context.ps1`
- 目标项目方案包完整性校验：`pwsh -NoProfile -File ./HAGSWorks/scripts/validate-plan-package.ps1`

说明：本仓库脚本与文档包含大量 UTF-8 中文内容；PowerShell 7（`pwsh`）下可直接运行 `./scripts/validate-skill-pack.ps1`，Windows PowerShell 5.1 请使用上面的兼容入口脚本。

## Acknowledgments

- https://github.com/nightwhite/helloagents
- https://github.com/hellowind777/helloagents

## License

双许可：代码 Apache-2.0 / 文档 CC BY 4.0。详见 `LICENSE`、`LICENSE-CC-BY-4.0`、`LICENSE-SUMMARY.md` 与 `NOTICE`。

