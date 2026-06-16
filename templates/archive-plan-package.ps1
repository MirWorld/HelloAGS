param(
  [string]$ProjectRoot = "",
  [string]$PlanRoot = "HAGSWorks/plan",
  [string]$HistoryRoot = "HAGSWorks/history",
  [string]$Package = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Write-Utf8Text([string]$path, [string]$text) {
  $parent = Split-Path -Parent $path
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

function Read-Text([string]$path) {
  return (Get-Content -LiteralPath $path -Raw)
}

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
    return (Resolve-Path -LiteralPath $ProjectRoot).Path
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

function Test-IsPathUnderDirectory([string]$path, [string]$directory) {
  if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($directory)) {
    return $false
  }

  try {
    $fullPath = [System.IO.Path]::GetFullPath($path)
    $fullDirectory = [System.IO.Path]::GetFullPath($directory)
  } catch {
    return $false
  }

  $separator = [System.IO.Path]::DirectorySeparatorChar
  $altSeparator = [System.IO.Path]::AltDirectorySeparatorChar
  if (-not ($fullDirectory.EndsWith($separator) -or $fullDirectory.EndsWith($altSeparator))) {
    $fullDirectory = $fullDirectory + $separator
  }

  return $fullPath.StartsWith($fullDirectory, [System.StringComparison]::OrdinalIgnoreCase)
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

function Resolve-PathValue([string]$baseRoot, [string]$rawPath) {
  $normalized = $rawPath.Trim().Trim('"', "'", [char]0x60).Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  if ([System.IO.Path]::IsPathRooted($normalized)) {
    return [System.IO.Path]::GetFullPath($normalized)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $baseRoot $normalized))
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

  $raw = $m.Groups["path"].Value
  $raw = [regex]::Replace($raw, '\s+#.*$', '').Trim()
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return ""
  }

  try {
    return (Resolve-PathValue -baseRoot $projectRoot -rawPath $raw)
  } catch {
    return ""
  }
}

function Clear-CurrentPointer([string]$pointerPath) {
  Write-Utf8Text -path $pointerPath -text "# 当前方案包指针（自动维护）`ncurrent_package:`n"
}

function Invoke-ArchiveValidator([string]$validatorPath, [string]$packagePath) {
  $args = @(
    "-NoProfile",
    "-File", $validatorPath,
    "-Mode", "archive",
    "-Package", $packagePath,
    "-Json"
  )

  $raw = & pwsh @args
  $exitCode = $LASTEXITCODE
  $text = ($raw -join "`n")

  if ([string]::IsNullOrWhiteSpace($text)) {
    return [ordered]@{
      ok = $false
      exit_code = $exitCode
      errors = @("validate-plan-package returned empty output.")
      warnings = @()
    }
  }

  try {
    $parsed = $text | ConvertFrom-Json -Depth 32
  } catch {
    return [ordered]@{
      ok = $false
      exit_code = $exitCode
      errors = @("validate-plan-package returned non-json output: $text")
      warnings = @()
    }
  }

  return [ordered]@{
    ok = (($exitCode -eq 0) -and ($parsed.ok -eq $true))
    exit_code = $exitCode
    errors = @($parsed.errors)
    warnings = @($parsed.warnings)
  }
}

function Add-HistoryIndexEntry(
  [string]$indexPath,
  [string]$packageName,
  [string]$historyRelative,
  [string]$sourceRelative
) {
  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $entry = @"

- $timestamp | ``$packageName`` | archived | $historyRelative
  - source: $sourceRelative
  - verify: validate-plan-package.ps1 -Mode archive passed
"@
  Add-Content -LiteralPath $indexPath -Value $entry -Encoding utf8
}

function Restore-TextFile([string]$path, [string]$originalText, [bool]$originalExists) {
  if ($originalExists) {
    if (Test-Path -LiteralPath $path) {
      try {
        $attributes = [System.IO.File]::GetAttributes($path)
        if (($attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
          [System.IO.File]::SetAttributes($path, ($attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)))
        }
      } catch {
        # ignore and let write surface a concrete error if needed
      }
    }
    Write-Utf8Text -path $path -text $originalText
  } elseif (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
  }
}

function Invoke-ArchiveRollback(
  [string]$sourcePath,
  [string]$destinationPath,
  [string]$indexPath,
  [string]$pointerPath,
  [bool]$indexExistedBefore,
  [string]$indexTextBefore,
  [bool]$pointerExistedBefore,
  [string]$pointerTextBefore
) {
  $rollbackReport = [ordered]@{
    rollback_attempted = $false
    rollback_succeeded = $false
    rollback_errors = @()
  }

  $rollbackReport.rollback_attempted = $true
  try {
    if ((Test-Path -LiteralPath $destinationPath -PathType Container) -and (-not (Test-Path -LiteralPath $sourcePath -PathType Container))) {
      Move-Item -LiteralPath $destinationPath -Destination $sourcePath -Force
    }
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
    $report | ConvertTo-Json -Depth 12
  } elseif ($report.ok) {
    Write-Output ("OK: archived {0} -> {1}" -f $report.source_package, $report.history_package)
  } else {
    Write-Error (($report.errors | ForEach-Object { $_ }) -join "`n")
  }
  exit $exitCode
}

