param(
  [switch]$CheckCodexCopy
)

$ErrorActionPreference = "Stop"

function Fail([string]$message) {
  Write-Error $message
  exit 1
}

function Info([string]$message) {
  Write-Output $message
}

function Get-RepoRoot() {
  try {
    $root = (git rev-parse --show-toplevel 2>$null).Trim()
    if (-not [string]::IsNullOrWhiteSpace($root)) {
      return $root
    }
  } catch {
    # ignore
  }

  $here = $PSScriptRoot
  if (-not $here) {
    Fail "Cannot determine script directory; run this script from a file on disk."
  }

  return (Resolve-Path -LiteralPath (Join-Path $here "..")).Path
}

function Get-TrackedFiles([string]$repoRoot) {
  Push-Location $repoRoot
  try {
    $files = git ls-files
    if ($LASTEXITCODE -ne 0) {
      Fail "git ls-files failed. Ensure this is a git repo."
    }
    return $files
  } finally {
    Pop-Location
  }
}

function Normalize-RelativePath([string]$path) {
  return $path.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
}

function Resolve-Reference([string]$repoRoot, [string]$sourceFile, [string]$rawRef) {
  $sourceDir = Split-Path -Parent (Join-Path $repoRoot (Normalize-RelativePath $sourceFile))
  $ref = Normalize-RelativePath $rawRef
  return [System.IO.Path]::GetFullPath((Join-Path $sourceDir $ref))
}

function Assert-FileExists([string]$repoRoot, [string]$relativePath) {
  $full = Join-Path $repoRoot (Normalize-RelativePath $relativePath)
  if (-not (Test-Path -LiteralPath $full)) {
    Fail "Missing required file: $relativePath"
  }
}

function Assert-ContainsAll([string]$repoRoot, [string]$relativePath, [string[]]$needles) {
  $full = Join-Path $repoRoot (Normalize-RelativePath $relativePath)
  if (-not (Test-Path -LiteralPath $full)) {
    Fail "File not found for content check: $relativePath"
  }

  $text = Get-Content -LiteralPath $full -Raw
  foreach ($needle in $needles) {
    if ($text -notmatch [regex]::Escape($needle)) {
      Fail "Missing required content in ${relativePath}: '$needle'"
    }
  }
}

function Assert-NotContainsAny([string]$repoRoot, [string]$relativePath, [string[]]$needles) {
  $full = Join-Path $repoRoot (Normalize-RelativePath $relativePath)
  if (-not (Test-Path -LiteralPath $full)) {
    Fail "File not found for negative content check: $relativePath"
  }

  $text = Get-Content -LiteralPath $full -Raw
  foreach ($needle in $needles) {
    if ($text -match [regex]::Escape($needle)) {
      Fail "Unexpected content in ${relativePath}: '$needle'"
    }
  }
}

function Assert-NoBrokenInternalReferences([string]$repoRoot, [string[]]$trackedFiles) {
  $mdFiles = $trackedFiles | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }
  $pattern = "(?<path>(?:\\.{1,2}/)*?(?:references|templates|examples|analyze|design|develop|kb|scripts)/[A-Za-z0-9][A-Za-z0-9._\\-]+\\.(?:md|ps1))"

  foreach ($md in $mdFiles) {
    $fullMd = Join-Path $repoRoot (Normalize-RelativePath $md)
    $text = Get-Content -LiteralPath $fullMd -Raw
    $matches = [regex]::Matches($text, $pattern)
    foreach ($m in $matches) {
      $rawRef = $m.Groups["path"].Value
      $resolved = Resolve-Reference -repoRoot $repoRoot -sourceFile $md -rawRef $rawRef
      if (-not (Test-Path -LiteralPath $resolved)) {
        Fail "Broken reference in ${md}: '$rawRef' (resolved: $resolved)"
      }
    }
  }
}

