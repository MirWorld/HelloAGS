# 变更历史索引

本文件记录所有已完成变更的索引，便于追溯和查询。

---

## 索引

| 时间戳 | 功能名称 | 类型 | 状态 | 方案包路径 |
|--------|----------|------|------|------------|
| YYYYMMDDHHMM | [功能标识] | [功能/修复/重构] | ✅已完成/[-]未执行 | [链接] |

---

## 按月归档

### YYYY-MM

- [YYYYMMDDHHMM_feature](YYYY-MM/YYYYMMDDHHMM_feature/) - [一句话功能描述]

---

## 轻量检索元数据（按需）

> 目标：不用向量库也能快速回忆历史任务。只写高价值事实；没有就留空，不要复制方案包正文。

### YYYYMMDDHHMM_feature

- `tags`: [hooks, resume, validation]
- `touched_files`: [`path/to/reference.md`, `path/to/script.ps1`]
- `decisions`: [关键决策 1；关键决策 2]
- `verify`: `命令1（结果摘要）`; `命令2`
- `signals`: [near_autocompact, response_incomplete]

### 字段拆分规则

- `tags` / `touched_files`: 按英文逗号 `,` 拆分；每项 trim；去除外层方括号、反引号和引号。
- `decisions`: 优先按中文分号 `；` 拆分；若没有中文分号，兼容英文分号 `;`；每项 trim；去除外层方括号、反引号和引号。
- `verify`: 仅按英文分号 `;` 拆分；每项 trim；去除外层反引号和引号。
- `verify` 每项若末尾存在括号注释 `(...)` 或 `（...）`，括号前进入 `command`，括号内容进入 `result_summary`；只识别末尾注释，不解析命令中间的括号。
