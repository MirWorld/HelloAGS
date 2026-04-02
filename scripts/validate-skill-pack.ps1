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
  $ref = $rawRef.Trim()
  $refNormalized = Normalize-RelativePath $ref

  $isRelative =
    $ref.StartsWith("./", [System.StringComparison]::Ordinal) -or
    $ref.StartsWith("../", [System.StringComparison]::Ordinal) -or
    $ref.StartsWith(".\\", [System.StringComparison]::Ordinal) -or
    $ref.StartsWith("..\\", [System.StringComparison]::Ordinal)

  $baseDir = if ($isRelative) { $sourceDir } else { $repoRoot }
  return [System.IO.Path]::GetFullPath((Join-Path $baseDir $refNormalized))
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

function Assert-NotMatches([string]$repoRoot, [string]$relativePath, [string]$pattern, [string]$hint) {
  $full = Join-Path $repoRoot (Normalize-RelativePath $relativePath)
  if (-not (Test-Path -LiteralPath $full)) {
    Fail "File not found for regex check: $relativePath"
  }

  $text = Get-Content -LiteralPath $full -Raw
  if ($text -match $pattern) {
    $msg = "Unexpected pattern in ${relativePath}: ${pattern}"
    if (-not [string]::IsNullOrWhiteSpace($hint)) {
      $msg += "`nHint: $hint"
    }
    Fail $msg
  }
}

function Assert-NoBrokenInternalReferences([string]$repoRoot, [string[]]$trackedFiles) {
  $mdFiles = $trackedFiles | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }
  $pattern = '(?<!/)(?<path>(?:\.{1,2}/)*?(?:references|templates|examples|analyze|design|develop|kb|scripts)/(?:[A-Za-z0-9][A-Za-z0-9._\-]*/)*[A-Za-z0-9][A-Za-z0-9._\-]*\.(?:md|ps1))'

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
  $statePattern = '(?ms)^\s*<helloagents_state>\s*(?<body>.*?)^\s*</helloagents_state>\s*$'

  function Normalize-StateValue([string]$raw) {
    if ($null -eq $raw) {
      return ""
    }
    $v = [regex]::Replace($raw, '\s+#.*$', '')
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

    $stateMatches = [regex]::Matches($text, $statePattern)
    if ($stateMatches.Count -eq 0) {
      continue
    }

    if (-not ([regex]::IsMatch($text, [regex]::Escape("回复契约:")))) {
      Fail "Interactive wait state invalid in ${md}: missing '回复契约:' (reply contract). Any file with <helloagents_state> must include a reply contract line."
    }

    foreach ($m in $stateMatches) {
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

      $nextAction = Normalize-StateValue $kv["next_unique_action"]
      if ([string]::IsNullOrWhiteSpace($nextAction)) {
        Fail "Interactive wait state invalid in ${md}: next_unique_action must be non-empty"
      }
    }
  }
}

function Assert-NoDeprecatedTerms([string]$repoRoot, [string[]]$trackedFiles) {
  $mdFiles = $trackedFiles | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }

  # Prefer SSOT terminology (see references/terminology.md).
  # Keep this as a warning (not a hard fail) to avoid brittle prose gating.
  $deprecated = ([char]0x6F02) + ([char]0x79FB) + ([char]0x6821) + ([char]0x9A8C)

  foreach ($md in $mdFiles) {
    $fullMd = Join-Path $repoRoot (Normalize-RelativePath $md)
    $text = Get-Content -LiteralPath $fullMd -Raw
    if ($text -match [regex]::Escape($deprecated)) {
      Info "WARN: Deprecated term found in ${md}. Please follow 'references/terminology.md'."
    }
  }
}

