# 子代理调度示例（Scout + Reviewer）

> 目的：演示“子代理只读侦察/独立审查”如何产出可合并的结构化结果，并由主控写回 `task.md##上下文快照`，避免污染主任务方向。

---

## 场景

用户需求：重构一个跨 4 层（UI/API/Service/DB）的下单流程，要求向后兼容旧客户端，且最近出现了重复扣库存的线上问题。

命中触发器：
- 跨层（≥3 层）
- 需要独立 Review（线上事故风险）

参考：
- `references/checklist-triggers.md`
- `references/subagent-orchestration.md`

---

## 1) Scout（只读侦察）输出示例

### 结论（≤5 条）
- TL;DR: 下单入口在 `src/api/orders`，库存扣减在 `src/domain/inventory`，但存在两个调用路径可能导致重复扣减；兼容字段映射在 `src/api/dto`。

### 证据（必须）
- [SRC:CODE] src/api/orders/controller.ts:88 CreateOrderHandler - HTTP 下单入口
- [SRC:CODE] src/domain/inventory/service.ts:142 ReserveStock - 预留库存逻辑
- [SRC:CODE] src/domain/order/service.ts:201 CreateOrder - 创建订单并触发库存预留

### 风险 / 不确定点
- [SRC:INFER][置信度: 中] 可能存在“重试导致幂等缺失”的重复扣减路径（验证：查 `Idempotency-Key` 是否被消费）
- [SRC:TODO] 缺失信息: 线上重复扣减的最小复现日志/trace id（影响：无法确认是重试还是并发）

### 主控下一步唯一动作
- 下一步唯一动作: 主控先在方案包 `how.md` 写清“幂等承诺/兼容策略/受影响消费者清单”，再进入实现。

---

## 2) Reviewer（独立审查）输出示例

### 结论（≤5 条）
- TL;DR: 当前方案如果直接引入新接口/新字段但不做兼容层，会破坏旧客户端；需要明确“库存预留 vs 支付成功扣减”的一致性承诺与回滚策略。

### 证据（必须）
- [SRC:CODE] src/api/dto/order.ts:33 LegacyOrderDTO - 旧字段仍被客户端使用
- [SRC:CODE] src/domain/inventory/service.ts:142 ReserveStock - 关键承诺点（需定义幂等/重试语义）

### 风险 / 不确定点
- [SRC:INFER][置信度: 低] 现有实现可能没有事务边界（验证：确认 DB 操作是否在同一事务/是否有 outbox）

### 主控下一步唯一动作
- 下一步唯一动作: 主控在 `task.md##上下文快照` 记录“幂等/兼容/一致性承诺”三项决策，并给出唯一的验证动作（跑哪条测试/脚本/复现步骤）。

---

## 3) 主控落盘（写回 task.md 的示例片段）

把 Scout/Reviewer 的“证据与结论”写入 `task.md##上下文快照`：
- 事实区只写带 `[SRC:CODE]` 的内容
- 推断进风险区（`[SRC:INFER]`）并给出验证方式
- 明确“下一步唯一动作”
