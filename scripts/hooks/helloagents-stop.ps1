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
      $items += [pscustomobject]@{
        kind = $kind
        ts = $ts
      }
    }
  }

  if ($items.Count -eq 0) {
    $topKind = Normalize-EventKind (Get-JsonStringValue $obj @("type", "event", "name", "kind"))
    if ($topKind) {
      $items += [pscustomobject]@{
        kind = $topKind
        ts = (Get-JsonStringValue $obj @("timestamp", "ts", "time", "occurred_at", "created_at"))
      }
    }
  }

  if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($raw)) {
    if ($raw -match '(?i)\bmodel[/_.-]?rerouted\b' -or $raw -match '(?i)\bserver reported model\b.*\brequested model\b' -or $raw -match '(?i)\bfallback\b') {
      $items += [pscustomobject]@{ kind = "model_rerouted"; ts = $null }
    }
    if ($raw -match '(?i)\bresponse[/_.-]?incomplete\b') {
      $items += [pscustomobject]@{ kind = "response_incomplete"; ts = $null }
    }
  }

  $items |
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
if ($events.Count -eq 0) {
  if ($DryRun) {
    Write-HookOutputJson -SystemMessage "SKIP: no supported runtime/model events found in hook payload."
  } else {
    Write-HookOutputJson
  }
  exit 0
}

$captureScript = Join-Path $projectRootResolved "HAGSWorks/scripts/capture-runtime-events.ps1"
if (-not (Test-Path -LiteralPath $captureScript)) {
  $kinds = ($events | ForEach-Object { $_.kind } | Sort-Object -Unique) -join ", "
  $msg = "WARN: runtime/model event(s) detected but capture-runtime-events is missing (kinds=$kinds). 建议运行 ~init 或启用 HAGSWorks/scripts/capture-runtime-events.ps1."
  Write-HookOutputJson -SystemMessage $msg
  exit 0
}

$threadId = Get-JsonStringValue $payload @("thread_id", "threadId", "session.thread_id", "session.threadId")
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

if ($forwarded -eq 0) {
  $msg = "WARN: hook payload parsed, but no event could be forwarded to capture-runtime-events."
  $hookMsg = $null
  if ($DryRun -and $forwardLogs.Count -gt 0) {
    $hookMsg = ($forwardLogs -join "`n")
  }
  Write-HookOutputJson -SystemMessage $msg -HookMessage $hookMsg
  exit 0
}

if ($forwardErrors -gt 0) {
  $msg = "WARN: stop hook forwarded $forwarded event(s), with $forwardErrors error(s)."
  $hookMsg = $null
  if ($DryRun -and $forwardLogs.Count -gt 0) {
    $hookMsg = ($forwardLogs -join "`n")
  }
  Write-HookOutputJson -SystemMessage $msg -HookMessage $hookMsg
  exit 0
}

if ($DryRun) {
  $hookMsg = $null
  if ($forwardLogs.Count -gt 0) {
    $hookMsg = ($forwardLogs -join "`n")
  }
  Write-HookOutputJson -SystemMessage ("OK: stop hook forwarded {0} event(s)." -f $forwarded) -HookMessage $hookMsg
  exit 0
}

Write-HookOutputJson