function Assert-InteractiveWaitContracts([string]$repoRoot, [string[]]$trackedFiles) {
  $mdFiles = $trackedFiles | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }
  $allowedModes = @("plan", "exec", "auto", "init", "qa")
  $allowedPhases = @("routing", "analyze", "design", "develop", "kb")
  $allowedAwaitingKinds = @("questions", "choice", "confirm")
  $statePattern = "(?s)<helloagents_state>\\s*(?<body>.*?)\\s*</helloagents_state>"

  function Normalize-StateValue([string]$raw) {
    if ($null -eq $raw) {
      return ""
    }
    $v = [regex]::Replace($raw, "\\s+#.*$", "")
    $v = $v.Trim()
    if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
      if ($v.Length -ge 2) {
        $v = $v.Substring(1, $v.Length - 2)
      }
    }
    return $v.Trim()
  }

  function Get-Options([string]$value) {
    $v = Normalize-StateValue $value
    if ([string]::IsNullOrWhiteSpace($v)) {
      return @()
    }
    return $v.Split("|") | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  }

  function Parse-StateBlock([string]$body) {
    $kv = @{}
    $lines = $body -split "`r?`n"
    foreach ($line in $lines) {
      $t = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($t)) {
        continue
      }
      if ($t.StartsWith("#")) {
        continue
      }
      $colon = $t.IndexOf(":")
      if ($colon -lt 0) {
        continue
      }
      $key = $t.Substring(0, $colon).Trim()
      $value = Normalize-StateValue ($t.Substring($colon + 1).Trim())
      $kv[$key] = $value
    }
    return $kv
  }

  function Assert-OptionsSubset([string]$md, [string]$key, [string[]]$options, [string[]]$allowed) {
    foreach ($opt in $options) {
      if ($opt -notin $allowed) {
        Fail "Interactive wait state invalid in ${md}: ${key} '${opt}' is not in [$($allowed -join ', ')]"
      }
    }
  }

  foreach ($md in $mdFiles) {
    $fullMd = Join-Path $repoRoot (Normalize-RelativePath $md)
    $text = Get-Content -LiteralPath $fullMd -Raw

    $matches = [regex]::Matches($text, $statePattern)
    if ($matches.Count -eq 0) {
      continue
    }

    foreach ($m in $matches) {
      $beforeLen = [Math]::Min(2000, $m.Index)
      $before = $text.Substring($m.Index - $beforeLen, $beforeLen)
      if ($before -notmatch [regex]::Escape("回复契约:")) {
        Fail "Interactive wait contract missing '回复契约:' near state block in ${md}"
      }

      $body = $m.Groups["body"].Value
      $kv = Parse-StateBlock $body

      $requiredKeys = @("version", "mode", "phase", "status", "awaiting_kind", "package", "next_unique_action")
      foreach ($k in $requiredKeys) {
        if (-not $kv.ContainsKey($k)) {
          Fail "Interactive wait state invalid in ${md}: missing key '${k}'"
        }
      }

      if ($kv["version"] -ne "1") {
        Fail "Interactive wait state invalid in ${md}: version must be 1 (got '$($kv["version"])')"
      }

      $modeOpts = Get-Options $kv["mode"]
      if ($modeOpts.Count -ne 1) {
        Fail "Interactive wait state invalid in ${md}: mode must be a single value (got '$($kv["mode"])')"
      }
      Assert-OptionsSubset -md $md -key "mode" -options $modeOpts -allowed $allowedModes

      $phaseOpts = Get-Options $kv["phase"]
      if ($phaseOpts.Count -ne 1) {
        Fail "Interactive wait state invalid in ${md}: phase must be a single value (got '$($kv["phase"])')"
      }
      Assert-OptionsSubset -md $md -key "phase" -options $phaseOpts -allowed $allowedPhases

      if ($kv["status"] -ne "awaiting_user_input") {
        Fail "Interactive wait state invalid in ${md}: status must be awaiting_user_input (got '$($kv["status"])')"
      }

      $kindOpts = Get-Options $kv["awaiting_kind"]
      if ($kindOpts.Count -ne 1) {
        Fail "Interactive wait state invalid in ${md}: awaiting_kind must be a single value (got '$($kv["awaiting_kind"])')"
      }
      Assert-OptionsSubset -md $md -key "awaiting_kind" -options $kindOpts -allowed $allowedAwaitingKinds

      if ($kv["package"].Contains("...")) {
        Fail "Interactive wait state invalid in ${md}: package must not contain '...' (got '$($kv["package"])')"
      }

      if (-not $kv["next_unique_action"].StartsWith("等待用户", [System.StringComparison]::Ordinal)) {
        Fail "Interactive wait state invalid in ${md}: next_unique_action must start with '等待用户' (got '$($kv["next_unique_action"])')"
      }
    }
  }
}

