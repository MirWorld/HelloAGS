<!-- CONTRACT: triage-pass v1 -->

# 高信号取证（Triage Pass）

目标：在开始写/改代码前，用一次“高信号取证”把关键事实与缺口收敛到可执行状态，减少空转、跑偏与上下文膨胀。

原则：
- 只输出**可验证事实**与明确缺口；推断必须隔离（`[SRC:INFER]`）
- 每条事实必须带 `[SRC:CODE] path symbol` 指针（行号可选）
- 取证完成后必须把结论写入 `task.md##上下文快照`（否则禁止进入实现）

---

## 1) 何时必须做

命中任一即必须做一次取证（并落盘）：
- 开发实施阶段第一次改代码前（默认必做一次）
- 涉及跨模块/跨层（≥3 层）或契约变化（API/Schema/DTO）
- 信息缺口大：无法明确“入口/调用链/副作用点/消费者”
- 连续失败 ≥2，需要从证据侧收敛问题

---

## 2) 取证输出（必须包含）

将以下内容以结构化条目写入 `task.md##上下文快照` 的“已确认事实/待确认/下一步唯一动作”：

### 2.1 入口与调用链（事实）
- [SRC:CODE] … 入口（UI route / API handler / job / event）
- [SRC:CODE] … 关键调用链（最多 5 跳，指向真实符号）

### 2.2 契约载体（事实）
- [SRC:CODE] … 契约/协议所在（DTO/Schema/Response shape/Error code）
- [SRC:CODE] … 关键不变量/语义承诺（幂等/鉴权/兼容/错误语义）

### 2.3 副作用点与消费者（事实）
- [SRC:CODE] … 写入点/外部 IO（DB/cache/queue/network）
- [SRC:CODE] … 主要消费者/调用点（至少列出 2 个）

### 2.4 缺口（只能写这里）
- [SRC:TODO] 缺失信息: …（影响: …）
- [SRC:INFER][置信度: 中] 推断: …（验证方式: …）

### 2.5 最小验证动作（verify_min，必须）

至少给出 1 条“最小-最快-最高信号”的验证动作，用于**立刻证明方向没跑偏**（细则见 `references/quality-gates.md` 的“最小-最快-最高信号”）：
- 命令/脚本/测试：`...`
- 预期：...

同时要求：
- 将同一条 `verify_min: ...` 写入方案包的 `how.md`（SSOT，推荐放在 `## 变更请求（Change/Verify/Don't）` 的 Verify 行），避免续作时读到两套验证命令
- `task.md##上下文快照` 负责记录“当前 verify_min 选择理由/执行证据/失败收敛决策”，不作为 verify_min 的唯一来源

若当前无法确定可运行的验证动作：允许写 `verify_min: unknown`，但必须同时写清“下一步如何获得 verify_min”（例如从 CI/README/package scripts/现有测试入口中取证）。  
注意：这只允许停留在规划域；进入执行域（改代码/交付）前必须把 `verify_min` 落成可运行命令（可用 `validate-plan-package.ps1 -Mode exec` 作为硬闸）。

### 2.6 下一步唯一动作（必须只有 1 条）
- 下一步唯一动作: `...` 预期: ...

---

## 3) 无多代理时的推荐做法（可选但高收益）

如环境不支持多代理：用 2–3 次独立 Pass（Scout/Reviewer/跨层与复用）模拟并行取证；细则见 `references/subagent-orchestration.md` 的 “无多代理时的替代方案”。
