# Quick Fix 示例（改一个参数）

## 用户输入示例
> 把登录接口的超时从 3 秒改成 10 秒（不涉及数据库、也不需要重构）

## 期望路由
- 意图：改动型
- 范围：微（≤2文件≤30行）
- 风险：无 EHRB
- 模式：Quick Fix（微调）

## 关键动作（快路径）
1. 按 `references/quickfix-protocol.md` 创建最小完整方案包：
   - `HAGWroks/plan/YYYYMMDDHHMM_quickfix_auth-timeout/why.md`
   - `HAGWroks/plan/YYYYMMDDHHMM_quickfix_auth-timeout/how.md`
   - `HAGWroks/plan/YYYYMMDDHHMM_quickfix_auth-timeout/task.md`
2. 执行“改一个参数微清单”（真值源/单位边界/消费者/文档/最小验证），把结论写入 `task.md##上下文快照`
3. 写执行域声明（Allow/Deny/NewFiles/Refactor=否），并把“下一步唯一动作”落盘
4. 只改必要代码 + 运行最小验证
5. 迁移方案包到 `HAGWroks/history/YYYY-MM/...`

## 输出示例（节选）
`task.md##上下文快照` 至少包含：
- Workset（改哪些文件 + 意图）
- 下一步唯一动作（1条可执行）
- 对超时单位（s/ms）的证据指针 `[SRC:CODE]`
