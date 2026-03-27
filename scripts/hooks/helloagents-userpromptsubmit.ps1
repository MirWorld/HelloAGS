param(
  [string]$InputFile = "",
  [string]$ProjectRoot = "",
  [string]$Package = ""
)

$ErrorActionPreference = "Stop"

function Write-HookOutputJson {
  param(
    [string]$SystemMessage = "",
    [string]$Decision = "",
    [string]$Reason = "",
    [string]$AdditionalContext = "",
    [string]$HookMessage = ""
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
  if (-not [string]::IsNullOrWhiteSpace($AdditionalContext)) {
    $hookSpecific.hookEventName = "UserPromptSubmit"
    $hookSpecific.additionalContext = $AdditionalContext
  }
  if (-not [string]::IsNullOrWhiteSpace($HookMessage)) {
    if (-not $hookSpecific.Contains("hookEventName")) {
      $hookSpecific.hookEventName = "UserPromptSubmit"
    }
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

    if ($ok -and $null -ne $current) {
      $value = $current.ToString()
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value.Trim()
      }
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

function Get-PromptFromPayload($obj) {
  return (Get-JsonStringValue $obj @("prompt", "user_prompt", "userPrompt", "payload.prompt", "payload.user_prompt", "payload.userPrompt"))
}

function Get-TurnIdFromPayload($obj) {
  return (Get-JsonStringValue $obj @("turn_id", "turnId", "payload.turn_id", "payload.turnId", "session.turn_id", "session.turnId", "metadata.turn_id", "metadata.turnId"))
}

function Resolve-PackagePath([string]$projectRoot, [string]$pointerValue) {
  if ([string]::IsNullOrWhiteSpace($pointerValue)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($pointerValue)) {
    return $pointerValue
  }

  return (Join-Path $projectRoot $pointerValue)
}

function Get-CurrentPackageFromPointer([string]$projectRoot) {
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
    return ""
  }

  return $rawPointer
}

function Test-CompletePackage([string]$packageFullPath) {
  if ([string]::IsNullOrWhiteSpace($packageFullPath)) {
    return $false
  }
  if (-not (Test-Path -LiteralPath $packageFullPath -PathType Container)) {
    return $false
  }

  foreach ($name in @("why.md", "how.md", "task.md")) {
    $full = Join-Path $packageFullPath $name
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
      return $false
    }
  }

  return $true
}

function Extract-SectionBody([string]$text, [string]$headerText) {
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $null
  }

  $headerEsc = [regex]::Escape($headerText)
  $pattern = "(?ms)^\s*${headerEsc}\s*$\s*(?<body>.*?)(?=^\s*###\s+|\z)"
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) {
    return $null
  }
  return $m.Groups["body"].Value
}

function Get-SignificantLines([string]$text, [int]$maxLines = 20) {
  $lines = @()
  foreach ($line in ($text -split "`r?`n")) {
    $t = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) {
      continue
    }
    if ($t.StartsWith("<!--")) {
      continue
    }
    $lines += $t
    if ($lines.Count -ge $maxLines) {
      break
    }
  }
  return $lines
}

function Get-NextUniqueAction([string]$taskText) {
  if ([string]::IsNullOrWhiteSpace($taskText)) {
    return $null
  }

  $matches = [regex]::Matches($taskText, '(?m)^\s*-\s*下一步唯一动作\s*:\s*(?<v>.+?)\s*$')
  if ($matches.Count -eq 0) {
    return $null
  }
  return $matches[$matches.Count - 1].Groups["v"].Value.Trim()
}

function Get-FeatureRemovalApprovalState([string[]]$texts) {
  $state = "no"
  foreach ($text in $texts) {
    if ([string]::IsNullOrWhiteSpace($text)) {
      continue
    }

    $matches = [regex]::Matches($text, '(?im)feature_removal_approved\s*:\s*(?<v>yes|no)\b')
    if ($matches.Count -gt 0) {
      $state = $matches[$matches.Count - 1].Groups["v"].Value.Trim().ToLowerInvariant()
    }
  }

  return $state
}

