<!-- CONTRACT: terminology v1 -->

# 术语口径（Terminology）

目标：为维护者提供**单一来源（SSOT）**的命名与口径，避免同一概念在不同文档里“越写越像两件事”。

原则：
- “校验”只做**结构与契约**的确定性检查；不绑定自然语言措辞。
- “漂移”只用来描述**现象/风险**（例如行号漂移、命名漂移、范围漂移），不作为工具/脚本/动作名称。

---

## 1) 校验（Validation）

本仓库里的“校验”= 可重复执行、可自动化、能明确通过/失败的检查（脚本/命令）。

常见校验脚本：
- `scripts/validate-skill-pack.ps1`：本 Skill 包自检（结构/引用/契约块）
- `HAGSWorks/scripts/validate-plan-package.ps1`：方案包完整性校验（why/how/task + 关键章节；支持 `-Mode plan|exec`）
- `HAGSWorks/scripts/validate-active-context.ps1`：Active Context 校验（Public API 指针可续作）

---

## 2) 校验分层（`loose` / `strict`）

`validate-active-context.ps1` 的分层口径：

- **`loose`（默认，可续作校验）**
  - 目的：确保 active_context 的 `[SRC:CODE] path symbol` **可用**，避免“看起来很像真的但不可续作”。
  - 特点：不强制行号；即使行号填写后漂移，也倾向给出告警而不是阻断。

- **`strict`（可选增强，严格校验）**
  - 目的：在交付/发布前提供更强信号。
  - 特点：要求行号，并对“行号附近是否能命中 symbol”更敏感（更容易因行号漂移而失败）。

---

## 3) 隐式初始化（Implicit `~init`）

定义：当流程需要写入 `HAGSWorks/`（方案包/知识库/指针/脚本等），但目标项目尚未初始化时，**在首次写入前隐式执行一次 `~init`**（幂等补齐最小骨架），以支持“用户无感正常对话也能完成任务”。

触发条件（必须同时满足）：
- `write_scope != no_write`
- 即将写入 `HAGSWorks/`，但 `HAGSWorks/` 缺失或关键骨架不完整

边界（避免变重）：
- 只做存在性检查 + 缺失补齐 + 轻量校验（不扫描代码、不批量生成模块文档、不跑项目门禁）
- 若用户明确 `no_write`：不得隐式初始化，只能提示（见 `references/routing.md`）

单一来源：
- 路由与写入范围：`references/routing.md`
- `~init` 幂等初始化协议：`kb/SKILL.md`

---

## SSOT Map（单一来源速查）

目的：任何概念/协议/门禁只维护一个“单一来源”。需要改口径时，优先改 SSOT 文件，而不是到处补丁。

| 概念 | SSOT（单一来源文件） |
|---|---|
| 术语口径 | `references/terminology.md` |
| 协议公共 API 清单 | `references/contracts.md` |
| 路由与写入范围/Delta | `references/routing.md` |
| 断层恢复（Resume） | `references/resume-protocol.md` |
| 输出规范 | `templates/output-format.md` |
| 方案包生命周期 | `references/plan-lifecycle.md` |
| 上下文快照 | `references/context-snapshot.md` |
| Active Context 协议 | `references/active-context.md` |
| 技术栈探测与命令启发式 | `references/stack-detection.md` |
| 质量门禁 | `references/quality-gates.md` |
| Quick Fix 协议 | `references/quickfix-protocol.md` |
| Triage Pass 协议 | `references/triage-pass.md` |
| 方案包完整性校验脚本 | `templates/validate-plan-package.ps1` |
| Active Context 校验脚本 | `templates/validate-active-context.ps1` |
