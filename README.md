# HelloAGENTS（Codex CLI Skill）

把“用户自然语言需求”转成“可对齐、可执行、可验证、可追溯”的工程交付：意图建模 → 方案包（why/how/task）→ 开发实施与质量门禁 → 知识库同步 → 历史归档。

## 你会得到什么
- **更强的需求理解**：6 槽意图模型 + 假设账本 + 对齐摘要（防跑偏/防返工）
- **更强的抗打断续作**：触发式“中期落盘”（上下文快照）+ 可验证接口注册表（Active Context）
- **更稳的交付质量**：失败升级协议 + 两段式 Review（规格一致性 → 结构与质量）
- **更稳的“小改动”**：Quick Fix 快路径协议（改一个参数也先取证+最小验证，避免暗坑）

## 快速开始
1. 安装 Skill：把本仓库放入 Codex CLI 的 skills 搜索路径（例如 `~/.codex/skills/helloagents/`）
2. 在你的项目根目录执行一次：输入 `~init`（生成项目的 `helloagents/` 工作区/知识库）
3. 正常提需求即可：默认 `~auto`（需要时可显式用 `~plan` / `~exec`）

## 目录结构（本仓库）
- `SKILL.md`：总入口（硬约束、路由、核心协议）
- `analyze/`、`design/`、`develop/`、`kb/`：分阶段规则
- `references/`：协议/门禁/安全等参考
- `templates/`：方案包/知识库模板
- `examples/`：使用示例

## 关键产物（在具体项目中）
- `helloagents/plan/`：方案包（why/how/task）
- `helloagents/history/`：已完成方案包归档
- `helloagents/active_context.md`：可验证接口注册表（每条 Public API 必须带 `[SRC:CODE] path:line symbol`）
- `helloagents/wiki/`：项目知识库主页与模块文档
> 建议把项目内的 `helloagents/` 提交到版本库（它是团队/项目的长期记忆落盘处），并遵循“真值分层”：代码事实 + 可复现验证证据 + `why.md##对齐摘要` 为 SSOT（真值）；与之冲突时以真值为准并回填修正文档。

## 验证（推荐）
- Active Context 漂移校验（在具体项目中）：`./helloagents/scripts/validate-active-context.ps1`
  - 如脚本缺失：可从本仓库 `templates/validate-active-context.ps1` 生成到项目的 `helloagents/scripts/validate-active-context.ps1`

## 维护（本仓库）
- Skill 包自检（检查引用/模板基础结构）：`./scripts/validate-skill-pack.ps1`

## 致谢（从其修改而来）
- 白佬（nightwhite）：https://github.com/nightwhite/helloagents
- H佬（Hellowind）：https://github.com/hellowind777/helloagents

## 许可
本仓库采用双许可（代码 Apache-2.0 / 文档 CC BY 4.0）：详见 `LICENSE`、`LICENSE-CC-BY-4.0`、`LICENSE-SUMMARY.md` 与 `NOTICE`。
