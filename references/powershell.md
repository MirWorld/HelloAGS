# Windows PowerShell 使用约束（参考）

目标：在 Windows/PowerShell 下减少命令误用与编码问题，提升可复现性。

---

## 通用原则

- 文件操作优先用内置文件工具（读取/搜索/编辑），仅在必要时使用 shell
- 优先使用 PowerShell 原生 cmdlet，避免依赖外部 Unix 工具

## 常见坑规避

- **不要使用** `&&` / `||`（PS 5.1 不支持）；用 `;` 或 `if ($?) {}` 判断
- 路径/文件名一律用引号包裹（避免空格与 null）
- 重定向/多行内容用 Here-String：`@' ... '@`（结束标记必须独占一行且在行首）
- 比较用 `-gt/-lt/-eq/-ne`；避免 `>` `<` 被当作重定向
- 空值比较把 `$null` 放左侧：`$null -eq $var`

---

## 编码与 Frontmatter（SKILL.md）

目标：避免因 BOM 导致 skill loader 读不到文件第 1 个字节的 `---`（frontmatter），出现“文件在但无法加载”的隐蔽故障。

- PowerShell 5.1：`Set-Content -Encoding utf8` 可能写入 BOM；对带 frontmatter 的文件（如 `SKILL.md`）避免使用
- 推荐写法：使用 **UTF-8 无 BOM** 写入

示例（仅供参考）：
```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
```
