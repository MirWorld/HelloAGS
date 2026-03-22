param(
  [string]$InputFile = "",
  [string]$ProjectRoot = ""
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

    if ($ok -and ($current -is [string]) -and -not [string]::IsNullOrWhiteSpace($current)) {
      return $current.Trim()
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

function Resolve-CurrentPackagePath([string]$projectRoot, [string]$pointerValue) {
  if ([string]::IsNullOrWhiteSpace($pointerValue)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($pointerValue)) {
    return $pointerValue
  }

  return (Join-Path $projectRoot $pointerValue)
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

$pointerFile = Join-Path $projectRootResolved "HAGSWorks/plan/_current.md"
if (-not (Test-Path -LiteralPath $pointerFile)) {
  Write-HookOutputJson
  exit 0
}

$pointerText = Read-Utf8Text -path $pointerFile
$match = [regex]::Match($pointerText, '(?m)^\s*current_package\s*:\s*(?<path>.*)\s*$')
if (-not $match.Success) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md missing current_package key. next=修复指针格式"
  exit 0
}

$rawPointer = [regex]::Replace($match.Groups["path"].Value, '\s+#.*$', '').Trim()
if ([string]::IsNullOrWhiteSpace($rawPointer)) {
  Write-HookOutputJson
  exit 0
}

$resolvedPackage = Resolve-CurrentPackagePath -projectRoot $projectRootResolved -pointerValue $rawPointer
$planRoot = (Join-Path $projectRootResolved "HAGSWorks/plan")
$historyRoot = (Join-Path $projectRootResolved "HAGSWorks/history")

try {
  $planRootFull = [System.IO.Path]::GetFullPath($planRoot)
  $historyRootFull = [System.IO.Path]::GetFullPath($historyRoot)
  $resolvedPackageFull = [System.IO.Path]::GetFullPath($resolvedPackage)
} catch {
  Write-HookOutputJson -SystemMessage "WARN: current_package path cannot be normalized: '$rawPointer'. next=修复指针路径"
  exit 0
}

if ($resolvedPackageFull.StartsWith($historyRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md points to history: '$rawPointer'. next=改回 HAGSWorks/plan 下的有效方案包"
  exit 0
}

if (-not $resolvedPackageFull.StartsWith($planRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md points outside plan root: '$rawPointer'. next=改回 HAGSWorks/plan 下的有效方案包"
  exit 0
}

if (-not (Test-Path -LiteralPath $resolvedPackageFull -PathType Container)) {
  Write-HookOutputJson -SystemMessage "WARN: _current.md current_package directory not found: '$rawPointer'. next=修复指针或重新选包"
  exit 0
}

$requiredFiles = @("why.md", "how.md", "task.md")
$missing = @()
foreach ($name in $requiredFiles) {
  $full = Join-Path $resolvedPackageFull $name
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    $missing += $name
    continue
  }

  $content = Read-Utf8Text -path $full
  if ([string]::IsNullOrWhiteSpace($content)) {
    $missing += $name
  }
}

if ($missing.Count -gt 0) {
  Write-HookOutputJson -SystemMessage ("WARN: _current.md points to incomplete package: '{0}' missing={1}. next=修复方案包或重新选包" -f $rawPointer, ($missing -join ","))
  exit 0
}

Write-HookOutputJson