function Assert-NoPlanAllowsSideEffects([string]$repoRoot, [string[]]$trackedFiles) {
  $mdFiles = $trackedFiles | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }
  $pattern = "(?s)(规划域|~plan)[\\s\\S]{0,200}(允许|可以|支持)(?<mid>[\\s\\S]{0,120})(build|test|install|migrate|迁移|构建|安装|测试)"
  $negation = "(禁止|不允许|不得|不可)"

  foreach ($md in $mdFiles) {
    $fullMd = Join-Path $repoRoot (Normalize-RelativePath $md)
    $text = Get-Content -LiteralPath $fullMd -Raw
    $matches = [regex]::Matches($text, $pattern)
    foreach ($m in $matches) {
      $mid = $m.Groups["mid"].Value
      if ($mid -match $negation) {
        continue
      }
      Fail "Plan domain wording contradiction in ${md}: found allowance of side-effect command near '$($m.Value.Trim())'"
    }
  }
}

function Assert-CodexCopyConsistent([string]$repoRoot, [string[]]$trackedFiles) {
  $codexRoot = Join-Path $repoRoot ".codex\\skills\\helloagents"
  if (-not (Test-Path -LiteralPath $codexRoot)) {
    Info "Skip: .codex skill copy not found at $codexRoot"
    return
  }

  $coreFiles = $trackedFiles | Where-Object {
    $_ -in @("SKILL.md", "README.md", "LICENSE", "NOTICE") -or
    $_ -match "^(analyze|design|develop|kb|references|templates|examples)/"
  }

  $diff = New-Object System.Collections.Generic.List[string]
  foreach ($rel in $coreFiles) {
    $src = Join-Path $repoRoot (Normalize-RelativePath $rel)
    $dst = Join-Path $codexRoot (Normalize-RelativePath $rel)
    if (-not (Test-Path -LiteralPath $dst)) {
      $diff.Add("Missing in .codex copy: $rel")
      continue
    }
    $srcHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash
    $dstHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash
    if ($srcHash -ne $dstHash) {
      $diff.Add("Drift: $rel")
    }
  }

  if ($diff.Count -gt 0) {
    $msg = "Codex copy drift detected in ${codexRoot}:`n" + ($diff -join "`n")
    Fail $msg
  }

  Info "OK: .codex skill copy matches tracked files"
}

$repoRoot = Get-RepoRoot
$tracked = Get-TrackedFiles $repoRoot

Info "RepoRoot: $repoRoot"
Info "Tracked files: $($tracked.Count)"

# Required files (minimal contract for this repo as a skill pack)
$required = @(
  "SKILL.md",
  "README.md",
  "LICENSE",
  "LICENSE-CC-BY-4.0",
  "LICENSE-SUMMARY.md",
  "NOTICE",
  "analyze/SKILL.md",
  "design/SKILL.md",
  "develop/SKILL.md",
  "kb/SKILL.md",
  "templates/output-format.md",
  "templates/plan-why-template.md",
  "templates/plan-how-template.md",
  "templates/plan-task-template.md",
  "templates/plan-why-quickfix-template.md",
  "templates/plan-how-quickfix-template.md",
  "templates/plan-task-quickfix-template.md",
  "templates/active-context-template.md",
  "templates/validate-active-context.ps1",
  "templates/validate-plan-package.ps1",
  "references/routing.md",
  "references/plan-lifecycle.md",
  "references/command-policy.md",
  "references/active-context.md",
  "references/context-snapshot.md",
  "references/quickfix-protocol.md",
  "references/hook-simulation.md",
  "references/read-paths.md",
  "references/prompt-optimization.md",
  "references/triage-pass.md",
  "references/failure-protocol.md",
  "references/review-protocol.md"
)

foreach ($r in $required) {
  Assert-FileExists -repoRoot $repoRoot -relativePath $r
}

Assert-NoBrokenInternalReferences -repoRoot $repoRoot -trackedFiles $tracked
Assert-InteractiveWaitContracts -repoRoot $repoRoot -trackedFiles $tracked
Assert-NoPlanAllowsSideEffects -repoRoot $repoRoot -trackedFiles $tracked

