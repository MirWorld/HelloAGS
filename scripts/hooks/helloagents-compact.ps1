param(
  [string]$InputFile = "",
  [string]$ProjectRoot = "",
  [string]$Package = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$H2_CONTEXT_SNAPSHOT = "上下文快照"
$H3_COMPACT_LIFECYCLE = "压缩生命周期检查点（可选，结构化）"
$LABEL_NEXT_UNIQUE_ACTION = "下一步唯一动作"

function Write-HookOutputJson {
  param(
    [string]$HookEventName = "",
    [string]$HookMessage = "",
    [string]$AdditionalContext = ""
  )

  $out = [ordered]@{
    "continue" = $true
    "suppressOutput" = $true
  }

  $messageParts = @()
  if (-not [string]::IsNullOrWhiteSpace($HookEventName)) {
    $messageParts += ("hook_event_name: {0}" -f $HookEventName.Trim())
  }
  if (-not [string]::IsNullOrWhiteSpace($HookMessage)) {
    $messageParts += $HookMessage
  }
  if (-not [string]::IsNullOrWhiteSpace($AdditionalContext)) {
    $messageParts += $AdditionalContext
  }

  if ($DryRun -and $messageParts.Count -gt 0) {
    $out.systemMessage = ($messageParts -join "`n")
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

function Get-JsonStringValue($obj, [string[]]$paths) {
  foreach ($path in $paths) {
    $current = $obj
    $ok = $true
    foreach ($segment in $path.Split(".")) {
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
      $value = $current.ToString()
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value.Trim()
      }
    }
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

function Ensure-TrailingNewline([string]$text) {
  if ([string]::IsNullOrEmpty($text)) {
    return ""
  }
  if ($text.EndsWith("`n")) {
    return $text
  }
  return $text + "`n"
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

function Resolve-CurrentPackagePath([string]$projectRoot, [string]$pointerValue) {
  if ([string]::IsNullOrWhiteSpace($pointerValue)) {
    return $null
  }
  if ([System.IO.Path]::IsPathRooted($pointerValue)) {
    return $pointerValue
  }
  return (Join-Path $projectRoot $pointerValue)
}

function Resolve-CurrentPackage([string]$projectRoot, [string]$packageArg) {
  if (-not [string]::IsNullOrWhiteSpace($packageArg)) {
    $candidate = Resolve-CurrentPackagePath -projectRoot $projectRoot -pointerValue $packageArg
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  $pointerPath = Join-Path $projectRoot "HAGSWorks/plan/_current.md"
  if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
    return $null
  }

  $text = Read-Utf8Text -path $pointerPath
  $match = [regex]::Match($text, '(?m)^\s*current_package\s*:\s*(?<path>.+?)\s*$')
  if (-not $match.Success) {
    return $null
  }

  $pointerValue = $match.Groups["path"].Value.Trim()
  if ([string]::IsNullOrWhiteSpace($pointerValue)) {
    return $null
  }

  $candidatePath = Resolve-CurrentPackagePath -projectRoot $projectRoot -pointerValue $pointerValue
  $planRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "HAGSWorks/plan"))
  $candidateFull = [System.IO.Path]::GetFullPath($candidatePath)

  if (-not $candidateFull.StartsWith($planRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }
  if (-not (Test-Path -LiteralPath $candidateFull -PathType Container)) {
    return $null
  }

  return (Resolve-Path -LiteralPath $candidateFull).Path
}

function Resolve-TaskFile([string]$packagePath) {
  if ([string]::IsNullOrWhiteSpace($packagePath)) {
    return $null
  }

  $taskPath = Join-Path $packagePath "task.md"
  if (Test-Path -LiteralPath $taskPath -PathType Leaf) {
    return $taskPath
  }

  return $null
}

function Get-H2Section([string]$text, [string]$title) {
  $pattern = "(?ms)^(?<header>##\s+" + [regex]::Escape($title) + "\s*)\r?\n(?<body>.*?)(?=^##\s+|\z)"
  $match = [regex]::Match($text, $pattern)
  if (-not $match.Success) {
    return $null
  }

  return [pscustomobject]@{
    before = $text.Substring(0, $match.Groups["body"].Index)
    body = $match.Groups["body"].Value
    after = $text.Substring($match.Groups["body"].Index + $match.Groups["body"].Length)
  }
}

function Get-RepoState([string]$projectRoot) {
  $state = [ordered]@{
    branch = "unknown"
    head = "unknown"
    dirty = "unknown"
    diffstat = "unknown"
  }

  Push-Location $projectRoot
  try {
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
      $state.branch = ($branch -join "`n").Trim()
    }

    $head = (git rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($head)) {
      $state.head = ($head -join "`n").Trim()
    }

    $porcelain = (git status --porcelain 2>$null)
    if ($LASTEXITCODE -eq 0) {
      $state.dirty = if ([string]::IsNullOrWhiteSpace(($porcelain -join "`n"))) { "false" } else { "true" }
    }

    $diffstat = (git diff --stat 2>$null)
    if ($LASTEXITCODE -eq 0) {
      $diffstatText = ($diffstat -join " ").Trim()
      $state.diffstat = if ([string]::IsNullOrWhiteSpace($diffstatText)) { "none" } else { $diffstatText }
    }
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

function Get-TaskLockPath([string]$projectRoot, [string]$taskPath) {
  $locksDir = Join-Path $projectRoot "_codex_temp/locks"
  if (-not (Test-Path -LiteralPath $locksDir -PathType Container)) {
    New-Item -ItemType Directory -Path $locksDir -Force | Out-Null
  }

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($taskPath.ToLowerInvariant())
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally {
    $sha.Dispose()
  }

  return (Join-Path $locksDir ("task-" + $hash.Substring(0, 16) + ".lock"))
}

function Invoke-WithTaskFileLock([string]$lockPath, [scriptblock]$body) {
  $stream = $null
  try {
    $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $result = & $body
    return [pscustomobject]@{
      acquired = $true
      value = $result
    }
  } catch [System.IO.IOException] {
    return [pscustomobject]@{
      acquired = $false
      value = "SKIP: task.md lock busy; compact checkpoint not appended."
    }
  } finally {
    if ($null -ne $stream) {
      $stream.Dispose()
    }
  }
}

function Test-CompactDuplicate([string]$snapshotBody, [string]$eventName, [string]$turnId) {
  if ([string]::IsNullOrWhiteSpace($snapshotBody)) {
    return $false
  }

  $eventPattern = '(?im)^\s*-\s*\[SRC:TOOL\]\s*compact_event\s*[:：]\s*' + [regex]::Escape($eventName) + '\b'
  if (-not ([regex]::IsMatch($snapshotBody, $eventPattern))) {
    return $false
  }

  if ([string]::IsNullOrWhiteSpace($turnId)) {
    return $true
  }

  $turnPattern = '(?im)^\s*-\s*\[SRC:TOOL\]\s*turn_id\s*[:：]\s*' + [regex]::Escape($turnId) + '\s*$'
  return [regex]::IsMatch($snapshotBody, $turnPattern)
}

function Append-CompactCheckpoint(
  [string]$snapshotBody,
  [string]$timestamp,
  [string]$eventName,
  [string]$trigger,
  [string]$sessionId,
  [string]$turnId,
  [string]$model,
  [string]$repoState,
  [string]$nextUniqueActionTail
) {
  $body = Ensure-TrailingNewline -text $snapshotBody
  $hasHeading = $body -match ('(?m)^\s*###\s*' + [regex]::Escape($H3_COMPACT_LIFECYCLE) + '\s*$')
  if (-not $hasHeading) {
    $body += ("`n### {0}`n" -f $H3_COMPACT_LIFECYCLE)
  }

  $body += "- [SRC:TOOL] compact_event: $eventName # ts=$timestamp`n"
  if (-not [string]::IsNullOrWhiteSpace($trigger)) {
    $body += "- [SRC:TOOL] compact_trigger: $trigger`n"
  }
  if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
    $body += "- [SRC:TOOL] session_id: $sessionId`n"
  }
  if (-not [string]::IsNullOrWhiteSpace($turnId)) {
    $body += "- [SRC:TOOL] turn_id: $turnId`n"
  }
  if (-not [string]::IsNullOrWhiteSpace($model)) {
    $body += "- [SRC:TOOL] model: $model`n"
  }
  $body += "- [SRC:TOOL] repo_state: $repoState`n"
  $body += "- ${LABEL_NEXT_UNIQUE_ACTION}: $nextUniqueActionTail`n`n"

  return $body
}

$raw = Get-RawInput -inputFile $InputFile
if ([string]::IsNullOrWhiteSpace($raw)) {
  Write-HookOutputJson -HookEventName "PreCompact" -HookMessage "SKIP: no compact payload provided."
  exit 0
}

$payload = Try-ParseJson -raw $raw
if ($null -eq $payload) {
  Write-HookOutputJson -HookEventName "PreCompact" -HookMessage "SKIP: invalid compact payload JSON."
  exit 0
}

$hookEventName = Get-JsonStringValue $payload @("hook_event_name", "hookEventName")
if ([string]::IsNullOrWhiteSpace($hookEventName)) {
  $hookEventName = "PreCompact"
}

if ($hookEventName -notin @("PreCompact", "PostCompact")) {
  Write-HookOutputJson -HookEventName $hookEventName -HookMessage ("SKIP: unsupported compact hook event '{0}'." -f $hookEventName)
  exit 0
}

$eventName = if ($hookEventName -eq "PostCompact") { "post_compact" } else { "pre_compact" }
$projectRootResolved = Get-ProjectRootFromPayload -obj $payload -projectRootArg $ProjectRoot
if ([string]::IsNullOrWhiteSpace($projectRootResolved)) {
  Write-HookOutputJson -HookEventName $hookEventName -HookMessage "SKIP: project root could not be resolved."
  exit 0
}

$packagePath = Resolve-CurrentPackage -projectRoot $projectRootResolved -packageArg $Package
if ([string]::IsNullOrWhiteSpace($packagePath) -or -not (Test-Path -LiteralPath $packagePath -PathType Container)) {
  Write-HookOutputJson -HookEventName $hookEventName -HookMessage "SKIP: no active plan package."
  exit 0
}

$taskPath = Resolve-TaskFile -packagePath $packagePath
if ([string]::IsNullOrWhiteSpace($taskPath) -or -not (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
  Write-HookOutputJson -HookEventName $hookEventName -HookMessage "SKIP: task.md not found."
  exit 0
}

$timestamp = Get-JsonStringValue $payload @("timestamp", "ts")
if ([string]::IsNullOrWhiteSpace($timestamp)) {
  $timestamp = (Get-Date).ToUniversalTime().ToString("o")
}

$trigger = Get-JsonStringValue $payload @("trigger")
$sessionId = Get-JsonStringValue $payload @("session_id", "sessionId")
$turnId = Get-JsonStringValue $payload @("turn_id", "turnId")
$model = Get-JsonStringValue $payload @("model")

$lockPath = Get-TaskLockPath -projectRoot $projectRootResolved -taskPath $taskPath
$lockResult = Invoke-WithTaskFileLock -lockPath $lockPath -body {
  $taskText = Read-Utf8Text -path $taskPath
  $snapshot = Get-H2Section -text $taskText -title $H2_CONTEXT_SNAPSHOT
  if ($null -eq $snapshot) {
    return "SKIP: task.md has no '## 上下文快照' section."
  }

  if (Test-CompactDuplicate -snapshotBody $snapshot.body -eventName $eventName -turnId $turnId) {
    return ("OK: duplicate {0} checkpoint skipped." -f $eventName)
  }

  $repoState = Get-RepoState -projectRoot $projectRootResolved
  $nextUniqueActionTail = Get-LastNextUniqueActionTail -taskText $taskText
  if ([string]::IsNullOrWhiteSpace($nextUniqueActionTail)) {
    $nextUniqueActionTail = '`按 references/resume-protocol.md 恢复当前方案包，再继续当前未完成任务` 预期: 压缩后仍按磁盘检查点续作，不重开已完成任务'
  }

  $newBody = Append-CompactCheckpoint `
    -snapshotBody $snapshot.body `
    -timestamp $timestamp `
    -eventName $eventName `
    -trigger $trigger `
    -sessionId $sessionId `
    -turnId $turnId `
    -model $model `
    -repoState $repoState `
    -nextUniqueActionTail $nextUniqueActionTail

  if ($DryRun) {
    return @(
      ("DRYRUN: would append {0} checkpoint to '{1}'." -f $eventName, $taskPath),
      "- compact_event: $eventName",
      "- compact_trigger: $trigger",
      "- session_id: $sessionId",
      "- turn_id: $turnId",
      "- repo_state: $repoState",
      "- ${LABEL_NEXT_UNIQUE_ACTION}: $nextUniqueActionTail"
    ) -join "`n"
  }

  $newText = $snapshot.before + $newBody + $snapshot.after
  Write-Utf8Text -path $taskPath -text $newText
  return ("OK: appended {0} checkpoint to '{1}'." -f $eventName, $taskPath)
}

if (-not $lockResult.acquired) {
  Write-HookOutputJson -HookEventName $hookEventName -HookMessage $lockResult.value
  exit 0
}

$additionalContext = @(
  "compact_event: $eventName",
  "compact_trigger: $trigger",
  "current_package: $packagePath",
  "next_unique_action: 压缩后优先读取 task.md##上下文快照 的最新 compact_event/repo_state/下一步唯一动作"
) -join "`n"

Write-HookOutputJson -HookEventName $hookEventName -HookMessage $lockResult.value -AdditionalContext $additionalContext
