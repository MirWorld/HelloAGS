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

    $ts = $null
    try { $ts = $obj.timestamp } catch { $ts = $null }
    if (-not ($ts -is [string]) -or [string]::IsNullOrWhiteSpace($ts)) {
      $ts = (Get-Date).ToUniversalTime().ToString("o")
    }

    $events += [pscustomobject]@{
      kind = $kind
      ts = $ts
    }
  }

  $events |
    Sort-Object kind, ts -Unique
}

function Extract-ModelEventsFromTextLog([string[]]$lines, [string]$threadId) {
  $events = @()

  $wantThread = -not [string]::IsNullOrWhiteSpace($threadId)
  $threadNeedle = if ($wantThread) { "thread_id=$threadId" } else { "" }

  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    if ($wantThread -and ($line.IndexOf($threadNeedle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0)) {
      continue
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
    }
  }

  $events |
    Sort-Object kind, ts -Unique
}

function Get-RecordedEventKeys([string]$snapshotBody) {
  $known = [ordered]@{
    kindOnly = @{}
    kindTs = @{}
  }

  if ([string]::IsNullOrWhiteSpace($snapshotBody)) {
    return $known
  }

  $rx = [regex]::new('(?im)^\s*-\s*\[SRC:TOOL\]\s*model_event\s*[:\uFF1A]\s*(?<kind>\S+)(?:\s+#\s*ts=(?<ts>\S+))?.*$')
  $ms = $rx.Matches($snapshotBody)
  foreach ($m in $ms) {
    $kind = $m.Groups["kind"].Value.Trim()
    $ts = $m.Groups["ts"].Value.Trim()
    if (-not [string]::IsNullOrWhiteSpace($kind)) {
      $known.kindOnly[$kind] = $true
      if (-not [string]::IsNullOrWhiteSpace($ts)) {
        $known.kindTs["$kind@@$ts"] = $true
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

  $hasHeading = ($b -match '(?m)^\s*###\s*Runtime/Model Events')
  if (-not $hasHeading) {
    $b += "`n### Runtime/Model Events (optional, structured)`n"
  } elseif ($b -notmatch "(\r?\n)$") {
    $b += "`n"
  }

  foreach ($e in $eventsToAdd) {
    $kind = $e.kind
    $ts = $e.ts
    $b += "- [SRC:TOOL] model_event: $kind # ts=$ts`n"
    $b += "- [SRC:TOOL] repo_state: $repoStateLine`n"
    $b += "- ${LABEL_NEXT_UNIQUE_ACTION}: Run references/resume-protocol.md (Reboot Check)`n`n"
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

$taskText = Read-Utf8Text -path $taskPath
$snapshot = Get-H2Section -text $taskText -h2Title $H2_CONTEXT_SNAPSHOT
if ($null -eq $snapshot) {
  Write-Output "SKIP: task.md has no '## 上下文快照' section."
  exit 0
}

$events = @()
if ($Mode -eq "append") {
  if ([string]::IsNullOrWhiteSpace($Kind)) {
    Write-Output "SKIP: -Mode append requires -Kind (model_rerouted|response_incomplete)."
    exit 0
  }
  $events = @([pscustomobject]@{
    kind = $Kind
    ts = (Get-Date).ToUniversalTime().ToString("o")
  })
} else {
  $codexHome = Get-CodexHome -codexHomeArg $CodexHome
  $tid = Get-ThreadId -threadIdArg $ThreadId

  if (-not [string]::IsNullOrWhiteSpace($tid)) {
    $textLog = Find-RealtimeTextLog -codexHome $codexHome
    if (-not [string]::IsNullOrWhiteSpace($textLog)) {
      $tail = @(Get-Content -LiteralPath $textLog -Tail $TailLines -ErrorAction SilentlyContinue)
      $events = @(Extract-ModelEventsFromTextLog -lines $tail -threadId $tid)
    }
  }

  if ($events.Count -eq 0) {
    $session = Find-SessionFile -codexHome $codexHome -threadId $tid -sessionFileArg $SessionFile
    if ([string]::IsNullOrWhiteSpace($session) -or -not (Test-Path -LiteralPath $session)) {
      if ([string]::IsNullOrWhiteSpace($tid)) {
        Write-Output "SKIP: CODEX_THREAD_ID missing; not scanning text logs to avoid cross-thread misattribution. Provide -ThreadId/CODEX_THREAD_ID or pass -SessionFile (or use -Mode append)."
      } else {
        Write-Output "SKIP: codex logs not found (no text log hit; and session JSONL missing: no session match)."
      }
      exit 0
    }

    $tail = @(Get-Content -LiteralPath $session -Tail $TailLines -ErrorAction SilentlyContinue)
    $events = @(Extract-ModelEvents -jsonLines $tail)
  }
}

if ($events.Count -eq 0) {
  Write-Output "OK: no runtime/model events found."
  exit 0
}

$recorded = Get-RecordedEventKeys -snapshotBody $snapshot.body
$toAdd = @()
foreach ($e in $events) {
  $k = $e.kind
  $ts = $e.ts
  if ($recorded.kindOnly.Contains($k)) {
    continue
  }
  if ($recorded.kindTs.Contains("$k@@$ts")) {
    continue
  }
  $toAdd += $e
}

if ($toAdd.Count -eq 0) {
  Write-Output "OK: no new events to append."
  exit 0
}

$repoState = Get-RepoState -projectRoot $projectRoot
$newBody = Append-EventsToSnapshot -snapshotBody $snapshot.body -eventsToAdd $toAdd -repoStateLine $repoState
$newText = $snapshot.before + $newBody + $snapshot.after

if ($DryRun) {
  Write-Output "DRYRUN: would append $($toAdd.Count) event(s) to '$taskPath'."
  $toAdd | ForEach-Object { Write-Output ("- model_event: " + $_.kind + " ts=" + $_.ts) }
  exit 0
}

Write-Utf8Text -path $taskPath -text $newText
Write-Output "OK: appended $($toAdd.Count) event(s) to '$taskPath'."
