# Light Iteration 示例（小范围迭代）

## 用户输入示例
> 为登录、注册和密码重置功能添加统一的错误处理（预计改 3-5 个文件，不涉及数据库变更）

## 期望路由
- 意图：改动型
- 范围：小（3–5文件）
- 风险：无 EHRB
- 模式：Light Iteration

## 关键动作
1. 创建最小完整方案包：`HAGWroks/plan/YYYYMMDDHHMM_auth-errors/`（包含 `why.md` + `how.md` + `task.md`）
2. `why.md` 写对齐摘要（目标/成功标准/非目标/约束）；`how.md` 写边界/复用/验证门禁；`task.md` 写可执行任务 + `## 上下文快照` 检查点
3. 按任务执行改动，并把每条任务更新为 `[√]/[X]/[-]`
4. 同步知识库（必要时先 `~init`）
5. 迁移方案包到 `HAGWroks/history/YYYY-MM/...`

## task.md 片段示例
```markdown
# 任务清单: auth-errors

## 1. 统一错误模型
- [ ] 1.1 在 `src/auth/errors.ts` 定义标准错误类型（code/message/cause）

## 2. 登录/注册/重置接入
- [ ] 2.1 在 `src/auth/login.ts` 替换散落的 throw/return 为标准错误
- [ ] 2.2 在 `src/auth/signup.ts` 同上
- [ ] 2.3 在 `src/auth/reset.ts` 同上

## 3. 测试
- [ ] 3.1 运行现有测试或补充一条集成测试覆盖 3 个入口
```

## 输出示例
```
✅【HelloAGENTS】- 轻量迭代完成

- ✅ 执行结果: 任务 5/5 完成
- 📦 方案包: 已迁移至 HAGWroks/history/2025-12/202512261830_auth-errors/
- 📚 知识库: 已更新

────
📁 变更:
  - src/auth/errors.ts
  - src/auth/login.ts
  - src/auth/signup.ts
  - src/auth/reset.ts
  - HAGWroks/wiki/modules/auth.md
  - HAGWroks/history/index.md

🔄 下一步: 请验证 3 个入口的错误提示是否一致
```
