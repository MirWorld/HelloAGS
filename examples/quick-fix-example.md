# Quick Fix 示例（微改动）

## 用户输入示例
> 修复 `src/utils/helper.ts` 第42行的拼写错误：`respose` 应该是 `response`

## 期望路由
- 意图：改动型
- 范围：微（≤2文件≤30行）
- 风险：无 EHRB
- 模式：Quick Fix（微调；仍创建最小完整方案包）

## 关键动作
1. 创建最小完整方案包（why/how/task）并声明执行域（Allow/Deny/回滚/最小验证）
2. 仅修改目标文件（避免无关重构）
3. 如存在 `HAGWroks/wiki/modules/utils.md`：补充/更新对应规范或变更历史
4. 如知识库缺失：提示建议执行 `~init`（不在本次任务中强制创建）

## 输出示例（使用 templates/output-format.md）
```
✅【HelloAGENTS】- 微调模式完成

- ✅ 改动: 修复拼写错误 respose → response
- 📁 涉及文件: src/utils/helper.ts
- 📚 知识库: ⚠️建议执行 ~init（未检测到 HAGWroks/）

────
📁 变更:
  - src/utils/helper.ts

🔄 下一步: 请验证改动效果
```