function Assert-SignalSeveritySSOT([string]$repoRoot, [string[]]$trackedFiles) {
  $mdFiles = $trackedFiles | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }
  $signalFile = "references/signal-severity.md"
  $patternGreen = '(?m)^\s*-\s*\*\*Green\*\*\s*[:：]'
  $patternYellow = '(?m)^\s*-\s*\*\*Yellow\*\*\s*[:：]'
  $patternRed = '(?m)^\s*-\s*\*\*Red\*\*\s*[:：]'

  foreach ($md in $mdFiles) {
    if ($md -eq $signalFile) {
      continue
    }

    $fullMd = Join-Path $repoRoot (Normalize-RelativePath $md)
    $text = Get-Content -LiteralPath $fullMd -Raw
    if (($text -match $patternGreen) -and ($text -match $patternYellow) -and ($text -match $patternRed)) {
      Fail "Signal severity definitions should live only in ${signalFile}; found duplicated level definitions in ${md}."
    }
  }
}

function Get-WorkspaceBootstrapManifest([string]$repoRoot) {
  $relativePath = "templates/workspace-bootstrap-manifest.json"
  $full = Join-Path $repoRoot (Normalize-RelativePath $relativePath)
  if (-not (Test-Path -LiteralPath $full)) {
    Fail "Missing required file: $relativePath"
  }

  try {
    return (Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -Depth 32)
  } catch {
    Fail ("Invalid JSON in {0}: {1}" -f $relativePath, $_.Exception.Message)
  }
}

$repoRoot = Get-RepoRoot
$tracked = Get-TrackedFiles $repoRoot
$workspaceBootstrapManifest = Get-WorkspaceBootstrapManifest -repoRoot $repoRoot

Info "RepoRoot: $repoRoot"
Info "Tracked files: $($tracked.Count)"

# Required files (minimal contract for this repo as a skill pack)
$required = @(
  ".gitignore",
  ".gitattributes",
  "SKILL.md",
  "README.md",
  "LICENSE",
  "LICENSE-CC-BY-4.0",
  "LICENSE-SUMMARY.md",
  "NOTICE",
  ".github/workflows/validate-skill-pack.yml",
  "analyze/SKILL.md",
  "design/SKILL.md",
  "develop/SKILL.md",
  "kb/SKILL.md",
  "scripts/validate-skill-pack-smoke.ps1",
  "scripts/hooks/helloagents-context-threshold.ps1",
  "scripts/hooks/helloagents-stop.ps1",
  "scripts/hooks/helloagents-sessionstart.ps1",
  "scripts/hooks/helloagents-userpromptsubmit.ps1",
  "templates/output-format.md",
  "templates/plan-why-template.md",
  "templates/plan-how-template.md",
  "templates/plan-task-template.md",
  "templates/plan-why-quickfix-template.md",
  "templates/plan-how-quickfix-template.md",
  "templates/plan-task-quickfix-template.md",
  "templates/workspace-bootstrap-manifest.json",
  "templates/hooks/stop-hook-fixture.json",
  "templates/hooks/stop-hook-feature-removal-fixture.json",
  "templates/hooks/sessionstart-hook-fixture.json",
  "templates/hooks/userpromptsubmit-hook-fixture.json",
  "templates/hooks/hooks.json",
  "templates/hooks/config.toml.snippet",
  "templates/validate-active-context.ps1",
  "templates/validate-plan-package.ps1",
  "references/routing.md",
  "references/plan-lifecycle.md",
  "references/command-policy.md",
  "references/active-context.md",
  "references/terminology.md",
  "references/signal-severity.md",
  "references/feature-removal-guard.md",
  "references/codex-upstream-leverage.md",
  "references/contracts.md",
  "references/context-snapshot.md",
  "references/quickfix-protocol.md",
  "references/hook-simulation.md",
  "references/read-paths.md",
  "references/resume-protocol.md",
  "references/prompt-optimization.md",
  "references/triage-pass.md",
  "references/failure-protocol.md",
  "references/review-protocol.md"
)

$bootstrapTemplatePaths = @()
foreach ($entry in @($workspaceBootstrapManifest.files)) {
  $templatePath = ""
  try { $templatePath = $entry.template } catch { $templatePath = "" }
  if (-not [string]::IsNullOrWhiteSpace($templatePath)) {
    $bootstrapTemplatePaths += $templatePath.Trim()
  }
}
$required += ($bootstrapTemplatePaths | Sort-Object -Unique)

foreach ($r in $required) {
  Assert-FileExists -repoRoot $repoRoot -relativePath $r
}

