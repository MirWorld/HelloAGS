param(
  [string]$InputFile = "",
  [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

function Write-HookOutputJson {
  param(
    [string]$SystemMessage = "",
    [string]$HookEventName = "",
    [string]$HookMessage = "",
    [string]$Decision = "",
    [string]$Reason = "",
    [string]$AdditionalContext = ""
  )

  $out = [ordered]@{}

  if (-not [string]::IsNullOrWhiteSpace($SystemMessage)) {
    $out.systemMessage = $SystemMessage.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($Decision)) {
    $out.decision = $Decision.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($Reason)) {
    $out.reason = $Reason.Trim()
  }

  $hookSpecific = [ordered]@{}
  if (-not [string]::IsNullOrWhiteSpace($HookEventName)) {
    $hookSpecific.hookEventName = $HookEventName.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($AdditionalContext)) {
    $hookSpecific.additionalContext = $AdditionalContext
  }
  if (-not [string]::IsNullOrWhiteSpace($HookMessage)) {
    $hookSpecific.hookMessage = $HookMessage
  }
  if ($hookSpecific.Count -gt 0) {
    $out.hookSpecificOutput = $hookSpecific
  }

  ($out | ConvertTo-Json -Depth 64 -Compress) | Write-Output
}

function Get-RawInput([string]$inputFile) {
  if (-not [string]::IsNullOrWhiteSpace($inputFile)) {
    if (-not (Test-Path -LiteralPath $inputFile)) {
      return $null
    }
    return Get-Content -LiteralPath $inputFile -Raw -ErrorAction Stop
  }

  try {
    $raw = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      return $raw
    }
  } catch {
    # ignore
  }

  return $null
}

function Try-ParseJson([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $null
  }

  try {
    return ($raw | ConvertFrom-Json -Depth 64)
  } catch {
    return $null
  }
}

function Read-Utf8Text([string]$path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)
  }
  return $text
}

function Get-JsonStringValue($obj, [string[]]$paths) {
  foreach ($path in $paths) {
    $current = $obj
    $ok = $true
    foreach ($segment in $path.Split('.')) {
      if ($null -eq $current) {
        $ok = $false
        break
      }
      try {
        $current = $current.$segment
      } catch {
        $ok = $false
        break
      }
    }

    if ($ok -and ($current -is [string]) -and -not [string]::IsNullOrWhiteSpace($current)) {
      return $current.Trim()
    }
  }

  return $null
}

function Get-ProjectRootFromPayload($obj, [string]$projectRootArg) {
  $fallback = (Get-Location).Path
  $candidates = @(
    $projectRootArg,
    (Get-JsonStringValue $obj @("project_root", "projectRoot", "workspace_root", "workspaceRoot", "cwd", "session.cwd", "session.project_root", "session.projectRoot"))
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    $pathValue = $candidate
    if ($pathValue -eq "__PROJECT_ROOT__") {
      $pathValue = $fallback
    }
    if (Test-Path -LiteralPath $pathValue -PathType Container) {
      return (Resolve-Path -LiteralPath $pathValue).Path
    }
  }

  if (Test-Path -LiteralPath $fallback -PathType Container) {
    return (Resolve-Path -LiteralPath $fallback).Path
  }

  return $null
}

function Resolve-CurrentPackagePath([string]$projectRoot, [string]$pointerValue) {
  if ([string]::IsNullOrWhiteSpace($pointerValue)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($pointerValue)) {
    return $pointerValue
  }

  return (Join-Path $projectRoot $pointerValue)
}

function Get-MarkdownSectionBody([string]$text, [string]$headingText) {
  if ([string]::IsNullOrWhiteSpace($text)) {
    return ""
  }

  $headerEsc = [regex]::Escape($headingText)
  $m = [regex]::Match($text, "(?ms)^\s*${headerEsc}\s*$\s*(?<body>.*?)(?=^\s*###\s+|\z)")
  if (-not $m.Success) {
    return ""
  }

  return $m.Groups["body"].Value
}

function Get-PendingLines([string]$taskText) {
  $pendingBody = Get-MarkdownSectionBody -text $taskText -headingText "### 待用户输入（Pending）"
  if ([string]::IsNullOrWhiteSpace($pendingBody)) {
    return @()
  }

  $lines = @()
  foreach ($line in ($pendingBody -split "`r?`n")) {
    $t = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) {
      continue
    }
    if ($t.StartsWith("<!--")) {
      continue
    }
    if (($t -match '^\-\s*\[SRC:TODO\]') -and (($t -match '…') -or ($t -match '\.\.\.'))) {
      continue
    }
    $lines += $t
  }

  return @($lines)
}

function Test-PackageCompleted([string]$taskText, [string[]]$pendingLines) {
  if ([string]::IsNullOrWhiteSpace($taskText)) {
    return $false
  }

  $taskMatches = [regex]::Matches($taskText, '(?m)^\s*-\s*\[(?<state>\s|√|X|-|\?)\]\s+')
  if ($taskMatches.Count -eq 0) {
    return $false
  }

  foreach ($m in $taskMatches) {
    $state = $m.Groups["state"].Value
    if (($state -ne "√") -and ($state -ne "-")) {
      return $false
    }
  }

  return ($pendingLines.Count -eq 0)
}

