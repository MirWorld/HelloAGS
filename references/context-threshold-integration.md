# Context Threshold Integration（Monitor ↔ helloagents）

## 1. 目标

在接近 Codex 自动压缩阈值前，由外部消费者先读取当前上下文占用，再把“恢复当前方案包所需的最小检查点”落回磁盘，避免压缩后：

- 丢失当前任务进度
- 重新打开已完成任务
- 因聊天记忆缺口而跑偏

本能力的定位是：

- **外部增强**，不是 Codex hooks engine 原生强制门
- **恢复前置证据**，不是替代 `model_event`
- **best-effort 自动落盘**，不是没有磁盘事实时强行猜状态

---

## 2. 当前结论

按当前代码状态，可以进入**联调可用**阶段。

含义：

- Monitor 侧已经能在 `pre_submit / post_turn / compact_boundary` 三个时机请求 `get_context_usage`
- Monitor 侧已经能把接近阈值的结构化 payload 发送给 helloagents 的 PowerShell 脚本
- helloagents 侧已经能把该 payload append 到当前方案包 `task.md##上下文快照`
- resume 协议已经认识 `threshold_event: near_autocompact`

但它还不是“完全验收”的状态，因为：

- 当前 `CodexMonitor` 源码快照缺少完整仓库级构建入口，未完成一次正式构建验证
- 还需要至少一次**真机端到端联调**，确认实际运行中的 Monitor 能成功调用脚本并写回目标项目

---

## 3. 对接前提

要让这条链路真正生效，必须同时满足：

1. Monitor 运行的是已包含阈值守卫改动的版本
2. 当前项目使用 helloagents，并存在有效方案包指针：
   - `HAGSWorks/plan/_current.md`
3. 当前方案包存在：
   - `task.md`
   - `## 上下文快照`
4. 机器可执行 PowerShell：
   - `pwsh`
5. 阈值脚本路径可被找到：
   - 环境变量 `HELLOAGENTS_CONTEXT_THRESHOLD_HOOK`
   - 或默认路径 `~/.codex/skills/helloagents/scripts/hooks/helloagents-context-threshold.ps1`

若上述任一条件不满足，策略应为：

- **SKIP**
- 不阻断正常消息发送
- 不冒充“已落盘”

---

## 4. 数据契约

Monitor 传给 helloagents 的 payload 最小字段：

- `source`
- `project_root`
- `used_tokens`
- `auto_compact_threshold`
- `remaining_to_compact`

可选字段：

- `threshold_severity`
- `compact_pre_tokens`
- `model`
- `percentage`
- `timestamp`
- `session_id`

当前约定的 `source`：

- `pre_submit`
- `post_turn`
- `compact_boundary`

---

## 5. Monitor → Skill 映射

### 5.1 Monitor 负责什么

- 读取上下文占用
- 判断是否接近自动压缩阈值
- 只在命中阈值时调用脚本
- 对短时间内的重复信号先做一层去重
- 不因为脚本失败而打爆主消息发送链路

### 5.2 helloagents 负责什么

- 解析结构化 payload
- 定位当前激活方案包
- 把 `near_autocompact` 检查点 append 到 `task.md##上下文快照`
- 同时写入：
  - `repo_state`
  - `下一步唯一动作`
- 对近重复检查点再做第二层去重

### 5.3 resume 协议负责什么

- 恢复时优先消费磁盘中的 `threshold_event: near_autocompact`
- 以其后的 `repo_state + 下一步唯一动作` 作为压缩前最后检查点
- 不依赖聊天记忆去猜“做到哪了”

---

## 6. 当前文件对应关系

Monitor 侧：

- `src/services/context/contextThresholdGuard.ts`
- `src/utils/analyzeContext.ts`
- `src/entrypoints/sdk/controlSchemas.ts`
- `src/remote/SessionsWebSocket.ts`
- `src/remote/RemoteSessionManager.ts`
- `src/server/directConnectManager.ts`

helloagents 侧：

- `scripts/hooks/helloagents-context-threshold.ps1`
- `references/context-snapshot.md`
- `references/contracts.md`
- `references/resume-protocol.md`
- `references/hook-simulation.md`
- `scripts/validate-skill-pack.ps1`
- `scripts/validate-skill-pack-smoke.ps1`

---

## 7. 去重策略

当前是两层去重：

### 7.1 Monitor 侧去重

用于减少高频重复调用脚本：

- 同一 `source`
- 短时间窗口内
- `remaining_to_compact` 变化很小

### 7.2 helloagents 侧去重

用于防止真正落盘重复污染 `task.md`：

- 同一 `threshold_source`
- `remaining_to_compact` 差值小于阈值
- 时间戳接近

原则：

- Monitor 侧去重是**降噪**
- Skill 侧去重是**最后防线**

---

## 8. 恢复语义

当 `task.md##上下文快照` 中存在：

- `threshold_event: near_autocompact`

恢复时应这样理解：

1. 这说明在压缩真正发生前，外部消费者已经捕获到“接近阈值”
2. 其后的 `repo_state` 是压缩前磁盘检查点的最小仓库事实
3. 其后的 `下一步唯一动作` 是恢复入口，而不是重新规划整包
4. 若当前任务状态已全部完成且无 Pending，仍应按 No-Redo 规则停止，而不是重新开工

---

## 9. 最小联调脚本

建议按以下顺序做真机联调：

1. 在目标项目里创建并激活一个方案包
2. 确认 `task.md` 含 `## 上下文快照`
3. 启动包含阈值守卫改动的 Monitor
4. 触发一次接近阈值的会话
5. 检查当前 `task.md` 是否新增：
   - `threshold_event: near_autocompact`
   - `threshold_source: ...`
   - `remaining_to_compact: ...`
   - `repo_state: ...`
   - `下一步唯一动作: ...`
6. 再触发一次近重复事件，确认不会重复 append

---

## 10. 边界

这套方案解决的是：

- “压缩前先落盘恢复检查点”

它不直接解决：

- CLI 内部压缩阈值 UI 展示
- Codex 原生 hook 强制门
- 没有方案包时的全局恢复
- 没有 `_current.md` 指针时的自动推断

如果以后要从“联调可用”升级到“强约束可依赖”，下一步应该是：

- 给 Monitor 版本做一次真机构建与实际运行验证
- 把当前 payload/去重/落盘结果固化成更明确的端到端验收脚本
