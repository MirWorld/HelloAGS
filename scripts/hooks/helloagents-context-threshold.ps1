param(
  [string]$InputFile = "",
  [string]$ProjectRoot = "",
  [string]$Package = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$H2_CONTEXT_SNAPSHOT = [string]::Concat(
  [char]0x4E0A,
  [char]0x4E0B,
  [char]0x6587,
  [char]0x5FEB,
  [char]0x7167
)

$H3_CONTEXT_THRESHOLD = [string]::Concat(
  [char]0x538B,
  [char]0x7F29,
  [char]0x9608,
  [char]0x503C,
  [char]0x68C0,
  [char]0x67E5,
  [char]0x70B9,
  [char]0xFF08,
  [char]0x53EF,
  [char]0x9009,
  [char]0xFF0C,
  [char]0x7ED3,
  [char]0x6784,
  [char]0x5316,
  [char]0xFF09
)

$LABEL_NEXT_UNIQUE_ACTION = [string]::Concat(
  [char]0x4E0B,
  [char]0x4E00,
  [char]0x6B65,
  [char]0x552F,
  [char]0x4E00,
  [char]0x52A8,
  [char]0x4F5C
)

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

    if ($ok -and $null -ne $current) {
      if ($current -is [datetime]) {
        return $current.ToUniversalTime().ToString("o")
      }
      $value = $current.ToString()
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value.Trim()
      }
    }
  }

  return $null
}

function Get-JsonIntValue($obj, [string[]]$paths) {
  foreach ($path in $paths) {
    $raw = Get-JsonStringValue $obj @($path)
    if ([string]::IsNullOrWhiteSpace($raw)) {
      continue
    }

    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed)) {
      return $parsed
    }
  }

  return $null
}

function Get-ProjectRootFromPayload($obj, [string]$projectRootArg) {
  $fallback = (Get-Location).Path
  $candidates = @(
    $projectRootArg,
    (Get-JsonStringValue $obj @("project_root", "projectRoot", "workspace_root", "workspaceRoot", "cwd", "session.cwd"))
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

function Read-Utf8Text([string]$path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)
  }
  return $text
}

function Write-Utf8Text([string]$path, [string]$text) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

function Resolve-CurrentPackage([string]$projectRoot, [string]$packageArg) {
  if (-not [string]::IsNullOrWhiteSpace($packageArg)) {
    if ([System.IO.Path]::IsPathRooted($packageArg)) {
      return $packageArg
    }
    return (Join-Path $projectRoot $packageArg)
  }

  $pointer = Join-Path $projectRoot "HAGSWorks/plan/_current.md"
  if (-not (Test-Path -LiteralPath $pointer -PathType Leaf)) {
    return $null
  }

  $text = Read-Utf8Text -path $pointer
  $m = [regex]::Match($text, '(?m)^\s*current_package\s*:\s*(?<path>.*)\s*$')
  if (-not $m.Success) {
    return $null
  }

  $raw = [regex]::Replace($m.Groups["path"].Value, '\s+#.*$', '').Trim()
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($raw)) {
    return $raw
  }

  return (Join-Path $projectRoot $raw)
}

function Resolve-TaskFile([string]$packagePath) {
  if ([string]::IsNullOrWhiteSpace($packagePath)) {
    return $null
  }

  return (Join-Path $packagePath "task.md")
}

function Get-H2Section([string]$text, [string]$title) {
  $pattern = '(?ms)^\s*##\s*' + [regex]::Escape($title) + '\s*$\r?\n'
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) {
    return $null
  }

  $start = $m.Index + $m.Length
  $tail = $text.Substring($start)
  $next = [regex]::Match($tail, '(?m)^\s*##\s+')
  $end = if ($next.Success) { $start + $next.Index } else { $text.Length }

  return [pscustomobject]@{
    before = $text.Substring(0, $start)
    body = $text.Substring($start, $end - $start)
    after = $text.Substring($end)
  }
}

function Ensure-TrailingNewline([string]$text) {
  if ($text -match "(\r?\n)$") {
    return $text
  }
  return ($text + "`n")
}

function Get-RepoState([string]$projectRoot) {
  $state = [ordered]@{
    branch = "unknown"
    head = "unknown"
    dirty = "unknown"
    diffstat = "unknown"
  }

  try {
    Push-Location $projectRoot
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $head = (git rev-parse --short HEAD 2>$null).Trim()
    $status = @(git status --porcelain 2>$null)
    $dirty = $false
    if ($status.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($status -join ""))) {
      $dirty = $true
    }
    $diffLines = @(git diff --stat 2>$null)
    $diffstat = "none"
    if ($diffLines.Count -gt 0) {
      $diffstat = ($diffLines -join "; ")
    }

    if (-not [string]::IsNullOrWhiteSpace($branch)) { $state.branch = $branch }
    if (-not [string]::IsNullOrWhiteSpace($head)) { $state.head = $head }
    $state.dirty = $dirty.ToString().ToLowerInvariant()
    $state.diffstat = $diffstat
  } catch {
    # best-effort
  } finally {
    try { Pop-Location } catch { }
  }

  return "branch=$($state.branch) head=$($state.head) dirty=$($state.dirty) diffstat=$($state.diffstat)"
}

