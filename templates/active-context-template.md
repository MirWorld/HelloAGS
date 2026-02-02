# Active Context（模板）

> 文件：`helloagents/active_context.md`  
> 约束：≤120 行，高密度；每条 Public API 必须包含 `[SRC:CODE] path:line symbol`（symbol 必须是可检索键/无空格）；推断只能出现在“待确认/风险”区。  
> 协议：`references/active-context.md`

---

# Active Context (Updated: YYYY-MM-DD)

## Modules (Public Surface)

- **ModuleName** (`path/to/module/`)
  - Purpose: [一句话用途]
  - Public APIs:
    - [SRC:CODE] path/to/file.ext:123 symbol - [一句话语义/输入输出摘要]
    - [SRC:CODE] path/to/file.ext:456 symbol - [一句话语义/输入输出摘要]

## Contracts Index

- API Contract: `path/to/openapi.yaml` (if any)
- DB Contract: `path/to/schema.sql` (if any)
- Types/DTO: `path/to/types.*` (if any)
- Events: `path/to/events.*` (if any)

## Data Flow Guarantees

> 只写“已确认承诺”（必须可追溯到代码/用户原话/工具输出）

- [SRC:CODE] path/to/file.ext:123 symbol - [承诺：例如 token 写入位置/错误码语义/幂等策略]

## Known Gaps / Risks

- [SRC:TODO] [缺失信息/待接入项] - 影响: [...]
- [SRC:INFER][置信度: 低] [可能风险] - 验证方式: [...]

## Next

- Run: `...` Expect: ...
- Change: `path/to/file` Goal: ...
