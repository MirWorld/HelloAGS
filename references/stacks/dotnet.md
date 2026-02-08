# .NET / C# Playbook（推荐默认 + 少量硬禁止）

目标：当项目被判定为 .NET（`*.sln` / `*.csproj`）时，提供一套**默认安全**、**默认可测试**、**默认可闭环**的实现习惯。  
原则：项目既有约定/CI/脚本优先；本 Playbook 仅作为兜底与收敛默认值。

---

## 硬禁止（高风险，默认不允许）

1. **禁用 `.Result` / `.Wait()` 等阻塞等待 Task**  
   - 容易死锁/吞异常/拖慢线程池；应改为 `await`，并尽量支持 `CancellationToken`。
2. **禁用 `async void`（除事件处理器外）**  
   - 非事件处理器使用 `async Task`，保证可等待、可测试、可收敛异常。
3. **禁用空 `catch {}` 吞异常**  
   - 至少记录/封装后抛出；在边界层做统一错误映射。

---

## 推荐默认（更灵活；可被项目现状覆盖）

### 可空与 API 设计
- 默认开启并遵循 Nullable Reference Types（NRT）；新代码不引入新的可空告警。
- 对外异步 API 默认接收 `CancellationToken`（尤其是 IO/网络/长计算）。

### 资源与生命周期
- `IDisposable/IAsyncDisposable` 默认用 `using` / `await using` 收口。
- 避免把 `HttpClient` 当短生命周期对象频繁 new；优先复用或交给 DI 管理（按项目现状）。

### 日志
- 有 DI/Host 的项目：默认用 `ILogger<T>`；避免到处 `Console.WriteLine`（除非 CLI 工具且已约定）。

### 测试
- 测试框架默认“随项目现状”；若新建测试且无约束，默认 `xUnit`。
- 测试命名与结构建议固定为 Arrange/Act/Assert，优先覆盖成功标准路径。

---

## 闭环（最小验证动作）

优先使用项目声明的命令矩阵；缺失时按以下兜底闭环：

- **快路径（最快信号）**：`dotnet test`
- **标准路径（更强信号）**：`dotnet build` → `dotnet test`
- **格式（可选）**：若项目已配置且命令可用：`dotnet format --verify-no-changes`