function Get-MetadataFieldValue([string[]]$texts, [string]$fieldName) {
  foreach ($text in $texts) {
    if ([string]::IsNullOrWhiteSpace($text)) {
      continue
    }

    foreach ($line in ($text -split "`r?`n")) {
      $trimmed = $line.Trim()
      if (-not $trimmed.StartsWith("-")) {
        continue
      }

      $trimmed = $trimmed.Substring(1).Trim()
      $trimmed = $trimmed.Trim([char]0x60).Trim()
      if (-not $trimmed.StartsWith($fieldName, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
      }

      $colon = $trimmed.IndexOf(":")
      if ($colon -lt 0) {
        continue
      }

      $value = $trimmed.Substring($colon + 1).Trim().Trim([char]0x60).Trim()
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
      }
    }
  }

  return ""
}

function Test-FeatureRemovalRiskFromPrompt([string]$prompt) {
  if ([string]::IsNullOrWhiteSpace($prompt)) {
    return $false
  }

  $patterns = @(
    '(?i)\b(remove|delete|drop|disable|deprecate|hide|turn\s+off)\b',
    '删除',
    '移除',
    '去掉',
    '去除',
    '禁用',
    '隐藏',
    '下线',
    '砍掉',
    '缩减'
  )

  foreach ($pattern in $patterns) {
    if ($prompt -match $pattern) {
      return $true
    }
  }

  return $false
}

function Test-FeatureRemovalGuardShouldInject(
  [string]$approvalState,
  [string]$taskText,
  [string]$howText,
  [string]$pendingBody,
  [string]$nextUniqueAction,
  [string]$promptTrimmed
) {
  if ($approvalState -eq "yes") {
    return $false
  }

  $stateTexts = @($taskText, $howText) -join "`n"
  if ($stateTexts -match '(?i)\bawaiting_topic\s*:\s*feature_removal_guard\b') {
    return $true
  }

  $liveSignalTexts = @($pendingBody, $nextUniqueAction, $promptTrimmed) -join "`n"
  if ($liveSignalTexts -match '功能删减') {
    return $true
  }
  if ($liveSignalTexts -match '(?i)\bfeature[_-]?removal\b') {
    return $true
  }

  foreach ($fieldName in @("approved_scope", "approved_target", "approved_reason", "replacement_behavior", "fallback_if_rejected")) {
    $value = Get-MetadataFieldValue -texts @($taskText, $howText) -fieldName $fieldName
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return $true
    }
  }

  return (Test-FeatureRemovalRiskFromPrompt -prompt $promptTrimmed)
}

function Build-FeatureRemovalGuardLines([string]$approvalState, [string]$packagePointer) {
  if ($approvalState -eq "yes") {
    return @()
  }

  $lines = @()
  $lines += "[HelloAGENTS Guard] 默认保留用户可见表面、公开契约与默认能力；未获 [SRC:USER] 明确批准前，不得删除、隐藏、禁用、短路或降级这些能力。"
  $lines += "[HelloAGENTS Guard] 若只是死代码/不可达分支/未使用 helper 清理，且外部行为与公开契约不变，可按内部清理处理。"
  $lines += ("feature_removal_approved: {0}" -f $approvalState)
  if (-not [string]::IsNullOrWhiteSpace($packagePointer)) {
    $lines += ("feature_removal_package: {0}" -f $packagePointer)
  }
  return $lines
}