function Get-LastNextUniqueActionTail([string]$taskText) {
  if ([string]::IsNullOrWhiteSpace($taskText)) {
    return $null
  }

  $matches = [regex]::Matches($taskText, '(?m)^\s*-\s*下一步唯一动作\s*[:：]\s*(?<tail>.+?)\s*$')
  if ($matches.Count -eq 0) {
    return $null
  }

  return $matches[$matches.Count - 1].Groups["tail"].Value.Trim()
}

function Get-LastThresholdCheckpoint([string]$snapshotBody) {
  if ([string]::IsNullOrWhiteSpace($snapshotBody)) {
    return $null
  }

  $records = @()
  $current = $null
  foreach ($line in ($snapshotBody -split "`r?`n")) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
      continue
    }

    $eventMatch = [regex]::Match($trimmed, '^\-\s*\[SRC:TOOL\]\s*threshold_event\s*[:：]\s*(?<event>\S+)(?:\s+#\s*ts=(?<ts>\S+))?')
    if ($eventMatch.Success) {
      if ($null -ne $current) {
        $records += [pscustomobject]$current
      }
      $current = [ordered]@{
        event = $eventMatch.Groups["event"].Value.Trim()
        source = ""
        remaining_to_compact = $null
        ts = $eventMatch.Groups["ts"].Value.Trim()
      }
      continue
    }

    if ($null -eq $current) {
      continue
    }

    $sourceMatch = [regex]::Match($trimmed, '^\-\s*\[SRC:TOOL\]\s*threshold_source\s*[:：]\s*(?<source>\S+)')
    if ($sourceMatch.Success) {
      $current.source = $sourceMatch.Groups["source"].Value.Trim()
      continue
    }

    $remainingMatch = [regex]::Match($trimmed, '^\-\s*\[SRC:TOOL\]\s*remaining_to_compact\s*[:：]\s*(?<remaining>-?\d+)')
    if ($remainingMatch.Success) {
      $parsed = 0
      if ([int]::TryParse($remainingMatch.Groups["remaining"].Value, [ref]$parsed)) {
        $current.remaining_to_compact = $parsed
      }
      continue
    }
  }

  if ($null -ne $current) {
    $records += [pscustomobject]$current
  }

  if ($records.Count -eq 0) {
    return $null
  }

  return $records[$records.Count - 1]
}

function Test-ThresholdDuplicate($lastCheckpoint, [string]$source, [int]$remainingToCompact, [string]$timestamp) {
  if ($null -eq $lastCheckpoint) {
    return $false
  }

  if ($lastCheckpoint.source -ne $source) {
    return $false
  }

  if ($null -eq $lastCheckpoint.remaining_to_compact) {
    return $false
  }

  if ([Math]::Abs([int]$lastCheckpoint.remaining_to_compact - $remainingToCompact) -ge 2000) {
    return $false
  }

  if ([string]::IsNullOrWhiteSpace($lastCheckpoint.ts)) {
    return $true
  }

  try {
    $lastTs = [datetimeoffset]::Parse($lastCheckpoint.ts)
    $currentTs = [datetimeoffset]::Parse($timestamp)
    if ([Math]::Abs(($currentTs - $lastTs).TotalMinutes) -le 10) {
      return $true
    }
  } catch {
    return $true
  }

  return $false
}

function Append-ThresholdCheckpoint(
  [string]$snapshotBody,
  [string]$timestamp,
  [string]$source,
  [int]$usedTokens,
  [int]$autoCompactThreshold,
  [int]$remainingToCompact,
  [string]$severity,
  [string]$model,
  [string]$percentage,
  [Nullable[int]]$compactPreTokens,
  [string]$repoState,
  [string]$nextUniqueActionTail
) {
  $body = Ensure-TrailingNewline -text $snapshotBody

  $hasHeading = $body -match ('(?m)^\s*###\s*' + [regex]::Escape($H3_CONTEXT_THRESHOLD) + '\s*$')
  if (-not $hasHeading) {
    $body += ("`n### {0}`n" -f $H3_CONTEXT_THRESHOLD)
  }

  $body += "- [SRC:TOOL] threshold_event: near_autocompact # ts=$timestamp`n"
  $body += "- [SRC:TOOL] threshold_source: $source`n"
  $body += "- [SRC:TOOL] used_tokens: $usedTokens`n"
  $body += "- [SRC:TOOL] auto_compact_threshold: $autoCompactThreshold`n"
  $body += "- [SRC:TOOL] remaining_to_compact: $remainingToCompact`n"
  $body += "- [SRC:TOOL] threshold_severity: $severity`n"
  if (-not [string]::IsNullOrWhiteSpace($model)) {
    $body += "- [SRC:TOOL] model: $model`n"
  }
  if (-not [string]::IsNullOrWhiteSpace($percentage)) {
    $body += "- [SRC:TOOL] percentage: $percentage`n"
  }
  if ($null -ne $compactPreTokens) {
    $body += "- [SRC:TOOL] compact_pre_tokens: $compactPreTokens`n"
  }
  $body += "- [SRC:TOOL] repo_state: $repoState`n"
  $body += "- ${LABEL_NEXT_UNIQUE_ACTION}: $nextUniqueActionTail`n`n"

  return $body
}

