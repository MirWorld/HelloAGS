param(
  [string]$InputFile = "",
  [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

function Write-HookOutputJson {
  param(
    [string]$Decision = "",
    [string]$Reason = "",
    [string]$SystemMessage = "",
    [string]$AdditionalContext = ""
  )

  $out = [ordered]@{}
  if (-not [string]::IsNullOrWhiteSpace($Decision)) {
    $out.decision = $Decision.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($Reason)) {
    $out.reason = $Reason.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($SystemMessage)) {
    $out.systemMessage = $SystemMessage.Trim()
  }

  $hookSpecific = [ordered]@{}
  if (-not [string]::IsNullOrWhiteSpace($AdditionalContext)) {
    $hookSpecific.hookEventName = "PreToolUse"
    $hookSpecific.additionalContext = $AdditionalContext
  }
  if ($hookSpecific.Count -gt 0) {
    $out.hookSpecificOutput = $hookSpecific
  }

  ($out | ConvertTo-Json -Depth 64 -Compress) | Write-Output
}

function Get-RawInput([string]$inputFile) {
  if (-not [string]::IsNullOrWhiteSpace($inputFile)) {
    if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
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

function Resolve-FullPath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) {
    return ""
  }

  try {
    return [System.IO.Path]::GetFullPath($path)
  } catch {
    return ""
  }
}

function Get-ProjectRootFromPayload($obj, [string]$projectRootArg) {
  $fallback = (Get-Location).Path
  $payloadCwd = Get-JsonStringValue $obj @("cwd", "project_root", "projectRoot", "workspace_root", "workspaceRoot", "session.cwd")
  $candidates = @($projectRootArg, $payloadCwd) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    $candidatePath = $candidate
    if ($candidatePath -eq "__PROJECT_ROOT__") {
      $candidatePath = $fallback
    }
    if (Test-Path -LiteralPath $candidatePath -PathType Container) {
      return (Resolve-Path -LiteralPath $candidatePath).Path
    }
  }

  if (Test-Path -LiteralPath $fallback -PathType Container) {
    return (Resolve-Path -LiteralPath $fallback).Path
  }

  return $null
}

function Test-IsPathUnderDirectory([string]$path, [string]$directory) {
  $fullPath = Resolve-FullPath $path
  $fullDirectory = Resolve-FullPath $directory
  if ([string]::IsNullOrWhiteSpace($fullPath) -or [string]::IsNullOrWhiteSpace($fullDirectory)) {
    return $false
  }

  $separator = [System.IO.Path]::DirectorySeparatorChar
  $altSeparator = [System.IO.Path]::AltDirectorySeparatorChar
  if (-not ($fullDirectory.EndsWith($separator) -or $fullDirectory.EndsWith($altSeparator))) {
    $fullDirectory = $fullDirectory + $separator
  }

  return $fullPath.StartsWith($fullDirectory, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-PackagePath([string]$projectRoot, [string]$pointerValue) {
  if ([string]::IsNullOrWhiteSpace($pointerValue)) {
    return $null
  }
  if ([System.IO.Path]::IsPathRooted($pointerValue)) {
    return $pointerValue
  }
  return Join-Path $projectRoot $pointerValue
}

function Get-CurrentPackageInfo([string]$projectRoot) {
  $pointerFile = Join-Path $projectRoot "HAGSWorks/plan/_current.md"
  if (-not (Test-Path -LiteralPath $pointerFile -PathType Leaf)) {
    return $null
  }

  $pointerText = Read-Utf8Text -path $pointerFile
  $match = [regex]::Match($pointerText, '(?m)^\s*current_package\s*:\s*(?<path>.*)\s*$')
  if (-not $match.Success) {
    return $null
  }

  $rawPointer = [regex]::Replace($match.Groups["path"].Value, '\s+#.*$', '').Trim()
  if ([string]::IsNullOrWhiteSpace($rawPointer)) {
    return $null
  }

  $packagePath = Resolve-PackagePath -projectRoot $projectRoot -pointerValue $rawPointer
  $planRoot = Join-Path $projectRoot "HAGSWorks/plan"
  if (-not (Test-IsPathUnderDirectory -path $packagePath -directory $planRoot)) {
    return $null
  }
  if (-not (Test-Path -LiteralPath $packagePath -PathType Container)) {
    return $null
  }
  foreach ($requiredFile in @("why.md", "how.md", "task.md")) {
    if (-not (Test-Path -LiteralPath (Join-Path $packagePath $requiredFile) -PathType Leaf)) {
      return $null
    }
  }

  return [pscustomobject]@{
    pointer = $rawPointer
    full_path = (Resolve-Path -LiteralPath $packagePath).Path
    task_path = (Resolve-Path -LiteralPath (Join-Path $packagePath "task.md")).Path
  }
}

function Get-SnapshotBody([string]$taskText) {
  if ([string]::IsNullOrWhiteSpace($taskText)) {
    return ""
  }

  $match = [regex]::Match($taskText, '(?ms)^\s*##\s*上下文快照\s*$\r?\n(?<body>.*?)(?=^\s*##\s+|\z)')
  if (-not $match.Success) {
    return ""
  }
  return $match.Groups["body"].Value
}

function Test-UnresolvedPostCompact([string]$taskText) {
  $snapshotBody = Get-SnapshotBody -taskText $taskText
  if ([string]::IsNullOrWhiteSpace($snapshotBody)) {
    return $false
  }

  $eventMatches = [regex]::Matches($snapshotBody, '(?im)^\s*-\s*\[SRC:TOOL\]\s*compact_event\s*[:：]\s*(?<kind>\S+)(?:\s+#.*)?\s*$')
  if ($eventMatches.Count -eq 0) {
    return $false
  }

  $lastPostCompact = $null
  foreach ($eventMatch in $eventMatches) {
    $kind = [regex]::Replace($eventMatch.Groups["kind"].Value, '^[`"'',;]+|[`"'',;]+$', '')
    if ($kind -match '(?i)^post_compact\b') {
      $lastPostCompact = $eventMatch
    }
  }
  if ($null -eq $lastPostCompact) {
    return $false
  }

  $after = ""
  try {
    $start = [Math]::Min($snapshotBody.Length, $lastPostCompact.Index + $lastPostCompact.Length)
    $after = $snapshotBody.Substring($start)
  } catch {
    $after = ""
  }

  $hasRepoAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?repo_state\s*[:：]\s*\S')
  $hasNextAfter = ($after -match '(?im)^\s*-\s*下一步唯一动作\s*[:：]\s*\S')
  $hasHydrationRequiredAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?resume_hydration_required\s*[:：]\s*yes\b')
  $hasHydratedFromPackageAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?hydrated_from_package\s*[:：]\s*\S')
  $hasHydrationSourceAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?hydration_source\s*[:：]\s*`?_current\.md\s*\+\s*task\.md\s*\+\s*repo_state`?\b')
  $hasRebootOkAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?reboot_check\s*[:：]\s*ok\b')
  $hasContractAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?contract_checkpoint\s*[:：]\s*ok\b')

  return (-not ($hasRepoAfter -and $hasNextAfter -and $hasHydrationRequiredAfter -and $hasHydratedFromPackageAfter -and $hasHydrationSourceAfter -and $hasRebootOkAfter -and $hasContractAfter))
}

function Convert-JsonValueToText($value) {
  if ($null -eq $value) {
    return ""
  }
  if ($value -is [string]) {
    return $value
  }
  if ($value -is [System.ValueType]) {
    return $value.ToString()
  }

  try {
    return (($value | ConvertTo-Json -Depth 64 -Compress) | Out-String)
  } catch {
    return $value.ToString()
  }
}

function Get-ToolName($payload) {
  return (Get-JsonStringValue $payload @("tool_name", "toolName"))
}

function Get-ToolCommand($payload) {
  $command = Get-JsonStringValue $payload @("tool_input.command", "toolInput.command", "tool_input.cmd", "toolInput.cmd", "tool_input.shell_command", "toolInput.shell_command")
  if (-not [string]::IsNullOrWhiteSpace($command)) {
    return $command
  }

  try {
    return Convert-JsonValueToText $payload.tool_input
  } catch {
    return ""
  }
}

function Normalize-PathText([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) {
    return ""
  }
  return ($text -replace '\\', '/').ToLowerInvariant()
}

function Test-CommandHasShellChaining([string]$command) {
  return ($command -match '(?i)(;|\&\&|\|\||\|\s*(?!select-string\b)|>\s*|>>\s*)')
}

function Test-CommandMentionsAllowedHydrationPath([string]$command, $packageInfo) {
  $normalizedCommand = Normalize-PathText $command
  $normalizedPointer = Normalize-PathText ([string]$packageInfo.pointer)
  $normalizedPackageFullPath = Normalize-PathText ([string]$packageInfo.full_path)
  $allowedPointerFile = "hagsworks/plan/_current.md"

  if ($normalizedCommand.Contains($allowedPointerFile)) {
    return $true
  }
  if (-not [string]::IsNullOrWhiteSpace($normalizedPointer) -and $normalizedCommand.Contains($normalizedPointer)) {
    return $true
  }
  if (-not [string]::IsNullOrWhiteSpace($normalizedPackageFullPath) -and $normalizedCommand.Contains($normalizedPackageFullPath)) {
    return $true
  }

  return $false
}

function Test-AllowedGitHydrationCommand([string]$command) {
  if ([string]::IsNullOrWhiteSpace($command)) {
    return $false
  }
  if (Test-CommandHasShellChaining -command $command) {
    return $false
  }

  $trimmedCommand = $command.Trim()
  return (
    ($trimmedCommand -match '(?i)^git\s+status\b') -or
    ($trimmedCommand -match '(?i)^git\s+rev-parse\b') -or
    ($trimmedCommand -match '(?i)^git\s+diff\s+(?:--stat|--shortstat)\b')
  )
}

function Test-AllowedHydrationReadCommand([string]$command, $packageInfo) {
  if ([string]::IsNullOrWhiteSpace($command)) {
    return $false
  }
  if (Test-CommandHasShellChaining -command $command) {
    return $false
  }
  if (-not (Test-CommandMentionsAllowedHydrationPath -command $command -packageInfo $packageInfo)) {
    return $false
  }

  $allowedReadVerb = '(?i)\b(Get-Content|gc|type|cat|Select-String|rg|Test-Path|Get-Item|Get-ChildItem|dir|ls)\b'
  $writeOrExecuteSignal = '(?i)\b(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|apply_patch|npm|pnpm|yarn|pytest|cargo|go\s+test|dotnet|mvn|gradle|make)\b'
  return (($command -match $allowedReadVerb) -and -not ($command -match $writeOrExecuteSignal))
}

function Test-AllowedHydrationTaskWrite([string]$toolText, $packageInfo) {
  if ([string]::IsNullOrWhiteSpace($toolText)) {
    return $false
  }
  if (Test-CommandHasShellChaining -command $toolText) {
    return $false
  }
  if (-not (Test-CommandMentionsAllowedHydrationPath -command $toolText -packageInfo $packageInfo)) {
    return $false
  }

  $normalizedText = Normalize-PathText $toolText
  if (-not $normalizedText.Contains("task.md")) {
    return $false
  }
  return (
    ($toolText -match '(?im)\breboot_check\s*[:：]\s*ok\b') -or
    ($toolText -match '(?im)\bcontract_checkpoint\s*[:：]\s*ok\b') -or
    ($toolText -match '(?im)\bhydration_source\s*[:：]\s*_current\.md\s*\+\s*task\.md\s*\+\s*repo_state\b')
  )
}

function Test-ShellToolName([string]$toolName) {
  return ($toolName -match '(?i)^(Bash|Shell|shell|exec_command|bash|sh|powershell|pwsh)$')
}

function Test-WriteToolName([string]$toolName) {
  return ($toolName -match '(?i)(apply_patch|write|edit|filesystem-edit|filesystem-write|multi_tool_use)')
}

function Test-ReadToolName([string]$toolName) {
  return ($toolName -match '(?i)^(Read|filesystem-read|open|view|read_file|get_file)$')
}

function New-HydrationContext([string]$packagePointer, [string]$turnId) {
  $lines = @(
    "[HelloAGENTS Guard] 当前方案包存在未恢复的 post_compact；工具调用已进入 hydration_only。",
    ("current_package: {0}" -f $packagePointer)
  )
  if (-not [string]::IsNullOrWhiteSpace($turnId)) {
    $lines += ("current_turn_id: {0}" -f $turnId)
  }
  $lines += "signal: compact_resume_required"
  $lines += "severity: Red"
  $lines += "mode: hydration_only"
  $lines += "resume_hydration_required: yes"
  $lines += "reboot_check: required"
  $lines += "hydration_source: _current.md + task.md + repo_state"
  $lines += "allowed_reads: HAGSWorks/plan/_current.md; current package why.md/how.md/task.md; git status/rev-parse/diff --stat"
  $lines += "allowed_write: current package task.md recovery checkpoint only"
  $lines += "forbidden: business_files; code_changes; verify_commands; temporary_replan"
  $lines += "next_unique_action: 读取 _current.md + task.md + repo_state 并执行 Reboot Check；写入 reboot_check: ok + contract_checkpoint: ok 后再进入 develop"
  return ($lines -join "`n")
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

$packageInfo = Get-CurrentPackageInfo -projectRoot $projectRootResolved
if ($null -eq $packageInfo) {
  Write-HookOutputJson
  exit 0
}

$taskText = Read-Utf8Text -path ([string]$packageInfo.task_path)
if (-not (Test-UnresolvedPostCompact -taskText $taskText)) {
  Write-HookOutputJson
  exit 0
}

$toolName = Get-ToolName $payload
$toolCommand = Get-ToolCommand $payload
$toolInputText = ""
try {
  $toolInputText = Convert-JsonValueToText $payload.tool_input
} catch {
  $toolInputText = ""
}
$turnId = Get-JsonStringValue $payload @("turn_id", "turnId")
$additionalContext = New-HydrationContext -packagePointer ([string]$packageInfo.pointer) -turnId $turnId

$allowed = $false
if (Test-ShellToolName -toolName $toolName) {
  $allowed = (
    (Test-AllowedGitHydrationCommand -command $toolCommand) -or
    (Test-AllowedHydrationReadCommand -command $toolCommand -packageInfo $packageInfo) -or
    (Test-AllowedHydrationTaskWrite -toolText $toolCommand -packageInfo $packageInfo)
  )
} elseif (Test-WriteToolName -toolName $toolName) {
  $allowed = Test-AllowedHydrationTaskWrite -toolText $toolInputText -packageInfo $packageInfo
} elseif (Test-ReadToolName -toolName $toolName) {
  $allowed = Test-CommandMentionsAllowedHydrationPath -command $toolInputText -packageInfo $packageInfo
}

if ($allowed) {
  Write-HookOutputJson -AdditionalContext $additionalContext
  exit 0
}

$reason = "compact_resume_required: 当前方案包存在未恢复的 post_compact；Hydration 完成前禁止读取业务文件、改代码、跑验证或临时重规划。请先读取 _current.md + task.md + repo_state，并写入 reboot_check: ok + contract_checkpoint: ok。"
Write-HookOutputJson `
  -Decision "block" `
  -Reason $reason `
  -SystemMessage "当前工具调用已被 HelloAGENTS PreToolUse 守卫阻断：压缩恢复未完成。" `
  -AdditionalContext $additionalContext