$report = [ordered]@{
  tool = "archive-plan-package"
  ok = $false
  project_root = ""
  plan_root = ""
  history_root = ""
  source_package = ""
  history_package = ""
  history_conflict = $false
  history_conflict_suffix = ""
  current_pointer_cleared = $false
  index_updated = $false
  rollback_attempted = $false
  rollback_succeeded = $false
  validation = $null
  errors = @()
  warnings = @()
}

try {
  $projectRootFull = Get-ProjectRoot
  $planRootFull = [System.IO.Path]::GetFullPath((Join-Path $projectRootFull $PlanRoot))
  $historyRootFull = [System.IO.Path]::GetFullPath((Join-Path $projectRootFull $HistoryRoot))
  $expectedPlanRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRootFull "HAGSWorks/plan"))
  $expectedHistoryRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRootFull "HAGSWorks/history"))
  $pointerPath = Join-Path $planRootFull "_current.md"
  $validatorPath = Join-Path $projectRootFull "HAGSWorks/scripts/validate-plan-package.ps1"
  $indexPath = Join-Path $historyRootFull "index.md"

  $report.project_root = $projectRootFull
  $report.plan_root = $planRootFull
  $report.history_root = $historyRootFull

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

  if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    $report.errors += "validator not found: HAGSWorks/scripts/validate-plan-package.ps1"
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

  $packageName = Split-Path -Leaf $packageFull
  $nameMatch = [regex]::Match($packageName, '^(?<year>\d{4})(?<month>\d{2})\d{6}_.+')
  if (-not $nameMatch.Success) {
    $report.errors += "package name must start with YYYYMMDDHHMM_: $packageName"
    Emit-Report -report $report -exitCode 1
  }

  $validation = Invoke-ArchiveValidator -validatorPath $validatorPath -packagePath $packageFull
  $report.validation = $validation
  $report.warnings += @($validation.warnings)
  if (-not $validation.ok) {
    $report.errors += @($validation.errors)
    if ($report.errors.Count -eq 0) {
      $report.errors += "Archive Readiness Gate failed."
    }
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

  $indexExistedBefore = Test-Path -LiteralPath $indexPath -PathType Leaf
  $indexTextBefore = $null
  if ($indexExistedBefore) {
    $indexTextBefore = Read-Text $indexPath
  } else {
    Write-Utf8Text -path $indexPath -text "# 历史方案索引`n"
  }

  $pointerExistedBefore = Test-Path -LiteralPath $pointerPath -PathType Leaf
  $pointerTextBefore = $null
  if ($pointerExistedBefore) {
    $pointerTextBefore = Read-Text $pointerPath
  }

  $moveCompleted = $false
  try {
    Move-Item -LiteralPath $packageFull -Destination $destinationFull
    $moveCompleted = $true

    Add-HistoryIndexEntry -indexPath $indexPath -packageName $destinationName -historyRelative $historyRelative -sourceRelative $sourceRelative
    $report.index_updated = $true

    $currentPackageFull = Get-CurrentPackagePath -projectRoot $projectRootFull -pointerPath $pointerPath
    if (Test-SamePath -left $currentPackageFull -right $packageFull) {
      Clear-CurrentPointer -pointerPath $pointerPath
      $report.current_pointer_cleared = $true
    }

    $report.ok = $true
    Emit-Report -report $report -exitCode 0
  } catch {
    if ($moveCompleted) {
      $report.rollback_attempted = $true
      $rollback = Invoke-ArchiveRollback -sourcePath $packageFull -destinationPath $destinationFull -indexPath $indexPath -pointerPath $pointerPath -indexExistedBefore $indexExistedBefore -indexTextBefore $indexTextBefore -pointerExistedBefore $pointerExistedBefore -pointerTextBefore $pointerTextBefore
      $report.rollback_succeeded = $rollback.rollback_succeeded
      $report.errors += @($rollback.rollback_errors)
      if (-not $rollback.rollback_succeeded) {
        $report.errors += "archive failed after move and rollback was incomplete; half-migration state may remain."
      }
    }

    $report.errors += $_.Exception.Message
    Emit-Report -report $report -exitCode 1
  }
} catch {
  $report.errors += $_.Exception.Message
  Emit-Report -report $report -exitCode 1
}