Assert-NoBrokenInternalReferences -repoRoot $repoRoot -trackedFiles $tracked
Assert-InteractiveWaitContracts -repoRoot $repoRoot -trackedFiles $tracked
Assert-NoDeprecatedTerms -repoRoot $repoRoot -trackedFiles $tracked
Assert-SignalSeveritySSOT -repoRoot $repoRoot -trackedFiles $tracked

# Template invariants (structural & contract-only; avoid brittle prose checks)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @("<output_format>", "<exception_output_format>")
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @(
  "<helloagents_state>",
  "回复契约:",
  "version:",
  "mode:",
  "phase:",
  "status:",
  "awaiting_kind:",
  "package:",
  "next_unique_action:"
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @(
  "awaiting_topic: feature_removal_guard"
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/active-context-template.md" -needles @(
  "## Modules (Public Surface)",
  "## Contracts Index",
  "## Data Flow Guarantees",
  "## Known Gaps / Risks",
  "## Next"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/current-plan-pointer-template.md" -needles @(
  "current_package:"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/workspace-bootstrap-manifest.json" -needles @(
  '"contract": "workspace-bootstrap-manifest v1"',
  '"workspace_root": "HAGSWorks"',
  '"directories"',
  '"files"'
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath ".gitignore" -needles @(
  "/HAGSWorks/",
  "/_codex_temp/"
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "kb/SKILL.md" -needles @(
  "templates/workspace-bootstrap-manifest.json",
  "唯一来源"
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/SKILL.md" -needles @(
  "templates/workspace-bootstrap-manifest.json",
  "唯一来源"
)

Assert-NotMatches -repoRoot $repoRoot -relativePath "templates/active-context-template.md" -pattern '\[SRC:CODE\][^\r\n]*(?::\d+|#L\d+)\b' -hint "Don't include resolvable [SRC:CODE] pointers in the template; ~init runs before real files/line numbers exist."

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-template.md" -needles @(
  "## 上下文快照",
  "## Review 记录",
  "## Active Context 更新记录"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-how-template.md" -needles @(
  "## 执行域声明（Allow/Deny）",
  "## 中期落盘（上下文快照）",
  "## 功能删减审批（如触发）",
  "carry_forward_verify:",
  "## 相邻变化压力（命中时最小展开）",
  "feature_removal_risk:",
  "feature_removal_approved:",
  "Feature Removal（允许功能删减）"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/routing.md" -needles @(
  "## 0) 阻断式路由（Hard Stop）",
  "<helloagents_state>",
  "write_scope",
  "no_write",
  "helloagents_only",
  "code_write",
  "## 6) Feedback-Delta（需求变更）"
)

# Core invariants (keep small but strict; prevents semantic drift)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/terminology.md" -needles @(
  "<!-- CONTRACT: terminology v1 -->",
  "## SSOT Map",
  "references/feature-removal-guard.md",
  "references/signal-severity.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/signal-severity.md" -needles @(
  "<!-- CONTRACT: signal-severity v1 -->",
  "## 1) 等级定义",
  "## 2) 稳定映射",
  "## 3) 使用方式",
  '`model_event: response_incomplete`',
  '`feature_removal_approved: no`',
  '`current_package` 无效 / 不完整 / 指向 history',
  "SessionStart hooks"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/feature-removal-guard.md" -needles @(
  "<!-- CONTRACT: feature-removal-guard v1 -->",
  "## 默认原则",
  "## 用户可见 / 公开表面识别",
  "## 视为功能删减",
  "## 不视为功能删减",
  "### 内部-only 白名单",
  "## 歧义处理",
  "## 判定顺序",
  "## 审批令牌",
  "feature_removal_risk:",
  "feature_removal_approved:",
  "## 命中后的固定动作"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/codex-upstream-leverage.md" -needles @(
  "<!-- CONTRACT: codex-upstream-leverage v1 -->"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/hook-simulation.md" -needles @(
  "references/contracts.md",
  "hook-bridge-protocol v1",
  "scripts/hooks/helloagents-context-threshold.ps1",
  "scripts/hooks/helloagents-stop.ps1",
  "scripts/hooks/helloagents-sessionstart.ps1",
  "scripts/hooks/helloagents-userpromptsubmit.ps1",
  "signal / severity / current_package / next_unique_action / package_status",
  "templates/hooks/stop-hook-fixture.json",
  "templates/hooks/stop-hook-feature-removal-fixture.json",
  "templates/hooks/sessionstart-hook-fixture.json",
  "templates/hooks/userpromptsubmit-hook-fixture.json",
  "templates/hooks/hooks.json",
  "templates/hooks/config.toml.snippet"
)

Assert-NotMatches -repoRoot $repoRoot -relativePath "scripts/hooks/helloagents-stop.ps1" -pattern 'Invoke-Expression|iex\b|Start-Process|Invoke-Command' -hint "Stop hook must treat payload as data only; never execute assistant message content."
Assert-NotMatches -repoRoot $repoRoot -relativePath "scripts/hooks/helloagents-context-threshold.ps1" -pattern 'Invoke-Expression|iex\b|Start-Process|Invoke-Command' -hint "Context-threshold hook should treat payload as data only; never execute dynamic content."
Assert-NotMatches -repoRoot $repoRoot -relativePath "scripts/hooks/helloagents-sessionstart.ps1" -pattern 'Invoke-Expression|iex\b|Start-Process|Invoke-Command' -hint "SessionStart hook should only validate pointers, not execute payload content."
Assert-NotMatches -repoRoot $repoRoot -relativePath "scripts/hooks/helloagents-userpromptsubmit.ps1" -pattern 'Invoke-Expression|iex\b|Start-Process|Invoke-Command' -hint "UserPromptSubmit hook should only guard/augment via JSON output; never execute payload content."
Assert-ContainsAll -repoRoot $repoRoot -relativePath "scripts/hooks/helloagents-sessionstart.ps1" -needles @(
  '"SessionStart"',
  "signal:",
  "severity:",
  "package_status:",
  "current_package_invalid",
  "response_incomplete",
  "package_completed"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/hooks/hooks.json" -needles @(
  '"SessionStart"',
  '"UserPromptSubmit"',
  '"Stop"',
  "helloagents-sessionstart.ps1",
  "helloagents-userpromptsubmit.ps1",
  "helloagents-stop.ps1"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/hooks/config.toml.snippet" -needles @(
  "[features]",
  "codex_hooks"
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath ".github/workflows/validate-skill-pack.yml" -needles @(
  "./scripts/validate-skill-pack.ps1",
  "./scripts/validate-skill-pack-smoke.ps1"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/contracts.md" -needles @(
  "<!-- CONTRACT: protocol-api v1 -->",
  "<!-- CONTRACT: hook-bridge-protocol v1 -->",
  "<helloagents_state>",
  "model_event:",
  "threshold_event:",
  "threshold_source:",
  "remaining_to_compact:",
  "turn_id:",
  "awaiting_topic:",
  "feature_removal_risk:",
  "systemMessage",
  "decision",
  "reason",
  "hookSpecificOutput",
  "hookEventName",
  "additionalContext",
  "hookMessage",
  "signal: response_incomplete",
  "signal: feature_removal_guard",
  "severity: Red",
  "HAGSWorks/plan/_current.md",
  "<!-- CONTRACT: signal-severity v1 -->"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/plan-lifecycle.md" -needles @(
  "<!-- CONTRACT: plan-lifecycle v1 -->",
  "<plan_lifecycle_contract>",
  "history_overwrite: deny",
  "history_conflict_suffix: _v2",
  "current_pointer_file: HAGSWorks/plan/_current.md",
  "current_pointer_key: current_package",
  "</plan_lifecycle_contract>"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "SKILL.md" -needles @(
  "<!-- CONTRACT: skill-no-redo v1 -->",
  "references/feature-removal-guard.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "develop/SKILL.md" -needles @(
  "<!-- CONTRACT: develop-no-redo v1 -->"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/resume-protocol.md" -needles @(
  "<!-- CONTRACT: resume-no-redo v1 -->"
  "<!-- CONTRACT: resume-package-selection v1 -->"
  "<resume_package_selection_contract>"
  "current_pointer_file: HAGSWorks/plan/_current.md"
  "current_pointer_key: current_package"
  "current_marker: （current）"
  "list_current_first: true"
  "list_sort: timestamp_desc"
  "list_timestamp_source: dirname_prefix_YYYYMMDDHHMM"
  "list_tiebreaker: dirname_desc"
  "</resume_package_selection_contract>"
  "<!-- CONTRACT: resume-current-package-pointer v1 -->"
  "threshold_event: near_autocompact"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/context-snapshot.md" -needles @(
  "### 错误与尝试",
  "model_event:",
  "threshold_event:",
  "threshold_source:",
  "remaining_to_compact:",
  "turn_id:",
  "contract_checkpoint:",
  "progress_phase:",
  "### 结构债务（可选，明确知道是权宜实现时填写）",
  "### Repo 状态",
  "### 待用户输入（Pending）",
  "### 下一步唯一动作",
  "下一步唯一动作:",
  "references/signal-severity.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/routing.md" -needles @(
  "references/signal-severity.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/resume-protocol.md" -needles @(
  "references/signal-severity.md"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/quickfix-protocol.md" -needles @(
  "<!-- CONTRACT: quickfix-protocol v1 -->",
  "verify_min",
  "carry_forward_verify"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/break-loop-checklist.md" -needles @(
  "结构侵蚀",
  "热点文件",
  "临时胶水"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/project-profile.md" -needles @(
  "架构不变量",
  "相邻变化压力"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-quickfix-template.md" -needles @(
  "## 上下文快照",
  "model_event:",
  "turn_id:",
  "progress_phase:",
  "### 结构债务（可选，明确知道是权宜实现时填写）",
  "### Repo 状态",
  "### 功能删减审批",
  "feature_removal_risk:",
  "feature_removal_approved:",
  "### 待用户输入（Pending）",
  "### 错误与尝试",
  "### 下一步唯一动作",
  "下一步唯一动作:"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/triage-pass.md" -needles @(
  "<!-- CONTRACT: triage-pass v1 -->",
  "verify_min"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/pre-implementation-checklist.md" -needles @(
  "<!-- CONTRACT: pre-implementation-checklist v1 -->",
  "references/triage-pass.md",
  "verify_min"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/quality-gates.md" -needles @(
  "<!-- CONTRACT: quality-gates v1 -->",
  "verify_min",
  "typecheck → build → test",
  "编译/构建失败"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-template.md" -needles @(
  "执行 build",
  "重跑受影响门禁（通常为 fmt/lint/typecheck/build/test）",
  "carry_forward_verify",
  "### 错误与尝试",
  "model_event:",
  "turn_id:",
  "progress_phase:",
  "### 结构债务（可选，明确知道是权宜实现时填写）",
  "### Repo 状态",
  "### 功能删减审批",
  "feature_removal_risk:",
  "feature_removal_approved:",
  "### 待用户输入（Pending）",
  "### 下一步唯一动作",
  "下一步唯一动作:"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/finish-checklist.md" -needles @(
  "fmt/lint/typecheck/build/test/security"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/routing.md" -needles @(
  "## 0) 阻断式路由（Hard Stop）",
  "疑似功能删减但未获批准",
  "### 6.2 功能删减确认（Feature Removal Confirmation）",
  "feature_removal_approved: yes"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/execution-guard.md" -needles @(
  "Feature Removal（是否允许功能删减）",
  "Feature Removal = 否",
  "feature_removal_approved: yes"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/review-protocol.md" -needles @(
  "references/feature-removal-guard.md",
  "不得删减用户可见表面、默认能力或既有契约",
  "功能删减",
  "结构侵蚀",
  "carry_forward_verify",
  "相邻变化压力",
  "design_debt"
)

Assert-NotContainsAny -repoRoot $repoRoot -relativePath "references/review-protocol.md" -needles @(
  "优先删减到最小必要改动面"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/validate-plan-package.ps1" -needles @(
  "carry_forward_verify",
  "progress_phase",
  "design_debt",
  "revisit_trigger"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @(
  "功能删减确认",
  "等待用户确认是否允许本次功能删减"
)

Info "OK: skill pack validation passed"
