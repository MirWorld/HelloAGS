param(
  [string]$PlanRoot = "HAGSWorks/plan",
  [string]$Package = "",
  [ValidateSet("plan", "exec")]
  [string]$Mode = "plan",
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

function Read-Text([string]$path) {
  return (Get-Content -LiteralPath $path -Raw)
}

function Strip-FencedCodeBlocks([string]$text) {
  if ($null -eq $text) {
    return ""
  }
  # Remove fenced blocks to avoid matching example snippets.
  return ([regex]::Replace($text, '(?ms)```.*?```|~~~.*?~~~', ''))
}

function Strip-HtmlComments([string]$text) {
  if ($null -eq $text) {
    return ""
  }
  return ([regex]::Replace($text, '(?ms)<!--.*?-->', ''))
}

function Get-MarkdownSectionBody([string]$text, [string]$headingRegex) {
  if ($null -eq $text) {
    return ""
  }
  $pattern = '(?ms)^\s*' + $headingRegex + '\s*$\r?\n(?<body>.*?)(?=^\s*#{2,6}\s+|\z)'
  $m = [regex]::Match($text, $pattern)
  if ($m.Success) {
    return $m.Groups["body"].Value
  }
  return ""
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
  mode = $Mode
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
      if ($text -notmatch '(?m)verify_min\s*[:：]\s*\S') {
        Add-Error "package '${pkgName}' how.md missing verify_min (expected a line like: verify_min: <command/steps>)"
      } else {
        $textNoCode = Strip-FencedCodeBlocks $text
        if ($Mode -eq "exec" -and $textNoCode -match '(?mi)verify_min\s*[:：]\s*unknown\b') {
          Add-Error "package '${pkgName}' how.md verify_min is unknown (exec mode requires a runnable verify_min)"
        }
      }
    }

    if ($fileName -eq "task.md") {
      $textNoCode = Strip-FencedCodeBlocks $text
      $taskItemAnyPattern = '(?m)^\s*-\s*\[(?:\s|√|X|-|\?)\]\s+'
      $taskItemOpenPattern = '(?m)^\s*-\s*\[\s\]\s+'

      if ($textNoCode -notmatch $taskItemAnyPattern) {
        Add-Error "package '${pkgName}' task.md has no task items (- [ ]/[√]/[X]/[-]/[?])"
      }

      if ($Mode -eq "exec") {
        if ($textNoCode -notmatch $taskItemOpenPattern) {
          Add-Error "package '${pkgName}' task.md has no pending tasks (- [ ]) (exec mode requires at least one pending task). If you need follow-up work, add a Delta to ## 上下文快照 and create a new - [ ] task."
        }

        $pendingBody = Get-MarkdownSectionBody -text $textNoCode -headingRegex '###\s*待用户输入（Pending）'
        $pendingBody = Strip-HtmlComments $pendingBody
        $pendingLines = $pendingBody -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        # Backward compatible: ignore template-like placeholder TODO lines that still contain ellipsis.
        $pendingLines = $pendingLines | Where-Object { -not (($_ -match '^\-\s*\[SRC:TODO\]') -and (($_ -match '…') -or ($_ -match '\.\.\.'))) }
        if ($pendingLines.Count -gt 0) {
          Add-Error "package '${pkgName}' task.md has unresolved Pending items (exec mode requires Pending to be empty)"
        }
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

