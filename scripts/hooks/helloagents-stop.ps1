param(
  [string]$InputFile = "",
  [string]$ProjectRoot = "",
  [string]$Package = "",
  [switch]$DryRun
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

function Parse-HelloAgentsState([string]$message) {
  if ([string]::IsNullOrWhiteSpace($message)) {
    return $null
  }

  $m = [regex]::Match($message, '(?ms)<helloagents_state>\s*(?<body>.*?)\s*</helloagents_state>')
  if (-not $m.Success) {
    return $null
  }

  $kv = @{}
  foreach ($line in ($m.Groups["body"].Value -split "`r?`n")) {
    $t = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) {
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

  if ($kv.Count -eq 0) {
    return $null
  }

  return $kv
}

function Get-FeatureRemovalWaitInfo($obj) {
  $message = Get-JsonStringValue $obj @("last_assistant_message", "lastAssistantMessage", "payload.last_assistant_message", "payload.lastAssistantMessage")
  if ([string]::IsNullOrWhiteSpace($message)) {
    return $null
  }

  $state = Parse-HelloAgentsState -message $message
  if ($null -eq $state) {
    return $null
  }

  $status = ""
  $topic = ""
  $nextAction = ""
  $package = ""
  if ($state.ContainsKey("status")) { $status = $state["status"] }
  if ($state.ContainsKey("awaiting_topic")) { $topic = $state["awaiting_topic"] }
  if ($state.ContainsKey("next_unique_action")) { $nextAction = $state["next_unique_action"] }
  if ($state.ContainsKey("package")) { $package = $state["package"] }

  if ($status -ne "awaiting_user_input") {
    return $null
  }
  if ($topic -ne "feature_removal_guard") {
    return $null
  }

  return [pscustomobject]@{
    topic = $topic
    next_unique_action = $nextAction
    package = $package
  }
}

function Normalize-EventKind([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $null
  }

  $v = $value.Trim()
  if ($v -match '(?i)\bmodel[/_.-]?rerouted\b' -or $v -match '(?i)\brerouted\b' -or $v -match '(?i)\bfallback\b') {
    return "model_rerouted"
  }
  if ($v -match '(?i)\bresponse[/_.-]?incomplete\b' -or $v -match '(?i)\bincomplete\b') {
    return "response_incomplete"
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

function Get-EventEntries($obj, [string]$raw) {
  $items = @()
  $payloadTurnId = Get-JsonStringValue $obj @("turn_id", "turnId", "session.turn_id", "session.turnId", "metadata.turn_id", "metadata.turnId")

  $eventContainers = @()
  try { if ($null -ne $obj.events) { $eventContainers += $obj.events } } catch { }
  try { if ($null -ne $obj.payload.events) { $eventContainers += $obj.payload.events } } catch { }

  foreach ($container in $eventContainers) {
    foreach ($item in @($container)) {
      $kind = Normalize-EventKind (Get-JsonStringValue $item @("type", "event", "name", "kind"))
      if (-not $kind) {
        continue
      }

      $ts = Get-JsonStringValue $item @("timestamp", "ts", "time", "occurred_at", "created_at")
      $turnId = Get-JsonStringValue $item @("turn_id", "turnId", "metadata.turn_id", "metadata.turnId")
      if ([string]::IsNullOrWhiteSpace($turnId)) {
        $turnId = $payloadTurnId
      }
      $items += [pscustomobject]@{
        kind = $kind
        ts = $ts
        turn_id = $turnId
      }
    }
  }

  if ($items.Count -eq 0) {
    $topKind = Normalize-EventKind (Get-JsonStringValue $obj @("type", "event", "name", "kind"))
    if ($topKind) {
      $items += [pscustomobject]@{
        kind = $topKind
        ts = (Get-JsonStringValue $obj @("timestamp", "ts", "time", "occurred_at", "created_at"))
        turn_id = $payloadTurnId
      }
    }
  }

  if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($raw)) {
    if ($raw -match '(?i)\bmodel[/_.-]?rerouted\b' -or $raw -match '(?i)\bserver reported model\b.*\brequested model\b' -or $raw -match '(?i)\bfallback\b') {
      $items += [pscustomobject]@{ kind = "model_rerouted"; ts = $null; turn_id = $payloadTurnId }
    }
    if ($raw -match '(?i)\bresponse[/_.-]?incomplete\b') {
      $items += [pscustomobject]@{ kind = "response_incomplete"; ts = $null; turn_id = $payloadTurnId }
    }
  }

  $items |
    Sort-Object kind, ts, turn_id -Unique |
    Group-Object kind |
    ForEach-Object { $_.Group | Select-Object -First 1 }
}

$raw = Get-RawInput -inputFile $InputFile
if ([string]::IsNullOrWhiteSpace($raw)) {
  if ($DryRun) {
    Write-HookOutputJson -SystemMessage "SKIP: no hook payload provided."
  } else {
    Write-HookOutputJson
  }
  exit 0
}

$payload = Try-ParseJson -raw $raw
if ($null -eq $payload) {
  if ($DryRun) {
    Write-HookOutputJson -SystemMessage "SKIP: invalid hook payload JSON."
  } else {
    Write-HookOutputJson
  }
  exit 0
}

$projectRootResolved = Get-ProjectRootFromPayload -obj $payload -projectRootArg $ProjectRoot
if ([string]::IsNullOrWhiteSpace($projectRootResolved)) {
  if ($DryRun) {
    Write-HookOutputJson -SystemMessage "SKIP: project root could not be resolved."
  } else {
    Write-HookOutputJson
  }
  exit 0
}

$events = @(Get-EventEntries -obj $payload -raw $raw)
$featureRemovalWait = Get-FeatureRemovalWaitInfo -obj $payload
if ($events.Count -eq 0 -and $null -eq $featureRemovalWait) {
  if ($DryRun) {
    Write-HookOutputJson -SystemMessage "SKIP: no supported runtime/model events or feature-removal wait state found in hook payload."
  } else {
    Write-HookOutputJson
  }
  exit 0
}

$captureScript = Join-Path $projectRootResolved "HAGSWorks/scripts/capture-runtime-events.ps1"
if ($events.Count -gt 0 -and -not (Test-Path -LiteralPath $captureScript)) {
  $kinds = ($events | ForEach-Object { $_.kind } | Sort-Object -Unique) -join ", "
  $msg = "WARN: runtime/model event(s) detected but capture-runtime-events is missing (kinds=$kinds). 建议运行 ~init 或启用 HAGSWorks/scripts/capture-runtime-events.ps1."
  Write-HookOutputJson -SystemMessage $msg
  exit 0
}

$threadId = Get-JsonStringValue $payload @("thread_id", "threadId", "session.thread_id", "session.threadId")
$turnId = Get-JsonStringValue $payload @("turn_id", "turnId", "session.turn_id", "session.turnId", "metadata.turn_id", "metadata.turnId")
$traceId = Get-JsonStringValue $payload @("trace_id", "traceId", "session.trace_id", "session.traceId", "metadata.trace_id", "metadata.traceId")

$forwarded = 0
$forwardErrors = 0
$forwardLogs = @()
foreach ($eventEntry in $events) {
  try {
    $captureParams = @{
      Mode = "append"
      Kind = $eventEntry.kind
    }

    if (-not [string]::IsNullOrWhiteSpace($Package)) {
      $captureParams.Package = $Package
    }
    if (-not [string]::IsNullOrWhiteSpace($threadId)) {
      $captureParams.ThreadId = $threadId
    }
    if (-not [string]::IsNullOrWhiteSpace($eventEntry.turn_id)) {
      $captureParams.TurnId = $eventEntry.turn_id
    } elseif (-not [string]::IsNullOrWhiteSpace($turnId)) {
      $captureParams.TurnId = $turnId
    }
    if (-not [string]::IsNullOrWhiteSpace($traceId)) {
      $captureParams.TraceId = $traceId
    }
    if (-not [string]::IsNullOrWhiteSpace($eventEntry.ts)) {
      $captureParams.EventTimestamp = $eventEntry.ts
    }
    if ($DryRun) {
      $captureParams.DryRun = $true
    }

    $captureOut = & $captureScript @captureParams 2>&1
    if ($DryRun -and $null -ne $captureOut) {
      foreach ($line in @($captureOut)) {
        $forwardLogs += $line.ToString()
      }
    }
    $forwarded += 1
  } catch {
    $forwardErrors += 1
    if ($DryRun) {
      $forwardLogs += ("ERR: capture-runtime-events failed for '{0}': {1}" -f $eventEntry.kind, $_.Exception.Message)
    }
  }
}

$featureWaitMessage = $null
$featureWaitContext = $null
if ($null -ne $featureRemovalWait) {
  $featureWaitMessage = "INFO: 检测到功能删减确认等待态；下一轮应先回答是否允许本次删减。"
  $featureWaitContextLines = @("awaiting_topic: feature_removal_guard")
  if (-not [string]::IsNullOrWhiteSpace($featureRemovalWait.package)) {
    $featureWaitContextLines += ("package: {0}" -f $featureRemovalWait.package)
  }
  if (-not [string]::IsNullOrWhiteSpace($turnId)) {
    $featureWaitContextLines += ("current_turn_id: {0}" -f $turnId)
  }
  if (-not [string]::IsNullOrWhiteSpace($featureRemovalWait.next_unique_action)) {
    $featureWaitContextLines += ("next_unique_action: {0}" -f $featureRemovalWait.next_unique_action)
  }
  $featureWaitContext = ($featureWaitContextLines -join "`n")
}

if ($forwarded -eq 0) {
  $msg = if ($featureWaitMessage) { $featureWaitMessage } else { "WARN: hook payload parsed, but no event could be forwarded to capture-runtime-events." }
  $hookMsg = $null
  if ($DryRun -and $forwardLogs.Count -gt 0) {
    $hookMsg = ($forwardLogs -join "`n")
  }
  Write-HookOutputJson -SystemMessage $msg -HookMessage $hookMsg -AdditionalContext $featureWaitContext
  exit 0
}

if ($forwardErrors -gt 0) {
  $msg = "WARN: stop hook forwarded $forwarded event(s), with $forwardErrors error(s)."
  if ($featureWaitMessage) {
    $msg += " $featureWaitMessage"
  }
  $hookMsg = $null
  if ($DryRun -and $forwardLogs.Count -gt 0) {
    $hookMsg = ($forwardLogs -join "`n")
  }
  Write-HookOutputJson -SystemMessage $msg -HookMessage $hookMsg -AdditionalContext $featureWaitContext
  exit 0
}

if ($DryRun) {
  $hookMsg = $null
  if ($forwardLogs.Count -gt 0) {
    $hookMsg = ($forwardLogs -join "`n")
  }
  $msg = ("OK: stop hook forwarded {0} event(s)." -f $forwarded)
  if ($featureWaitMessage) {
    $msg += " " + $featureWaitMessage
  }
  Write-HookOutputJson -SystemMessage $msg -HookMessage $hookMsg -AdditionalContext $featureWaitContext
  exit 0
}

if ($featureWaitMessage) {
  Write-HookOutputJson -SystemMessage $featureWaitMessage -AdditionalContext $featureWaitContext
  exit 0
}

Write-HookOutputJson
