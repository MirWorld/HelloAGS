# Active Context（模板）

> 文件：`HAGSWorks/active_context.md`  
> 约束：≤120 行，高密度；每条 Public API 必须包含 `[SRC:CODE] path:line symbol`（symbol 必须是可检索键/无空格）；推断只能出现在“待确认/风险”区。  
> 协议：`references/active-context.md`

---

# Active Context (Updated: YYYY-MM-DD)

## Modules (Public Surface)

- **ModuleName** (`path/to/module/`)
  - Purpose: [一句话用途]
  - Public APIs:
    - [在这里列出 Public API 条目]

## Contracts Index

- API Contract: `path/to/openapi.yaml` (if any)
- DB Contract: `path/to/schema.sql` (if any)
- Types/DTO: `path/to/types.*` (if any)
- Events: `path/to/events.*` (if any)

## Data Flow Guarantees

> 只写“已确认承诺”（必须可追溯到代码/用户原话/工具输出）

- [在这里列出已确认承诺条目]

## Known Gaps / Risks

- [SRC:TODO] [缺失信息/待接入项] - 影响: [...]
- [SRC:INFER][置信度: 低] [可能风险] - 验证方式: [...]

## Next

- Run: `...` Expect: ...
- Change: `path/to/file` Goal: ...