# Template invariants (keep light; fail only on foundational structure)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @("<output_format>", "<exception_output_format>")
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @(
  "<helloagents_state>",
  "status: awaiting_user_input",
  "awaiting_kind:",
  "回复契约:",
  "运行态渲染规则（硬约束"
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/active-context-template.md" -needles @(
  "## Modules (Public Surface)",
  "## Contracts Index",
  "## Data Flow Guarantees",
  "## Known Gaps / Risks",
  "## Next"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-template.md" -needles @(
  "## 上下文快照",
  "## Review 记录",
  "## Active Context 更新记录"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-how-template.md" -needles @(
  "## 中期落盘（上下文快照）",
  "## 执行域声明（Allow/Deny）",
  "## 跨层一致性（如触发）"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/routing.md" -needles @(
  "## 0) 阻断式路由（Hard Stop）",
  "续作/断层恢复",
  "<helloagents_state>",
  "结构化判定",
  "不再支持",
  "最小完整方案包",
  "write_scope",
  "no_write",
  "helloagents_only",
  "code_write"
)

# Guardrail: prevent "task-only plan package" from creeping back in.
Assert-NotContainsAny -repoRoot $repoRoot -relativePath "references/routing.md" -needles @(
  '仅 `task.md`'
)

# Core invariants (keep small but strict; prevents semantic drift)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/context-snapshot.md" -needles @(
  "### 错误与尝试",
  "### 待用户输入（Pending）",
  "### 下一步唯一动作",
  "下一步唯一动作:"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/resume-protocol.md" -needles @(
  "5 问 Reboot Check",
  "下一步唯一动作",
  "待用户输入（Pending）",
  "回复契约",
  "git rev-parse --show-toplevel",
  "PROJECT_ROOT"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/review-protocol.md" -needles @(
  "置信度 0–100",
  "≥80"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/subagent-orchestration.md" -needles @(
  "Multiple Independent Passes",
  "只读的侦察/审查器"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/command-policy.md" -needles @(
  "只读命令（允许）",
  "有副作用命令（禁止于规划域）",
  "规划域（~plan / 方案设计阶段）",
  "只允许只读命令",
  "禁止有副作用命令",
  "执行域（~exec / 开发实施阶段）",
  "灰区处理"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "analyze/SKILL.md" -needles @(
  "../references/checklist-triggers.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "kb/SKILL.md" -needles @(
  "../references/checklist-triggers.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "design/SKILL.md" -needles @(
  "规划域护栏（Plan-only）",
  "只读命令",
  "references/command-policy.md",
  "方案设计入场门槛",
  "不创建方案包",
  "<helloagents_state>",
  "plan-why-quickfix-template.md",
  "quickfix-protocol.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/quickfix-protocol.md" -needles @(
  "完整方案包",
  "改一个参数",
  "真值源是否唯一",
  "单位与边界是否一致",
  "消费者有哪些",
  "最小动作"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-quickfix-template.md" -needles @(
  "## 上下文快照",
  "### 待用户输入（Pending）",
  "### 错误与尝试",
  "### 下一步唯一动作",
  "下一步唯一动作:"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/triage-pass.md" -needles @(
  "入口与调用链",
  "契约载体",
  "副作用点与消费者",
  "下一步唯一动作"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/pre-implementation-checklist.md" -needles @(
  "高信号取证已完成",
  "references/triage-pass.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/quality-gates.md" -needles @(
  "最小-最快-最高信号",
  "证据落盘"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-template.md" -needles @(
  "### 错误与尝试",
  "### 待用户输入（Pending）",
  "### 下一步唯一动作",
  "下一步唯一动作:"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/read-paths.md" -needles @(
  "最短读取路径",
  "停止条件",
  "references/routing.md",
  "templates/output-format.md",
  "git rev-parse --show-toplevel",
  "PROJECT_ROOT"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/prompt-optimization.md" -needles @(
  "Trigger-only",
  "RTCF",
  "默认写入范围",
  "冲突约束处理"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/project-profile.md" -needles @(
  "git rev-parse --show-toplevel",
  "PROJECT_ROOT",
  "工作区根目录"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/hook-simulation.md" -needles @(
  "SessionStart",
  "UserPromptSubmit",
  "PreToolUse",
  "Stop",
  "references/routing.md",
  "references/command-policy.md",
  "references/execution-guard.md",
  "references/review-protocol.md",
  "templates/output-format.md"
)

if ($CheckCodexCopy) {
  Assert-CodexCopyConsistent -repoRoot $repoRoot -trackedFiles $tracked
}

Info "OK: skill pack validation passed"