$raw = Get-RawInput -inputFile $InputFile
if ([string]::IsNullOrWhiteSpace($raw)) {
  Write-Output "SKIP: no threshold payload provided."
  exit 0
}

$payload = Try-ParseJson -raw $raw
if ($null -eq $payload) {
  Write-Output "SKIP: invalid threshold payload JSON."
  exit 0
}

$projectRootResolved = Get-ProjectRootFromPayload -obj $payload -projectRootArg $ProjectRoot
if ([string]::IsNullOrWhiteSpace($projectRootResolved)) {
  Write-Output "SKIP: project root could not be resolved."
  exit 0
}

$packagePath = Resolve-CurrentPackage -projectRoot $projectRootResolved -packageArg $Package
if ([string]::IsNullOrWhiteSpace($packagePath) -or -not (Test-Path -LiteralPath $packagePath -PathType Container)) {
  Write-Output "SKIP: no active plan package."
  exit 0
}

$taskPath = Resolve-TaskFile -packagePath $packagePath
if ([string]::IsNullOrWhiteSpace($taskPath) -or -not (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
  Write-Output "SKIP: task.md not found."
  exit 0
}

$source = Get-JsonStringValue $payload @("source", "threshold_source")
if ([string]::IsNullOrWhiteSpace($source)) {
  Write-Output "SKIP: threshold source missing."
  exit 0
}

$usedTokens = Get-JsonIntValue $payload @("used_tokens")
$autoCompactThreshold = Get-JsonIntValue $payload @("auto_compact_threshold")
$remainingToCompact = Get-JsonIntValue $payload @("remaining_to_compact")
if ($null -eq $usedTokens -or $null -eq $autoCompactThreshold -or $null -eq $remainingToCompact) {
  Write-Output "SKIP: threshold payload missing used_tokens / auto_compact_threshold / remaining_to_compact."
  exit 0
}

$severity = Get-JsonStringValue $payload @("threshold_severity", "severity")
if ([string]::IsNullOrWhiteSpace($severity)) {
  $severity = if ($remainingToCompact -le 4000) { "hard" } else { "soft" }
}
$timestamp = Get-JsonStringValue $payload @("timestamp", "ts")
if ([string]::IsNullOrWhiteSpace($timestamp)) {
  $timestamp = (Get-Date).ToUniversalTime().ToString("o")
}
$model = Get-JsonStringValue $payload @("model")
$percentage = Get-JsonStringValue $payload @("percentage")
$compactPreTokens = Get-JsonIntValue $payload @("compact_pre_tokens")

$taskText = Read-Utf8Text -path $taskPath
$snapshot = Get-H2Section -text $taskText -title $H2_CONTEXT_SNAPSHOT
if ($null -eq $snapshot) {
  Write-Output "SKIP: task.md has no '## 上下文快照' section."
  exit 0
}

$lastCheckpoint = Get-LastThresholdCheckpoint -snapshotBody $snapshot.body
if (Test-ThresholdDuplicate -lastCheckpoint $lastCheckpoint -source $source -remainingToCompact $remainingToCompact -timestamp $timestamp) {
  Write-Output "OK: duplicate near-autocompact checkpoint skipped."
  exit 0
}

$repoState = Get-RepoState -projectRoot $projectRootResolved
$nextUniqueActionTail = Get-LastNextUniqueActionTail -taskText $taskText
if ([string]::IsNullOrWhiteSpace($nextUniqueActionTail)) {
  $nextUniqueActionTail = '`按 references/resume-protocol.md 恢复当前方案包，再继续当前未完成任务` 预期: 压缩后仍按磁盘检查点续作，不重开已完成任务'
}

$newBody = Append-ThresholdCheckpoint `
  -snapshotBody $snapshot.body `
  -timestamp $timestamp `
  -source $source `
  -usedTokens $usedTokens `
  -autoCompactThreshold $autoCompactThreshold `
  -remainingToCompact $remainingToCompact `
  -severity $severity `
  -model $model `
  -percentage $percentage `
  -compactPreTokens $compactPreTokens `
  -repoState $repoState `
  -nextUniqueActionTail $nextUniqueActionTail

if ($DryRun) {
  Write-Output "DRYRUN: would append near-autocompact checkpoint to '$taskPath'."
  Write-Output "- threshold_source: $source"
  Write-Output "- used_tokens: $usedTokens"
  Write-Output "- auto_compact_threshold: $autoCompactThreshold"
  Write-Output "- remaining_to_compact: $remainingToCompact"
  Write-Output "- repo_state: $repoState"
  Write-Output "- ${LABEL_NEXT_UNIQUE_ACTION}: $nextUniqueActionTail"
  exit 0
}

$newText = $snapshot.before + $newBody + $snapshot.after
Write-Utf8Text -path $taskPath -text $newText
Write-Output "OK: appended near-autocompact checkpoint to '$taskPath'."
