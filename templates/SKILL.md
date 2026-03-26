---
name: templates
description: 文档/脚本模板集合；创建 Wiki/方案包/校验脚本时读取；模板正文以 `templates/` 为唯一来源，避免多处维护漂移
---

# 文档模板集合（导航）

本文件只提供**模板导航与使用说明**；模板正文以 `templates/` 为唯一来源，避免多处维护导致漂移。

## 使用方式（渐进式加载）

1. 先 `rg`/目录浏览定位你需要的模板文件
2. 只打开该模板文件（不要一次性加载所有模板）
3. 将 `[...]` 替换为实际内容；未知项写 `unknown`，不要凭空猜测
4. 遵循 G1/G5：自然语言简体中文；写入保持仓库既有编码（默认 UTF-8）

补充：
- `HAGSWorks/` 初始化骨架（目录 + 目标文件映射）以 `templates/workspace-bootstrap-manifest.json` 为唯一来源
- 新增/删除初始化文件时，优先修改该 manifest；本导航不再逐项重复维护 `~init` 的所有目标文件映射

## 模板索引

| 模板文件 | 目标文件（建议） | 用途 |
|---|---|---|
| `templates/plan-why-template.md` | `HAGSWorks/plan/.../why.md` | 变更提案与对齐摘要 |
| `templates/plan-how-template.md` | `HAGSWorks/plan/.../how.md` | 技术设计/ADR/质量门禁 |
| `templates/plan-task-template.md` | `HAGSWorks/plan/.../task.md` | 任务清单（含 Review 记录） |
| `templates/plan-why-quickfix-template.md` | `HAGSWorks/plan/.../why.md` | Quick Fix 极简对齐摘要（仍为完整方案包） |
| `templates/plan-how-quickfix-template.md` | `HAGSWorks/plan/.../how.md` | Quick Fix 极简技术说明（边界/验证/回滚） |
| `templates/plan-task-quickfix-template.md` | `HAGSWorks/plan/.../task.md` | Quick Fix 极简任务清单（含上下文快照/Review） |
| `templates/workspace-bootstrap-manifest.json` | `HAGSWorks/**` | `~init` / 隐式初始化最小骨架真值清单（目录 + 目标文件映射） |
| `templates/wiki-module-template.md` | `HAGSWorks/wiki/modules/<module>.md` | 模块文档（按需生成，不在最小骨架中默认批量创建） |
| `templates/output-format.md` | （输出规范单一来源） | 统一输出格式（G6.1~G6.4） |
| `templates/hooks/hooks.json` | `.codex/hooks.json`（可选） | Codex hooks 接线模板（可选增强） |
| `templates/hooks/config.toml.snippet` | `.codex/config.toml` 片段（可选） | 启用 Codex hooks 的配置片段（可选增强） |
| `scripts/validate-skill-pack-smoke.ps1` | 仓库维护命令 | 最小行为级冒烟验证（bootstrap + hooks fixture + feature-removal wait） |

## 约束提醒

- 阶段规则（`analyze/`、`design/`、`develop/`、`kb/`）应**直接引用具体模板文件**，不要依赖本导航文件承载模板正文。