function Test-UnresolvedResponseIncomplete([string]$taskText) {
  if ([string]::IsNullOrWhiteSpace($taskText)) {
    return $false
  }

  $snapshotMatch = [regex]::Match($taskText, '(?ms)^\s*##\s*上下文快照\s*$\r?\n(?<body>.*?)(?=^\s*##\s+|\z)')
  if (-not $snapshotMatch.Success) {
    return $false
  }

  $snapshotBody = $snapshotMatch.Groups["body"].Value
  $eventMatches = [regex]::Matches($snapshotBody, '(?im)^\s*-\s*\[SRC:TOOL\]\s*model_event\s*[:：]\s*(?<kind>\S+)(?:\s+#.*)?\s*$')
  if ($eventMatches.Count -eq 0) {
    return $false
  }

  $lastIncomplete = $null
  foreach ($m in $eventMatches) {
    $kind = [regex]::Replace($m.Groups["kind"].Value, '^[`"'',;]+|[`"'',;]+$', '')
    if ($kind -match '(?i)^response[._]incomplete\b') {
      $lastIncomplete = $m
    }
  }

  if ($null -eq $lastIncomplete) {
    return $false
  }

  $after = ""
  try {
    $start = [Math]::Min($snapshotBody.Length, $lastIncomplete.Index + $lastIncomplete.Length)
    $after = $snapshotBody.Substring($start)
  } catch {
    $after = ""
  }

  $hasRepoAfter = ($after -match '(?im)\brepo_state\s*[:：]\s*\S')
  $hasNextAfter = ($after -match '(?im)下一步唯一动作\s*[:：]\s*\S')
  return (-not ($hasRepoAfter -and $hasNextAfter))
}

$raw = Get-RawInput -inputFile $InputFile
if ([string]::IsNullOrWhiteSpace($raw)) {
  Write-HookOutputJson
  exit 0
}

$payload = Try-ParseJson -raw $raw
if ($null -eq $payload) {
  Write-HookOutputJson
  exit 0
}

$projectRootResolved = Get-ProjectRootFromPayload -obj $payload -projectRootArg $ProjectRoot
if ([string]::IsNullOrWhiteSpace($projectRootResolved)) {
  Write-HookOutputJson
  exit 0
}

$pointerFile = Join-Path $projectRootResolved "HAGSWorks/plan/_current.md"
if (-not (Test-Path -LiteralPath $pointerFile)) {
  Write-HookOutputJson
  exit 0
}

$pointerText = Read-Utf8Text -path $pointerFile
$match = [regex]::Match($pointerText, '(?m)^\s*current_package\s*:\s*(?<path>.*)\s*$')
if (-not $match.Success) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md missing current_package key. next=修复指针格式"
  exit 0
}

$rawPointer = [regex]::Replace($match.Groups["path"].Value, '\s+#.*$', '').Trim()
if ([string]::IsNullOrWhiteSpace($rawPointer)) {
  Write-HookOutputJson
  exit 0
}

$resolvedPackage = Resolve-CurrentPackagePath -projectRoot $projectRootResolved -pointerValue $rawPointer
$planRoot = (Join-Path $projectRootResolved "HAGSWorks/plan")
$historyRoot = (Join-Path $projectRootResolved "HAGSWorks/history")

try {
  $planRootFull = [System.IO.Path]::GetFullPath($planRoot)
  $historyRootFull = [System.IO.Path]::GetFullPath($historyRoot)
  $resolvedPackageFull = [System.IO.Path]::GetFullPath($resolvedPackage)
} catch {
  Write-HookOutputJson -SystemMessage "WARN: current_package path cannot be normalized: '$rawPointer'. next=修复指针路径"
  exit 0
}

if ($resolvedPackageFull.StartsWith($historyRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md points to history: '$rawPointer'. next=改回 HAGSWorks/plan 下的有效方案包"
  exit 0
}

if (-not $resolvedPackageFull.StartsWith($planRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md points outside plan root: '$rawPointer'. next=改回 HAGSWorks/plan 下的有效方案包"
  exit 0
}

if (-not (Test-Path -LiteralPath $resolvedPackageFull -PathType Container)) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md current_package directory not found: '$rawPointer'. next=修复指针或重新选包"
  exit 0
}

$requiredFiles = @("why.md", "how.md", "task.md")
$missing = @()
foreach ($name in $requiredFiles) {
  $full = Join-Path $resolvedPackageFull $name
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    $missing += $name
    continue
  }

  $content = Read-Utf8Text -path $full
  if ([string]::IsNullOrWhiteSpace($content)) {
    $missing += $name
  }
}

if ($missing.Count -gt 0) {
  Write-HookOutputJson -SystemMessage ("WARN: _current.md points to incomplete package: '{0}' missing={1}. next=修复方案包或重新选包" -f $rawPointer, ($missing -join ","))
  exit 0
}

$taskFile = Join-Path $resolvedPackageFull "task.md"
$taskText = Read-Utf8Text -path $taskFile
$pendingLines = @(Get-PendingLines -taskText $taskText)
if (Test-UnresolvedResponseIncomplete -taskText $taskText) {
  Write-HookOutputJson -SystemMessage ("WARN: current_package contains unresolved response_incomplete: '{0}'. next=先补恢复检查点或先走恢复流程" -f $rawPointer)
  exit 0
}

if (Test-PackageCompleted -taskText $taskText -pendingLines $pendingLines) {
  Write-HookOutputJson -SystemMessage ("WARN: current_package already completed with no Pending: '{0}'. next=等待新需求或新建方案包，不要继续执行当前包" -f $rawPointer)
  exit 0
}

Write-HookOutputJson
