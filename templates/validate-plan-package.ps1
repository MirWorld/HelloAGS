param(
  [string]$PlanRoot = "HAGWroks/plan",
  [string]$Package = "",
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
  if ($PSScriptRoot) {
    try {
      $twoUp = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\\..")).Path
      if (Test-Path -LiteralPath (Join-Path $twoUp "HAGWroks")) {
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

function Read-Text([string]$path) {
  return (Get-Content -LiteralPath $path -Raw)
}

function Text-HasAll([string]$text, [string[]]$needles) {
  foreach ($needle in $needles) {
    if ($text -notmatch [regex]::Escape($needle)) {
      return $false
    }
  }
  return $true
}

$report = [ordered]@{
  tool = "validate-plan-package"
  ok = $true
  project_root = ""
  plan_root = ""
  checked_packages = @()
  errors = @()
}

function Add-Error([string]$message) {
  $script:report.ok = $false
  $script:report.errors += $message
}

function Emit-Json() {
  $script:report | ConvertTo-Json -Depth 8
}

$projectRoot = Get-ProjectRoot
$planRootFull = (Join-Path $projectRoot $PlanRoot)
$report.project_root = $projectRoot
$report.plan_root = $planRootFull

if (-not (Test-Path -LiteralPath $planRootFull)) {
  Add-Error "plan root not found: $PlanRoot (resolved: $planRootFull)"
  if ($Json) { Emit-Json }
  exit 1
}

$packages = @()
if (-not [string]::IsNullOrWhiteSpace($Package)) {
  $packageFull = Join-Path $projectRoot $Package
  if (-not (Test-Path -LiteralPath $packageFull)) {
    Add-Error "package not found: $Package (resolved: $packageFull)"
    if ($Json) { Emit-Json }
    exit 1
  }
  $packages = @((Resolve-Path -LiteralPath $packageFull).Path)
} else {
  $packages = Get-ChildItem -LiteralPath $planRootFull -Directory | Select-Object -ExpandProperty FullName
}

if ($packages.Count -eq 0) {
  Add-Error "no plan packages found under: $planRootFull"
  if ($Json) { Emit-Json }
  exit 1
}

$requiredFiles = @("why.md", "how.md", "task.md")
$needlesByFile = @{
  "why.md" = @("## 对齐摘要")
  "how.md" = @("## 执行域声明（Allow/Deny）")
  "task.md" = @("## 上下文快照", "### 下一步唯一动作（可执行）", "下一步唯一动作:")
}

foreach ($pkg in $packages) {
  $pkgName = Split-Path -Leaf $pkg
  $report.checked_packages += $pkgName

  foreach ($fileName in $requiredFiles) {
    $filePath = Join-Path $pkg $fileName
    if (-not (Test-Path -LiteralPath $filePath)) {
      Add-Error "package '${pkgName}' missing file: ${fileName}"
      continue
    }

    $item = Get-Item -LiteralPath $filePath
    if ($item.Length -le 0) {
      Add-Error "package '${pkgName}' empty file: ${fileName}"
      continue
    }

    $text = Read-Text $filePath
    $needles = $needlesByFile[$fileName]
    if ($needles -and -not (Text-HasAll -text $text -needles $needles)) {
      Add-Error "package '${pkgName}' missing required sections in ${fileName}"
    }

    if ($fileName -eq "how.md") {
      if ($text -notmatch '(?m)verify_min\\s*[:：]\\s*\\S') {
        Add-Error "package '${pkgName}' how.md missing verify_min (expected a line like: verify_min: <command/steps>)"
      }
    }

    if ($fileName -eq "task.md") {
      if ($text -notmatch [regex]::Escape("- [ ]")) {
        Add-Error "package '${pkgName}' task.md has no task items (- [ ])"
      }
    }
  }
}

if ($Json) {
  Emit-Json
}

if (-not $report.ok) {
  $summary = "Plan package validation failed:`n" + ($report.errors -join "`n")
  Write-Error $summary
  exit 1
}

Write-Output "OK: plan package validation passed ($($packages.Count) package(s))"
