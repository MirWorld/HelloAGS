param(
  [string]$ProjectRoot = "",
  [string]$PlanRoot = "HAGSWorks/plan",
  [string]$HistoryRoot = "HAGSWorks/history",
  [string]$Package = "",
  [switch]$ConfirmAbandon,
  [switch]$ConfirmCurrent,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

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
  if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    return [System.IO.Path]::GetFullPath($ProjectRoot)
  }

  if ($PSScriptRoot) {
    try {
      $twoUp = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
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

function Resolve-PathValue([string]$baseRoot, [string]$rawPath) {
  if ([string]::IsNullOrWhiteSpace($rawPath)) {
    return ""
  }

  $expanded = [Environment]::ExpandEnvironmentVariables($rawPath.Trim())
  if ([System.IO.Path]::IsPathRooted($expanded)) {
    return [System.IO.Path]::GetFullPath($expanded)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $baseRoot $expanded))
}

function Test-SamePath([string]$left, [string]$right) {
  if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) {
    return $false
  }

  try {
    $leftFull = [System.IO.Path]::GetFullPath($left).TrimEnd('\', '/')
    $rightFull = [System.IO.Path]::GetFullPath($right).TrimEnd('\', '/')
    return [string]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Test-IsPathUnderDirectory([string]$path, [string]$directory) {
  if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($directory)) {
    return $false
  }

  try {
    $pathFull = [System.IO.Path]::GetFullPath($path).TrimEnd('\', '/')
    $dirFull = [System.IO.Path]::GetFullPath($directory).TrimEnd('\', '/')
    if ([string]::Equals($pathFull, $dirFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $false
    }

    $dirPrefix = $dirFull + [System.IO.Path]::DirectorySeparatorChar
    return $pathFull.StartsWith($dirPrefix, [System.StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Read-Text([string]$path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)
  }
  return $text
}

function Write-Utf8Text([string]$path, [string]$text) {
  $parent = Split-Path -Parent $path
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

function Strip-FencedCodeBlocks([string]$text) {
  if ($null -eq $text) {
    return ""
  }

  return ([regex]::Replace($text, '(?ms)```.*?```|~~~.*?~~~', ''))
}

function Get-MarkdownSectionBody([string]$text, [string]$headingRegex) {
  if ($null -eq $text) {
    return ""
  }

  $pattern = '(?m)^\s*(?:' + $headingRegex + ')\s*$\r?\n'
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) {
    return ""
  }

  $start = $m.Index + $m.Length
  $tail = $text.Substring($start)
  $next = [regex]::Match($tail, '(?m)^\s*#{2,6}\s+')
  if ($next.Success) {
    return $tail.Substring(0, $next.Index)
  }

  return $tail
}

function Get-MarkdownH2SectionBody([string]$text, [string]$headingRegex) {
  if ($null -eq $text) {
    return ""
  }

  $pattern = '(?m)^\s*(?:' + $headingRegex + ')\s*$\r?\n'
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) {
    return ""
  }

  $start = $m.Index + $m.Length
  $tail = $text.Substring($start)
  $next = [regex]::Match($tail, '(?m)^\s*##\s+')
  if ($next.Success) {
    return $tail.Substring(0, $next.Index)
  }

  return $tail
}

function Get-CurrentPackagePath([string]$projectRoot, [string]$pointerPath) {
  if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) {
    return ""
  }

  $pointerText = Read-Text $pointerPath
  $m = [regex]::Match($pointerText, '(?m)^\s*current_package\s*:\s*(?<path>.*)\s*$')
  if (-not $m.Success) {
    return ""
  }

  $raw = $m.Groups["path"].Value.Trim().Trim('"', "'")
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return ""
  }

  return Resolve-PathValue -baseRoot $projectRoot -rawPath $raw
}

function Clear-CurrentPointer([string]$pointerPath) {
  Write-Utf8Text -path $pointerPath -text "# 当前方案包指针（自动维护）`ncurrent_package:`n"
}

function Get-ExecutionEvidence([string]$taskText) {
  $evidence = New-Object System.Collections.Generic.List[string]
  $textNoCode = Strip-FencedCodeBlocks $taskText
  $snapshotBody = Get-MarkdownH2SectionBody -text $textNoCode -headingRegex '##\s*上下文快照'
  $reviewBody = Get-MarkdownSectionBody -text $textNoCode -headingRegex '##\s*Review\s*记录'

  if ($textNoCode -match '(?m)^\s*-\s*\[(?:√|X|\?)\]\s+') {
    $evidence.Add("terminal_or_confirmation_task")
  }

  if (($textNoCode -match '(?m)^\s*-\s*\[-\]\s+') -and ($snapshotBody -notmatch '(?mi)\barchive_intent\s*[:：]\s*abandoned_unexecuted\b')) {
    $evidence.Add("skipped_task_without_abandon_intent")
  }

  if ($snapshotBody -match '(?mi)\bprogress_phase\s*[:：]\s*(mid|late|final)\b') {
    $evidence.Add("progress_checkpoint_after_start")
  }

  if ($snapshotBody -match '(?mi)\b(model_event|compact_event|threshold_event)\s*[:：]\s*\S') {
    $evidence.Add("runtime_or_compact_event")
  }

  if ($textNoCode -match '(?mi)\b(touched_files|verify_result|verify)\s*[:：]\s*\S') {
    $evidence.Add("touched_files_or_verify_signal")
  }

  $reviewLines = $reviewBody -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and
    -not ($_ -match '^（?仅在完成收尾时填写') -and
    -not ($_ -match '^小任务可只写') -and
    -not ($_ -match '^\(?仅在命中时填写')
  }

  if ($reviewLines.Count -gt 0) {
    $evidence.Add("review_record_present")
  }

  return @($evidence)
}

function Set-AbandonedTaskText([string]$taskText) {
  $updated = $taskText
  if ($updated -notmatch '(?mi)^\s*>\s*\*\*状态:\*\*\s*未执行（用户清理）') {
    $firstLine = [regex]::Match($updated, '^\s*#.*(?:\r?\n)?')
    if ($firstLine.Success) {
      $insertAt = $firstLine.Index + $firstLine.Length
      $updated = $updated.Insert($insertAt, "`n> **状态:** 未执行（用户清理）`n")
    } else {
      $updated = "> **状态:** 未执行（用户清理）`n`n" + $updated
    }
  }

  $updated = [regex]::Replace(
    $updated,
    '(?m)^(?<indent>\s*)-\s*\[\s\](?<rest>\s+.+)$',
    {
      param($m)
      $indent = $m.Groups["indent"].Value
      $rest = $m.Groups["rest"].Value
      return ("{0}- [-]{1}`n{0}  > 备注: 用户明确放弃执行（未执行清理）" -f $indent, $rest)
    }
  )

  $checkpoint = @"

### 未执行清理归档
- [SRC:USER] archive_intent: abandoned_unexecuted
- [SRC:USER] abandon_confirmed_by_user: yes
- [SRC:TOOL] progress_phase: final
- [SRC:TOOL] 验证: 未执行（用户放弃执行；这不是完成证据）
- [SRC:TOOL] 下一步唯一动作: `无；方案包已按未执行清理迁移` 预期: 等待新需求
"@

  if ($updated -match '(?m)^\s*##\s*上下文快照\s*$') {
    $reviewMatch = [regex]::Match($updated, '(?m)^\s*##\s*Review\s*记录\s*$')
    if ($reviewMatch.Success) {
      return $updated.Insert($reviewMatch.Index, $checkpoint + "`n")
    }

    return $updated.TrimEnd() + "`n" + $checkpoint + "`n"
  }

  return $updated.TrimEnd() + "`n`n## 上下文快照`n" + $checkpoint + "`n"
}

function Add-HistoryIndexEntry(
  [string]$indexPath,
  [string]$packageName,
  [string]$historyRelative,
  [string]$sourceRelative
) {
  if (Test-Path -LiteralPath $indexPath -PathType Container) {
    throw "history index path is a directory, not a file: $indexPath"
  }

  if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    Write-Utf8Text -path $indexPath -text "# 历史方案索引`n"
  }

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
  $entry = @"

- $timestamp | `$packageName` | abandoned_unexecuted | $historyRelative
  - source: `$sourceRelative`
  - archive_intent: abandoned_unexecuted
  - verify: not_run_user_abandoned
"@
  Add-Content -LiteralPath $indexPath -Value $entry -Encoding utf8
}

function Restore-TextFile([string]$path, [string]$originalText, [bool]$originalExists) {
  if ($originalExists) {
    Write-Utf8Text -path $path -text $originalText
  } elseif (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
  }
}

function Invoke-Rollback(
  [string]$sourcePath,
  [string]$destinationPath,
  [string]$taskPath,
  [string]$indexPath,
  [string]$pointerPath,
  [bool]$taskExistedBefore,
  [string]$taskTextBefore,
  [bool]$indexExistedBefore,
  [string]$indexTextBefore,
  [bool]$pointerExistedBefore,
  [string]$pointerTextBefore
) {
  $rollbackReport = [ordered]@{
    rollback_attempted = $true
    rollback_succeeded = $false
    rollback_errors = @()
  }

  try {
    if ((Test-Path -LiteralPath $destinationPath -PathType Container) -and (-not (Test-Path -LiteralPath $sourcePath -PathType Container))) {
      Move-Item -LiteralPath $destinationPath -Destination $sourcePath -Force
    }

    Restore-TextFile -path $taskPath -originalText $taskTextBefore -originalExists $taskExistedBefore
    Restore-TextFile -path $indexPath -originalText $indexTextBefore -originalExists $indexExistedBefore
    Restore-TextFile -path $pointerPath -originalText $pointerTextBefore -originalExists $pointerExistedBefore
    $rollbackReport.rollback_succeeded = $true
  } catch {
    $rollbackReport.rollback_errors += $_.Exception.Message
  }

  return $rollbackReport
}

function Emit-Report([hashtable]$report, [int]$exitCode) {
  if ($Json) {
    $report | ConvertTo-Json -Depth 32
  } else {
    if ($report.ok) {
      Write-Output ("OK: abandoned unexecuted plan archived: {0} -> {1}" -f $report.source_package, $report.history_package)
    } else {
      Write-Output "ERROR: abandoned plan cleanup failed."
      foreach ($err in @($report.errors)) {
        Write-Output ("- {0}" -f $err)
      }
    }
  }

  exit $exitCode
}

$report = [ordered]@{
  ok = $false
  tool = "abandon-plan-package"
  source_package = $null
  history_package = $null
  current_pointer_cleared = $false
  history_conflict = $false
  history_conflict_suffix = $null
  evidence = @()
  rollback_attempted = $false
  rollback_succeeded = $false
  errors = @()
  warnings = @()
}

try {
  $projectRootFull = Get-ProjectRoot
  $projectRootFull = [System.IO.Path]::GetFullPath($projectRootFull)
  $planRootFull = Resolve-PathValue -baseRoot $projectRootFull -rawPath $PlanRoot
  $historyRootFull = Resolve-PathValue -baseRoot $projectRootFull -rawPath $HistoryRoot
  $expectedPlanRoot = Join-Path $projectRootFull "HAGSWorks/plan"
  $expectedHistoryRoot = Join-Path $projectRootFull "HAGSWorks/history"
  $pointerPath = Join-Path $planRootFull "_current.md"
  $indexPath = Join-Path $historyRootFull "index.md"

  if (-not $ConfirmAbandon) {
    $report.errors += "Refusing to abandon a plan package without -ConfirmAbandon."
    Emit-Report -report $report -exitCode 1
  }

  if ([string]::IsNullOrWhiteSpace($Package)) {
    $report.errors += "-Package is required."
    Emit-Report -report $report -exitCode 1
  }

  if (-not (Test-Path -LiteralPath $planRootFull -PathType Container)) {
    $report.errors += "plan root not found: $PlanRoot (resolved: $planRootFull)"
    Emit-Report -report $report -exitCode 1
  }

  if (-not (Test-SamePath -left $planRootFull -right $expectedPlanRoot)) {
    $report.errors += "plan root must resolve to HAGSWorks/plan: $planRootFull"
    Emit-Report -report $report -exitCode 1
  }

  if (-not (Test-SamePath -left $historyRootFull -right $expectedHistoryRoot)) {
    $report.errors += "history root must resolve to HAGSWorks/history: $historyRootFull"
    Emit-Report -report $report -exitCode 1
  }

  $packageFull = Resolve-PathValue -baseRoot $projectRootFull -rawPath $Package
  if (-not (Test-Path -LiteralPath $packageFull -PathType Container)) {
    $report.errors += "package not found or not a directory: $Package (resolved: $packageFull)"
    Emit-Report -report $report -exitCode 1
  }

  $packageFull = (Resolve-Path -LiteralPath $packageFull).Path
  if (-not (Test-IsPathUnderDirectory -path $packageFull -directory $planRootFull)) {
    $report.errors += "package is outside plan root: $Package (resolved: $packageFull; expected under: $PlanRoot)"
    Emit-Report -report $report -exitCode 1
  }

  $requiredFiles = @("why.md", "how.md", "task.md")
  foreach ($requiredFile in $requiredFiles) {
    $requiredPath = Join-Path $packageFull $requiredFile
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      $report.errors += "package is incomplete; missing $requiredFile"
    } elseif ([string]::IsNullOrWhiteSpace((Read-Text $requiredPath))) {
      $report.errors += "package is incomplete; empty $requiredFile"
    }
  }

  if ($report.errors.Count -gt 0) {
    Emit-Report -report $report -exitCode 1
  }

  $currentPackageFull = Get-CurrentPackagePath -projectRoot $projectRootFull -pointerPath $pointerPath
  $isCurrentPackage = Test-SamePath -left $currentPackageFull -right $packageFull
  if ($isCurrentPackage -and (-not $ConfirmCurrent)) {
    $report.errors += "package is current_package; refusing abandoned cleanup without -ConfirmCurrent."
    Emit-Report -report $report -exitCode 1
  }

  $taskPath = Join-Path $packageFull "task.md"
  $taskTextBefore = Read-Text $taskPath
  $evidence = Get-ExecutionEvidence -taskText $taskTextBefore
  $report.evidence = @($evidence)
  if ($evidence.Count -gt 0) {
    $report.errors += ("package has execution evidence and must use resume/Archive Readiness Gate, not abandoned cleanup: {0}" -f ($evidence -join ", "))
    Emit-Report -report $report -exitCode 1
  }

  $packageName = Split-Path -Leaf $packageFull
  $nameMatch = [regex]::Match($packageName, '^(?<year>\d{4})(?<month>\d{2})\d{6}_.+')
  if (-not $nameMatch.Success) {
    $report.errors += "package name must start with YYYYMMDDHHMM_: $packageName"
    Emit-Report -report $report -exitCode 1
  }

  $historyMonth = "{0}-{1}" -f $nameMatch.Groups["year"].Value, $nameMatch.Groups["month"].Value
  $historyMonthDir = Join-Path $historyRootFull $historyMonth
  New-Item -ItemType Directory -Path $historyMonthDir -Force | Out-Null

  $destinationBase = Join-Path $historyMonthDir $packageName
  $destinationFull = $destinationBase
  $suffix = 2
  while (Test-Path -LiteralPath $destinationFull) {
    $report.history_conflict = $true
    $report.history_conflict_suffix = "_v${suffix}"
    $destinationFull = "${destinationBase}_v${suffix}"
    $suffix++
  }

  $destinationFull = [System.IO.Path]::GetFullPath($destinationFull)
  if (-not (Test-IsPathUnderDirectory -path $destinationFull -directory $historyRootFull)) {
    $report.errors += "resolved history destination is outside history root: $destinationFull"
    Emit-Report -report $report -exitCode 1
  }

  $destinationName = Split-Path -Leaf $destinationFull
  $historyRelative = ("HAGSWorks/history/{0}/{1}/" -f $historyMonth, $destinationName)
  $sourceRelative = ("HAGSWorks/plan/{0}/" -f $packageName)
  $report.source_package = $sourceRelative
  $report.history_package = $historyRelative

  $taskExistedBefore = Test-Path -LiteralPath $taskPath -PathType Leaf
  $indexExistedBefore = Test-Path -LiteralPath $indexPath -PathType Leaf
  $indexTextBefore = $null
  if ($indexExistedBefore) {
    $indexTextBefore = Read-Text $indexPath
  } elseif (Test-Path -LiteralPath $indexPath -PathType Container) {
    $report.errors += "history index path is a directory, not a file: $indexPath"
    Emit-Report -report $report -exitCode 1
  }

  $pointerExistedBefore = Test-Path -LiteralPath $pointerPath -PathType Leaf
  $pointerTextBefore = $null
  if ($pointerExistedBefore) {
    $pointerTextBefore = Read-Text $pointerPath
  }

  $moveCompleted = $false
  try {
    Write-Utf8Text -path $taskPath -text (Set-AbandonedTaskText -taskText $taskTextBefore)
    Move-Item -LiteralPath $packageFull -Destination $destinationFull
    $moveCompleted = $true

    Add-HistoryIndexEntry -indexPath $indexPath -packageName $destinationName -historyRelative $historyRelative -sourceRelative $sourceRelative
    if ($isCurrentPackage) {
      Clear-CurrentPointer -pointerPath $pointerPath
      $report.current_pointer_cleared = $true
    }

    $report.ok = $true
    Emit-Report -report $report -exitCode 0
  } catch {
    $rollback = Invoke-Rollback -sourcePath $packageFull -destinationPath $destinationFull -taskPath $taskPath -indexPath $indexPath -pointerPath $pointerPath -taskExistedBefore $taskExistedBefore -taskTextBefore $taskTextBefore -indexExistedBefore $indexExistedBefore -indexTextBefore $indexTextBefore -pointerExistedBefore $pointerExistedBefore -pointerTextBefore $pointerTextBefore
    $report.rollback_attempted = $rollback.rollback_attempted
    $report.rollback_succeeded = $rollback.rollback_succeeded
    $report.errors += @($rollback.rollback_errors)
    if ($moveCompleted -and (-not $rollback.rollback_succeeded)) {
      $report.errors += "abandoned cleanup failed after move and rollback was incomplete; half-migration state may remain."
    }

    $report.errors += $_.Exception.Message
    Emit-Report -report $report -exitCode 1
  }
} catch {
  $report.errors += $_.Exception.Message
  Emit-Report -report $report -exitCode 1
}
