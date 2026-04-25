param(
  [string]$PlanRoot = "HAGSWorks/plan",
  [string]$Package = "",
  [ValidateSet("detect", "append")]
  [string]$Mode = "detect",
  [ValidateSet("", "model_rerouted", "response_incomplete")]
  [string]$Kind = "",
  [string]$TaskFile = "",
  [string]$CodexHome = "",
  [string]$ThreadId = "",
  [string]$TurnId = "",
  [string]$TraceId = "",
  [string]$EventTimestamp = "",
  [string]$SessionFile = "",
  [int]$TailLines = 20000,
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

$LABEL_NEXT_UNIQUE_ACTION = [string]::Concat(
  [char]0x4E0B,
  [char]0x4E00,
  [char]0x6B65,
  [char]0x552F,
  [char]0x4E00,
  [char]0x52A8,
  [char]0x4F5C
)

$H3_RUNTIME_MODEL_EVENTS = [string]::Concat(
  [char]0x8FD0,
  [char]0x884C,
  [char]0x65F6,
  [char]0x002F,
  [char]0x6A21,
  [char]0x578B,
  [char]0x4E8B,
  [char]0x4EF6,
  [char]0xFF08,
  [char]0x53EF,
  [char]0x9009,
  [char]0xFF0C,
  [char]0x7ED3,
  [char]0x6784,
  [char]0x5316,
  [char]0xFF09
)

$H3_RUNTIME_MODEL_EVENTS_LEGACY = "### Runtime/Model Events (optional, structured)"

function Get-GitRoot() {
  try {
    $root = (git rev-parse --show-toplevel 2>$null).Trim()
    if (-not [string]::IsNullOrWhiteSpace($root)) {
      return $root
    }
  } catch {
    # ignore
  }
  return $null
}

function Get-ProjectRoot() {
  if ($PSScriptRoot) {
    try {
      $twoUp = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\\..")).Path
      if (Test-Path -LiteralPath (Join-Path $twoUp "HAGSWorks")) {
        return $twoUp
      }
    } catch {
      # ignore
    }
  }

  $gitRoot = Get-GitRoot
  if ($gitRoot) {
    return $gitRoot
  }

  return (Get-Location).Path
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

function Get-TaskLockPath([string]$projectRoot, [string]$taskPath) {
  $lockRoot = Join-Path $projectRoot "_codex_temp/locks"
  if (-not (Test-Path -LiteralPath $lockRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null
  }

  $normalized = $taskPath.ToLowerInvariant()
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").Substring(0, 16)
    return (Join-Path $lockRoot "helloagents-task-$hash.lock")
  } finally {
    $sha.Dispose()
  }
}

function Invoke-WithTaskFileLock([string]$lockPath, [scriptblock]$body, [int]$timeoutMs = 5000) {
  $deadline = [datetime]::UtcNow.AddMilliseconds($timeoutMs)
  $stream = $null

  while ([datetime]::UtcNow -lt $deadline) {
    try {
      $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
      break
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }

  if ($null -eq $stream) {
    return [pscustomobject]@{
      acquired = $false
      value = $null
    }
  }

  try {
    return [pscustomobject]@{
      acquired = $true
      value = (& $body)
    }
  } finally {
    $stream.Dispose()
  }
}

function Resolve-CurrentPackage([string]$projectRoot, [string]$planRoot, [string]$packageArg) {
  if (-not [string]::IsNullOrWhiteSpace($packageArg)) {
    $p = $packageArg.Trim()
    if ([System.IO.Path]::IsPathRooted($p)) {
      return $p
    }
    return (Join-Path $projectRoot $p)
  }

  $pointer = Join-Path $projectRoot (Join-Path $planRoot "_current.md")
  if (-not (Test-Path -LiteralPath $pointer)) {
    return $null
  }

  $text = Read-Utf8Text -path $pointer
  $m = [regex]::Match($text, '(?m)^\s*current_package\s*:\s*(?<path>.*)\s*$')
  if (-not $m.Success) {
    return $null
  }

  $raw = $m.Groups["path"].Value
  $raw = [regex]::Replace($raw, '\s+#.*$', '')
  $v = $raw.Trim()
  if ([string]::IsNullOrWhiteSpace($v)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($v)) {
    return $v
  }

  return (Join-Path $projectRoot $v)
}

function Resolve-TaskFile([string]$projectRoot, [string]$taskFileArg, [string]$packagePath) {
  if (-not [string]::IsNullOrWhiteSpace($taskFileArg)) {
    $p = $taskFileArg.Trim()
    if ([System.IO.Path]::IsPathRooted($p)) {
      return $p
    }
    return (Join-Path $projectRoot $p)
  }

  if ([string]::IsNullOrWhiteSpace($packagePath)) {
    return $null
  }

  return (Join-Path $packagePath "task.md")
}

function Get-CodexHome([string]$codexHomeArg) {
  if (-not [string]::IsNullOrWhiteSpace($codexHomeArg)) {
    return $codexHomeArg.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    return $env:CODEX_HOME.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    return (Join-Path $env:USERPROFILE ".codex")
  }

  return (Join-Path $HOME ".codex")
}

function Get-ThreadId([string]$threadIdArg) {
  if (-not [string]::IsNullOrWhiteSpace($threadIdArg)) {
    return $threadIdArg.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) {
    return $env:CODEX_THREAD_ID.Trim()
  }
  return $null
}

function Get-TurnId([string]$turnIdArg) {
  if (-not [string]::IsNullOrWhiteSpace($turnIdArg)) {
    return $turnIdArg.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_TURN_ID)) {
    return $env:CODEX_TURN_ID.Trim()
  }
  return $null
}

function Get-TraceId([string]$traceIdArg) {
  if (-not [string]::IsNullOrWhiteSpace($traceIdArg)) {
    return $traceIdArg.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_TRACE_ID)) {
    return $env:CODEX_TRACE_ID.Trim()
  }
  return $null
}

function Get-EventTimestamp([string]$eventTimestampArg) {
  if (-not [string]::IsNullOrWhiteSpace($eventTimestampArg)) {
    return $eventTimestampArg.Trim()
  }
  return (Get-Date).ToUniversalTime().ToString("o")
}

function Find-SessionFile([string]$codexHome, [string]$threadId, [string]$sessionFileArg) {
  if (-not [string]::IsNullOrWhiteSpace($sessionFileArg)) {
    if (Test-Path -LiteralPath $sessionFileArg) {
      return $sessionFileArg
    }
    return $null
  }

  if ([string]::IsNullOrWhiteSpace($codexHome) -or [string]::IsNullOrWhiteSpace($threadId)) {
    return $null
  }

  $sessionDirs = @(
    (Join-Path $codexHome "sessions"),
    (Join-Path $codexHome "archived_sessions")
  )

  foreach ($d in $sessionDirs) {
    if (-not (Test-Path -LiteralPath $d)) {
      continue
    }
    $hit = Get-ChildItem -LiteralPath $d -Recurse -File -Filter "*$threadId*.jsonl" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($hit) {
      return $hit.FullName
    }
  }
  return $null
}

function Find-RealtimeTextLog([string]$codexHome) {
  if ([string]::IsNullOrWhiteSpace($codexHome)) {
    return $null
  }

  $candidates = @(
    (Join-Path $codexHome "log\\codex-tui.log")
  )

  foreach ($p in $candidates) {
    if (Test-Path -LiteralPath $p) {
      return $p
    }
  }

  return $null
}

function Get-TraceIdFromObject($obj) {
  $candidates = @()

  try { $candidates += $obj.trace_id } catch { }
  try { $candidates += $obj.traceId } catch { }
  try { $candidates += $obj.payload.trace_id } catch { }
  try { $candidates += $obj.payload.traceId } catch { }
  try { $candidates += $obj.metadata.trace_id } catch { }
  try { $candidates += $obj.metadata.traceId } catch { }

  foreach ($candidate in $candidates) {
    if ($candidate -is [string] -and -not [string]::IsNullOrWhiteSpace($candidate)) {
      return $candidate.Trim()
    }
  }

  return $null
}

function Get-TurnIdFromObject($obj) {
  $candidates = @()

  try { $candidates += $obj.turn_id } catch { }
  try { $candidates += $obj.turnId } catch { }
  try { $candidates += $obj.payload.turn_id } catch { }
  try { $candidates += $obj.payload.turnId } catch { }
  try { $candidates += $obj.metadata.turn_id } catch { }
  try { $candidates += $obj.metadata.turnId } catch { }

  foreach ($candidate in $candidates) {
    if ($candidate -is [string] -and -not [string]::IsNullOrWhiteSpace($candidate)) {
      return $candidate.Trim()
    }
  }

  return $null
}

function Get-TraceIdFromTextLine([string]$line) {
  if ([string]::IsNullOrWhiteSpace($line)) {
    return $null
  }

  $patterns = @(
    '(?i)\btrace_id=(?<id>\S+)',
    '(?i)\btraceId=(?<id>\S+)',
    '(?i)"trace_id"\s*:\s*"(?<id>[^"]+)"',
    '(?i)"traceId"\s*:\s*"(?<id>[^"]+)"'
  )

  foreach ($pattern in $patterns) {
    $m = [regex]::Match($line, $pattern)
    if ($m.Success) {
      $id = $m.Groups["id"].Value.Trim([char]0x60, '"', "'", ",", ";")
      if (-not [string]::IsNullOrWhiteSpace($id)) {
        return $id
      }
    }
  }

  return $null
}

function Get-TurnIdFromTextLine([string]$line) {
  if ([string]::IsNullOrWhiteSpace($line)) {
    return $null
  }

  $patterns = @(
    '(?i)\bturn_id=(?<id>\S+)',
    '(?i)\bturnId=(?<id>\S+)',
    '(?i)"turn_id"\s*:\s*"(?<id>[^"]+)"',
    '(?i)"turnId"\s*:\s*"(?<id>[^"]+)"'
  )

  foreach ($pattern in $patterns) {
    $m = [regex]::Match($line, $pattern)
    if ($m.Success) {
      $id = $m.Groups["id"].Value.Trim([char]0x60, '"', "'", ",", ";")
      if (-not [string]::IsNullOrWhiteSpace($id)) {
        return $id
      }
    }
  }

  return $null
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

function Extract-ModelEvents([string[]]$jsonLines) {
  return Extract-ModelEventsInternal -jsonLines $jsonLines -wantedTraceId $null -wantedTurnId $null
}

function Extract-ModelEventsInternal([string[]]$jsonLines, [string]$wantedTraceId, [string]$wantedTurnId) {
  $events = @()

  foreach ($line in $jsonLines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    $obj = $null
    try {
      $obj = ($line | ConvertFrom-Json)
    } catch {
      continue
    }

    if ($null -eq $obj) {
      continue
    }

    if ($obj.type -ne "event_msg") {
      continue
    }

    $payloadType = $null
    try {
      $payloadType = $obj.payload.type
    } catch {
      $payloadType = $null
    }

    if (-not ($payloadType -is [string])) {
      continue
    }

    $kind = $null
    if ($payloadType -match '(?i)^model[/_.-]?rerouted\b') {
      $kind = "model_rerouted"
    } elseif ($payloadType -match '(?i)^response[/_.-]?incomplete\b') {
      $kind = "response_incomplete"
    }

    if (-not $kind) {
      continue
    }

    $traceId = Get-TraceIdFromObject -obj $obj
    $turnId = Get-TurnIdFromObject -obj $obj
    if (-not [string]::IsNullOrWhiteSpace($wantedTraceId)) {
      if ([string]::IsNullOrWhiteSpace($traceId) -or ($traceId -ne $wantedTraceId)) {
        continue
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($wantedTurnId)) {
      if ([string]::IsNullOrWhiteSpace($turnId) -or ($turnId -ne $wantedTurnId)) {
        continue
      }
    }

    $ts = $null
    try { $ts = $obj.timestamp } catch { $ts = $null }
    if (-not ($ts -is [string]) -or [string]::IsNullOrWhiteSpace($ts)) {
      $ts = (Get-Date).ToUniversalTime().ToString("o")
    }

    $events += [pscustomobject]@{
      kind = $kind
      ts = $ts
      trace_id = $traceId
      turn_id = $turnId
    }
  }

  $events |
    Sort-Object kind, ts, trace_id, turn_id -Unique
}

function Extract-ModelEventsFromTextLog([string[]]$lines, [string]$threadId, [string]$turnId, [string]$traceId) {
  $events = @()

  $wantThread = -not [string]::IsNullOrWhiteSpace($threadId)
  $threadNeedle = if ($wantThread) { "thread_id=$threadId" } else { "" }
  $wantTurn = -not [string]::IsNullOrWhiteSpace($turnId)
  $wantTrace = -not [string]::IsNullOrWhiteSpace($traceId)

  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    if ($wantThread -and ($line.IndexOf($threadNeedle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0)) {
      continue
    }

    $lineTurnId = Get-TurnIdFromTextLine -line $line
    if ($wantTurn) {
      if ([string]::IsNullOrWhiteSpace($lineTurnId) -or ($lineTurnId -ne $turnId)) {
        continue
      }
    }

    $lineTraceId = Get-TraceIdFromTextLine -line $line
    if ($wantTrace) {
      if ([string]::IsNullOrWhiteSpace($lineTraceId) -or ($lineTraceId -ne $traceId)) {
        continue
      }
    }

    $mTs = [regex]::Match($line, '^(?<ts>\d{4}-\d{2}-\d{2}T[0-9:\.\-]+Z)\s+')
    if (-not $mTs.Success) {
      continue
    }

    $ts = $mTs.Groups["ts"].Value
    if ([string]::IsNullOrWhiteSpace($ts)) {
      $ts = (Get-Date).ToUniversalTime().ToString("o")
    }

    $kind = $null
    if ($line -match '(?i)\bmodel[/_.-]?rerouted\b') {
      $kind = "model_rerouted"
    } elseif ($line -match '(?i)\bserver reported model\b.*\brequested model\b') {
      $kind = "model_rerouted"
    } elseif ($line -match '(?i)\bresponse[/_.-]?incomplete\b') {
      $kind = "response_incomplete"
    }

    if (-not $kind) {
      continue
    }

    $events += [pscustomobject]@{
      kind = $kind
      ts = $ts
      trace_id = $lineTraceId
      turn_id = $lineTurnId
    }
  }

  $events |
    Sort-Object kind, ts, trace_id, turn_id -Unique
}

function Get-RecordedEventKeys([string]$snapshotBody) {
  $known = [ordered]@{
    kindOnly = @{}
    kindTs = @{}
    kindTsTrace = @{}
    kindTurn = @{}
    kindTsTurn = @{}
    kindTsTraceTurn = @{}
  }

  if ([string]::IsNullOrWhiteSpace($snapshotBody)) {
    return $known
  }

  $rx = [regex]::new('(?im)^\s*-\s*\[SRC:TOOL\]\s*model_event\s*[:\uFF1A]\s*(?<kind>\S+)(?:\s+#\s*ts=(?<ts>\S+))?(?:\s+trace_id=(?<trace>\S+))?(?:\s+turn_id=(?<turn>\S+))?.*$')
  $ms = $rx.Matches($snapshotBody)
  foreach ($m in $ms) {
    $kind = $m.Groups["kind"].Value.Trim()
    $ts = $m.Groups["ts"].Value.Trim()
    $trace = $m.Groups["trace"].Value.Trim()
    $turn = $m.Groups["turn"].Value.Trim()
    if (-not [string]::IsNullOrWhiteSpace($kind)) {
      $known.kindOnly[$kind] = $true
      if (-not [string]::IsNullOrWhiteSpace($turn)) {
        $known.kindTurn["$kind@@$turn"] = $true
      }
      if (-not [string]::IsNullOrWhiteSpace($ts)) {
        $known.kindTs["$kind@@$ts"] = $true
        if (-not [string]::IsNullOrWhiteSpace($turn)) {
          $known.kindTsTurn["$kind@@$ts@@$turn"] = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($trace)) {
          $known.kindTsTrace["$kind@@$ts@@$trace"] = $true
          if (-not [string]::IsNullOrWhiteSpace($turn)) {
            $known.kindTsTraceTurn["$kind@@$ts@@$trace@@$turn"] = $true
          }
        }
      }
    }
  }

  return $known
}

function Get-H2Section([string]$text, [string]$h2Title) {
  $pattern = '(?ms)^\s*##\s*' + [regex]::Escape($h2Title) + '\s*$\r?\n'
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

function Ensure-TrailingNewline([string]$s) {
  if ($s -match "(\r?\n)$") {
    return $s
  }
  return ($s + "`n")
}

function Append-EventsToSnapshot([string]$snapshotBody, [pscustomobject[]]$eventsToAdd, [string]$repoStateLine) {
  $b = Ensure-TrailingNewline -s $snapshotBody

  $hasHeading = (
    ($b -match '(?m)^\s*###\s*Runtime/Model Events') -or
    ($b -match ('(?m)^\s*###\s*' + [regex]::Escape($H3_RUNTIME_MODEL_EVENTS) + '\s*$'))
  )
  if (-not $hasHeading) {
    $b += ("`n### {0}`n" -f $H3_RUNTIME_MODEL_EVENTS)
  } elseif ($b -notmatch "(\r?\n)$") {
    $b += "`n"
  }
  $b = [regex]::Replace(
    $b,
    '(?m)^\s*###\s*Runtime/Model Events \(optional, structured\)\s*$',
    ("### {0}" -f $H3_RUNTIME_MODEL_EVENTS)
  )

  foreach ($e in $eventsToAdd) {
    $kind = $e.kind
    $ts = $e.ts
    $traceSuffix = ""
    if (-not [string]::IsNullOrWhiteSpace($e.trace_id)) {
      $traceSuffix = " trace_id=$($e.trace_id)"
    }
    $turnSuffix = ""
    if (-not [string]::IsNullOrWhiteSpace($e.turn_id)) {
      $turnSuffix = " turn_id=$($e.turn_id)"
    }
    $b += "- [SRC:TOOL] model_event: $kind # ts=$ts$traceSuffix$turnSuffix`n"
    if (-not [string]::IsNullOrWhiteSpace($e.trace_id)) {
      $b += "- [SRC:TOOL] trace_id: $($e.trace_id)`n"
    }
    if (-not [string]::IsNullOrWhiteSpace($e.turn_id)) {
      $b += "- [SRC:TOOL] turn_id: $($e.turn_id)`n"
    }
    $b += "- [SRC:TOOL] repo_state: $repoStateLine`n"
    $b += "- ${LABEL_NEXT_UNIQUE_ACTION}: 按 references/resume-protocol.md 执行断层恢复（Reboot Check）`n`n"
  }

  return $b
}

$projectRoot = Get-ProjectRoot
$pkgPath = Resolve-CurrentPackage -projectRoot $projectRoot -planRoot $PlanRoot -packageArg $Package
$taskPath = Resolve-TaskFile -projectRoot $projectRoot -taskFileArg $TaskFile -packagePath $pkgPath

if ([string]::IsNullOrWhiteSpace($taskPath) -or -not (Test-Path -LiteralPath $taskPath)) {
  Write-Output "SKIP: task.md not found (package='$Package')."
  exit 0
}

$events = @()
if ($Mode -eq "append") {
  if ([string]::IsNullOrWhiteSpace($Kind)) {
    Write-Output "SKIP: -Mode append requires -Kind (model_rerouted|response_incomplete)."
    exit 0
  }
  $appendTraceId = Get-TraceId -traceIdArg $TraceId
  $appendTurnId = Get-TurnId -turnIdArg $TurnId
  $appendTimestamp = Get-EventTimestamp -eventTimestampArg $EventTimestamp
  $events = @([pscustomobject]@{
    kind = $Kind
    ts = $appendTimestamp
    trace_id = $appendTraceId
    turn_id = $appendTurnId
  })
} else {
  $codexHome = Get-CodexHome -codexHomeArg $CodexHome
  $tid = Get-ThreadId -threadIdArg $ThreadId
  $turnId = Get-TurnId -turnIdArg $TurnId
  $traceId = Get-TraceId -traceIdArg $TraceId

  if (-not [string]::IsNullOrWhiteSpace($tid) -or -not [string]::IsNullOrWhiteSpace($traceId)) {
    $textLog = Find-RealtimeTextLog -codexHome $codexHome
    if (-not [string]::IsNullOrWhiteSpace($textLog)) {
      $tail = @(Get-Content -LiteralPath $textLog -Tail $TailLines -ErrorAction SilentlyContinue)
      $events = @(Extract-ModelEventsFromTextLog -lines $tail -threadId $tid -turnId $turnId -traceId $traceId)
    }
  }

  if ($events.Count -eq 0) {
    $session = Find-SessionFile -codexHome $codexHome -threadId $tid -sessionFileArg $SessionFile
    if ([string]::IsNullOrWhiteSpace($session) -or -not (Test-Path -LiteralPath $session)) {
      if ([string]::IsNullOrWhiteSpace($tid) -and [string]::IsNullOrWhiteSpace($traceId)) {
        Write-Output "SKIP: CODEX_THREAD_ID/CODEX_TRACE_ID missing; turn_id alone is not enough for safe log scanning. Provide -ThreadId/-TraceId (or env vars), pass -SessionFile, or use -Mode append."
      } else {
        Write-Output "SKIP: codex logs not found (no text log hit; and session JSONL missing: no session match)."
      }
      exit 0
    }

    $tail = @(Get-Content -LiteralPath $session -Tail $TailLines -ErrorAction SilentlyContinue)
    $events = @(Extract-ModelEventsInternal -jsonLines $tail -wantedTraceId $traceId -wantedTurnId $turnId)
  }
}

if ($events.Count -eq 0) {
  Write-Output "OK: no runtime/model events found."
  exit 0
}

$lockPath = Get-TaskLockPath -projectRoot $projectRoot -taskPath $taskPath
$lockResult = Invoke-WithTaskFileLock -lockPath $lockPath -body {
  $taskText = Read-Utf8Text -path $taskPath
  $snapshot = Get-H2Section -text $taskText -h2Title $H2_CONTEXT_SNAPSHOT
  if ($null -eq $snapshot) {
    return "SKIP: task.md has no '## 上下文快照' section."
  }

  $recorded = Get-RecordedEventKeys -snapshotBody $snapshot.body
  $toAdd = @()
  foreach ($e in $events) {
    $k = $e.kind
    $ts = $e.ts
    $eventTraceId = $e.trace_id
    $eventTurnId = $e.turn_id
    $isDuplicate = $false
    if (-not [string]::IsNullOrWhiteSpace($eventTurnId)) {
      if (-not [string]::IsNullOrWhiteSpace($eventTraceId) -and $recorded.kindTsTraceTurn.Contains("$k@@$ts@@$eventTraceId@@$eventTurnId")) {
        $isDuplicate = $true
      } elseif ($recorded.kindTsTurn.Contains("$k@@$ts@@$eventTurnId")) {
        $isDuplicate = $true
      } elseif ($recorded.kindTurn.Contains("$k@@$eventTurnId")) {
        $isDuplicate = $true
      } elseif ($recorded.kindTs.Contains("$k@@$ts")) {
        $isDuplicate = $true
      }
    } elseif (-not [string]::IsNullOrWhiteSpace($eventTraceId)) {
      if ($recorded.kindTsTrace.Contains("$k@@$ts@@$eventTraceId") -or $recorded.kindTs.Contains("$k@@$ts")) {
        $isDuplicate = $true
      }
    } elseif (-not [string]::IsNullOrWhiteSpace($ts)) {
      if ($recorded.kindTs.Contains("$k@@$ts")) {
        $isDuplicate = $true
      }
    } elseif ($recorded.kindOnly.Contains($k)) {
      $isDuplicate = $true
    }
    if ($isDuplicate) {
      continue
    }
    $toAdd += $e
  }

  if ($toAdd.Count -eq 0) {
    return "OK: no new events to append."
  }

  $repoState = Get-RepoState -projectRoot $projectRoot
  $newBody = Append-EventsToSnapshot -snapshotBody $snapshot.body -eventsToAdd $toAdd -repoStateLine $repoState
  $newText = $snapshot.before + $newBody + $snapshot.after

  if ($DryRun) {
    $lines = @("DRYRUN: would append $($toAdd.Count) event(s) to '$taskPath'.")
    $toAdd | ForEach-Object {
      $suffix = ""
      if (-not [string]::IsNullOrWhiteSpace($_.trace_id)) {
        $suffix = " trace_id=" + $_.trace_id
      }
      if (-not [string]::IsNullOrWhiteSpace($_.turn_id)) {
        $suffix += " turn_id=" + $_.turn_id
      }
      $lines += ("- model_event: " + $_.kind + " ts=" + $_.ts + $suffix)
      $lines += ("- repo_state: " + $repoState)
      $lines += ("- " + $LABEL_NEXT_UNIQUE_ACTION + ": 按 references/resume-protocol.md 执行断层恢复（Reboot Check）")
      $lines += "- recovery_checkpoint: repo_state + 下一步唯一动作"
    }
    return ($lines -join "`n")
  }

  Write-Utf8Text -path $taskPath -text $newText
  return "OK: appended $($toAdd.Count) event(s) to '$taskPath'."
}

if (-not $lockResult.acquired) {
  Write-Output "SKIP: task.md lock busy; runtime/model events not appended."
  exit 0
}

Write-Output $lockResult.value
