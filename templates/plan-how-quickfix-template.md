# Quick Fix - 技术说明（how.md）

目录：`HAGWroks/plan/YYYYMMDDHHMM_quickfix_<slug>/how.md`

> 说明：Quick Fix 的 `how.md` 只写“边界/验证/回滚”的最小闭包；其余内容按需补充。

---

## 边界与依赖

- **Allow（允许修改）**：[…]
- **Deny（禁止修改）**：[…]

## 执行域声明（Allow/Deny）

按 `references/execution-guard.md`：
- NewFiles：否
- Refactor：否

## 参数变更微清单（如适用）

按 `references/quickfix-protocol.md` 第 3 节执行，并把结论写入 `task.md##上下文快照`。

## 验证计划（最小-最快-最高信号）

- 命令/脚本：`…`
- 预期：…

## 回滚方式

- 回滚动作：…
- 风险：…
