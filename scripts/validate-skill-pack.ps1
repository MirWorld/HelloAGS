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

    $matches = [regex]::Matches($text, $statePattern)
    if ($matches.Count -eq 0) {
      continue
    }

    foreach ($m in $matches) {
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
    }
  }
}

function Assert-NoDeprecatedTerms([string]$repoRoot, [string[]]$trackedFiles) {
  $mdFiles = $trackedFiles | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }

  # Avoid embedding deprecated terms as plain text in this repo (keeps grep clean),
  # but still block reintroduction into docs.
  $deprecated = ([char]0x6F02) + ([char]0x79FB) + ([char]0x6821) + ([char]0x9A8C)

  foreach ($md in $mdFiles) {
    $fullMd = Join-Path $repoRoot (Normalize-RelativePath $md)
    $text = Get-Content -LiteralPath $fullMd -Raw
    if ($text -match [regex]::Escape($deprecated)) {
      Fail "Deprecated term found in ${md}. Please follow 'references/terminology.md'."
    }
  }
}

$repoRoot = Get-RepoRoot
$tracked = Get-TrackedFiles $repoRoot

Info "RepoRoot: $repoRoot"
Info "Tracked files: $($tracked.Count)"

# Required files (minimal contract for this repo as a skill pack)
$required = @(
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
  "references/terminology.md",
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

foreach ($r in $required) {
  Assert-FileExists -repoRoot $repoRoot -relativePath $r
}

Assert-NoBrokenInternalReferences -repoRoot $repoRoot -trackedFiles $tracked
Assert-InteractiveWaitContracts -repoRoot $repoRoot -trackedFiles $tracked
Assert-NoDeprecatedTerms -repoRoot $repoRoot -trackedFiles $tracked

# Template invariants (structural & contract-only; avoid brittle prose checks)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @("<output_format>", "<exception_output_format>")
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/output-format.md" -needles @(
  "<helloagents_state>",
  "version:",
  "mode:",
  "phase:",
  "status:",
  "awaiting_kind:",
  "package:",
  "next_unique_action:"
)
Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/active-context-template.md" -needles @(
  "## Modules (Public Surface)",
  "## Contracts Index",
  "## Data Flow Guarantees",
  "## Known Gaps / Risks",
  "## Next"
)

Assert-NotMatches -repoRoot $repoRoot -relativePath "templates/active-context-template.md" -pattern '\[SRC:CODE\][^\r\n]*(?::\d+|#L\d+)\b' -hint "Don't include resolvable [SRC:CODE] pointers in the template; ~init runs before real files/line numbers exist."

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-template.md" -needles @(
  "## 上下文快照",
  "## Review 记录",
  "## Active Context 更新记录"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-how-template.md" -needles @(
  "## 执行域声明（Allow/Deny）",
  "## 中期落盘（上下文快照）"
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
  "## SSOT Map"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "SKILL.md" -needles @(
  "<!-- CONTRACT: skill-no-redo v1 -->"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "develop/SKILL.md" -needles @(
  "<!-- CONTRACT: develop-no-redo v1 -->"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/resume-protocol.md" -needles @(
  "<!-- CONTRACT: resume-no-redo v1 -->"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/context-snapshot.md" -needles @(
  "### 错误与尝试",
  "### 待用户输入（Pending）",
  "### 下一步唯一动作",
  "下一步唯一动作:"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "references/quickfix-protocol.md" -needles @(
  "<!-- CONTRACT: quickfix-protocol v1 -->",
  "verify_min"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-quickfix-template.md" -needles @(
  "## 上下文快照",
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
  "verify_min"
)

Assert-ContainsAll -repoRoot $repoRoot -relativePath "templates/plan-task-template.md" -needles @(
  "### 错误与尝试",
  "### 待用户输入（Pending）",
  "### 下一步唯一动作",
  "下一步唯一动作:"
)

Info "OK: skill pack validation passed"