try {
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

  $prompt = (Get-PromptFromPayload -obj $payload)
  if ($null -eq $prompt) {
    $prompt = ""
  }
  $promptTrimmed = $prompt.Trim()
  $turnId = Get-TurnIdFromPayload -obj $payload

  $packagePointer = $null
  if (-not [string]::IsNullOrWhiteSpace($Package)) {
    $packagePointer = $Package.Trim()
  } else {
    $packagePointer = Get-CurrentPackageFromPointer -projectRoot $projectRootResolved
  }

  if ($null -eq $packagePointer) {
    Write-HookOutputJson
    exit 0
  }

  if ([string]::IsNullOrWhiteSpace($packagePointer)) {
    Write-HookOutputJson
    exit 0
  }

  $packagePath = Resolve-PackagePath -projectRoot $projectRootResolved -pointerValue $packagePointer
  $packageFull = $null
  try { $packageFull = [System.IO.Path]::GetFullPath($packagePath) } catch { $packageFull = $null }

  if (-not (Test-CompletePackage -packageFullPath $packageFull)) {
    $msg = "当前 current_package 指针无效或方案包不完整，已阻断以避免跑偏/重做。"
    $reason = "请先修复 `HAGSWorks/plan/_current.md` 指针或重新选择有效方案包（why/how/task齐全），再继续对话。"
    Write-HookOutputJson -SystemMessage $msg -Decision "block" -Reason $reason
    exit 0
  }

  $taskFile = Join-Path $packageFull "task.md"
  $howFile = Join-Path $packageFull "how.md"
  $taskText = Read-Utf8Text -path $taskFile
  $howText = ""
  if (Test-Path -LiteralPath $howFile -PathType Leaf) {
    $howText = Read-Utf8Text -path $howFile
  }
  $pendingBody = Extract-SectionBody -text $taskText -headerText "### 待用户输入（Pending）"
  $pendingLines = @()
  if ($null -ne $pendingBody) {
    $pendingLines = @(Get-SignificantLines -text $pendingBody -maxLines 20)
  }
  $nextUniqueAction = Get-NextUniqueAction -taskText $taskText
  $featureRemovalApproval = Get-FeatureRemovalApprovalState -texts @($taskText, $howText)
  $shouldInjectFeatureRemovalGuard = Test-FeatureRemovalGuardShouldInject `
    -approvalState $featureRemovalApproval `
    -taskText $taskText `
    -howText $howText `
    -pendingBody $pendingBody `
    -nextUniqueAction $nextUniqueAction `
    -promptTrimmed $promptTrimmed
  $featureRemovalGuardLines = @()
  if ($shouldInjectFeatureRemovalGuard) {
    $featureRemovalGuardLines = @(Build-FeatureRemovalGuardLines -approvalState $featureRemovalApproval -packagePointer $packagePointer)
  }

  $additionalContextLines = @()
  if ($pendingLines.Count -gt 0) {
    $additionalContextLines += "[HelloAGENTS Guard] 检测到待用户输入（Pending），本轮必须只处理用户回复，禁止进入执行/重开流程。"
    $additionalContextLines += ("current_package: {0}" -f $packagePointer)
    if (-not [string]::IsNullOrWhiteSpace($turnId)) {
      $additionalContextLines += ("current_turn_id: {0}" -f $turnId)
    }
    if (-not [string]::IsNullOrWhiteSpace($nextUniqueAction)) {
      $additionalContextLines += ("next_unique_action: {0}" -f $nextUniqueAction)
    }
    $additionalContextLines += "pending:"
    foreach ($line in $pendingLines) {
      $additionalContextLines += ("- {0}" -f $line)
    }
  }
  if ($featureRemovalGuardLines.Count -gt 0) {
    if ($additionalContextLines.Count -gt 0) {
      $additionalContextLines += ""
    }
    if (-not [string]::IsNullOrWhiteSpace($turnId) -and -not ($additionalContextLines -contains ("current_turn_id: {0}" -f $turnId))) {
      $additionalContextLines += ("current_turn_id: {0}" -f $turnId)
    }
    $additionalContextLines += $featureRemovalGuardLines
  }

  if ($pendingLines.Count -eq 0 -and $featureRemovalGuardLines.Count -eq 0) {
    Write-HookOutputJson
    exit 0
  }

  $additionalContext = ($additionalContextLines -join "`n")
  if ($additionalContext.Length -gt 2400) {
    $additionalContext = $additionalContext.Substring(0, 2400) + "`n…(truncated)"
  }

  if ($pendingLines.Count -gt 0 -and $promptTrimmed.StartsWith("~")) {
    $msg = "当前处于 Pending（等待你回复上一轮问题/选择/确认），为避免跑偏已阻断命令执行。"
    $reason = "请先按回复契约回答（或回复 `取消` 结束等待），再执行其它命令/发起新需求。"
    Write-HookOutputJson -SystemMessage $msg -Decision "block" -Reason $reason -AdditionalContext $additionalContext
    exit 0
  }

  if ($pendingLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($promptTrimmed)) {
    $msg = "输入为空且当前处于 Pending，已阻断以避免误触发。"
    $reason = "请按回复契约输入有效回复；如需结束等待，回复 `取消`。"
    Write-HookOutputJson -SystemMessage $msg -Decision "block" -Reason $reason -AdditionalContext $additionalContext
    exit 0
  }

  Write-HookOutputJson -AdditionalContext $additionalContext
  exit 0
} catch {
  Write-HookOutputJson
  exit 0
}
