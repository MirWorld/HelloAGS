param(
  [string]$ActiveContextPath = "HAGSWorks/active_context.md",
  [ValidateSet("loose", "strict")]
  [string]$Mode = "loose"
)

$ErrorActionPreference = "Stop"

function Fail([string]$message) {
  Write-Error $message
  exit 1
}

function Resolve-ProjectRoot([string]$activeContextPath) {
  $resolved = Resolve-Path -LiteralPath $activeContextPath
  $workspaceDir = Split-Path -Parent $resolved.Path
  return (Resolve-Path -LiteralPath (Split-Path -Parent $workspaceDir)).Path
}

function Parse-CodePointer([string]$line) {
  $patterns = @(
    @{ re = "\[SRC:CODE\]\s+(?<path>\S+?):(?<line>\d+)\s+(?<rest>.+)$"; hasLine = $true },
    @{ re = "\[SRC:CODE\]\s+(?<path>\S+?)#L(?<line>\d+)\s+(?<rest>.+)$"; hasLine = $true },
    @{ re = "\[SRC:CODE\]\s+(?<path>\S+?)\s+(?<rest>.+)$"; hasLine = $false }
  )

  foreach ($p in $patterns) {
    $m = [regex]::Match($line, $p.re)
    if ($m.Success) {
      $lineValue = $null
      if ($p.hasLine) {
        $lineValue = [int]$m.Groups["line"].Value
      }

      return [pscustomobject]@{
        path = $m.Groups["path"].Value
        line = $lineValue
        rest = $m.Groups["rest"].Value
        hasLine = $p.hasLine
      }
    }
  }

  return $null
}

if (-not (Test-Path -LiteralPath $ActiveContextPath)) {
  Fail "active_context not found: $ActiveContextPath"
}

$projectRoot = Resolve-ProjectRoot $ActiveContextPath
$lines = Get-Content -LiteralPath $ActiveContextPath

if ($lines.Count -gt 120) {
  Fail "active_context exceeds 120 lines (current: $($lines.Count)): $ActiveContextPath"
}

$requiredHeadings = @(
  "## Modules (Public Surface)",
  "## Contracts Index",
  "## Data Flow Guarantees",
  "## Known Gaps / Risks",
  "## Next"
)

foreach ($heading in $requiredHeadings) {
  if (-not ($lines -contains $heading)) {
    Fail "Missing required heading '$heading': $ActiveContextPath"
  }
}

$currentSection = ""
$modulesSectionSeen = $false
$apiEntryCount = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
  $lineNo = $i + 1
  $line = $lines[$i]

  $headingMatch = [regex]::Match($line, "^\s*##\s+(?<h>.+?)\s*$")
  if ($headingMatch.Success) {
    $currentSection = $headingMatch.Groups["h"].Value.Trim()
    if ($currentSection -eq "Modules (Public Surface)") {
      $modulesSectionSeen = $true
    }
    continue
  }

  if ($line -match "\[SRC:INFER\]") {
    if ($currentSection -ne "Known Gaps / Risks") {
      Fail "Line $lineNo - [SRC:INFER] must be inside 'Known Gaps / Risks': $ActiveContextPath"
    }
  }

  if ($line -match "\[SRC:TODO\]") {
    if ($currentSection -ne "Known Gaps / Risks" -and $currentSection -ne "Next") {
      Fail "Line $lineNo - [SRC:TODO] must be inside 'Known Gaps / Risks' or 'Next': $ActiveContextPath"
    }
  }

  if (-not $modulesSectionSeen) {
    continue
  }

  if ($currentSection -ne "Modules (Public Surface)") {
    continue
  }

  if ($line -notmatch "\[SRC:CODE\]") {
    continue
  }

  $ptr = Parse-CodePointer $line
  if ($null -eq $ptr) {
    Fail "Line $lineNo - invalid [SRC:CODE] pointer (expected 'path symbol', 'path:line symbol' or 'path#Lline symbol'): $line"
  }

  if ($Mode -eq "strict" -and -not $ptr.hasLine) {
    Fail "Line $lineNo - strict mode requires a line number in [SRC:CODE] pointer (use 'path:line symbol' or 'path#Lline symbol'): $line"
  }

  $pathValue = $ptr.path
  $lineValue = $ptr.line
  $rest = $ptr.rest.Trim()
  if ([string]::IsNullOrWhiteSpace($rest)) {
    Fail "Line $lineNo - [SRC:CODE] missing symbol (expected 'path symbol')"
  }

  $apiEntryCount++

  $symbolPart = $rest
  foreach ($separator in @(" - ", " — ", " – ")) {
    $idx = $symbolPart.IndexOf($separator)
    if ($idx -gt 0) {
      $symbolPart = $symbolPart.Substring(0, $idx)
      break
    }
  }
  $symbolPart = $symbolPart.Trim()
  if ([string]::IsNullOrWhiteSpace($symbolPart)) {
    Fail "Line $lineNo - [SRC:CODE] missing symbol (expected 'path symbol')"
  }
  if ($symbolPart -match "\s") {
    Fail "Line $lineNo - [SRC:CODE] symbol must be a single grep key (no spaces). Use a function/class/handler name. Got: '$symbolPart'"
  }

  $resolvedPath = $pathValue
  if (-not ([System.IO.Path]::IsPathRooted($resolvedPath))) {
    $resolvedPath = Join-Path $projectRoot $resolvedPath
  }

  if (-not (Test-Path -LiteralPath $resolvedPath)) {
    Fail "Line $lineNo - [SRC:CODE] file not found: $pathValue (resolved: $resolvedPath)"
  }

  $targetLines = Get-Content -LiteralPath $resolvedPath
  if ($ptr.hasLine) {
    if ($lineValue -lt 1 -or $lineValue -gt $targetLines.Count) {
      Fail "Line $lineNo - [SRC:CODE] line out of range: ${pathValue}:$lineValue (file lines: $($targetLines.Count))"
    }
  }

  $searchKey = $symbolPart
  if ($searchKey.Contains("(")) {
    $searchKey = $searchKey.Split("(")[0].Trim()
  }
  if ([string]::IsNullOrWhiteSpace($searchKey)) {
    $searchKey = $symbolPart
  }

  $matchLines = New-Object System.Collections.Generic.List[int]
  for ($j = 1; $j -le $targetLines.Count; $j++) {
    if ($targetLines[$j - 1].IndexOf($searchKey, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      $matchLines.Add($j)
    }
  }

  if ($matchLines.Count -eq 0) {
    Fail "Line $lineNo - [SRC:CODE] symbol not found in file: $symbolPart (search: $searchKey). File: $pathValue"
  }

  if ($Mode -eq "strict") {
    $radius = 20
    $start = [Math]::Max(1, $lineValue - $radius)
    $end = [Math]::Min($targetLines.Count, $lineValue + $radius)

    $foundNear = $false
    for ($j = $start; $j -le $end; $j++) {
      if ($targetLines[$j - 1].IndexOf($searchKey, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $foundNear = $true
        break
      }
    }

    if (-not $foundNear) {
      $shown = ($matchLines | Select-Object -First 10) -join ", "
      Fail "Line $lineNo - [SRC:CODE] symbol not found near referenced line: ${pathValue}:$lineValue ($symbolPart). Possible drift; found at line(s): $shown"
    }
  } elseif ($ptr.hasLine) {
    $radius = 20
    $start = [Math]::Max(1, $lineValue - $radius)
    $end = [Math]::Min($targetLines.Count, $lineValue + $radius)

    $foundNear = $false
    for ($j = $start; $j -le $end; $j++) {
      if ($targetLines[$j - 1].IndexOf($searchKey, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $foundNear = $true
        break
      }
    }

    if (-not $foundNear) {
      $shown = ($matchLines | Select-Object -First 5) -join ", "
      Write-Output "WARN: Line $lineNo - [SRC:CODE] symbol not found near referenced line: ${pathValue}:$lineValue ($symbolPart). Possible drift; found at line(s): $shown"
    }
  }
}

Write-Output "OK: active_context validation passed"
Write-Output "- File: $ActiveContextPath"
Write-Output "- Mode: $Mode"
Write-Output "- Lines: $($lines.Count) (<= 120)"
Write-Output "- ProjectRoot: $projectRoot"
Write-Output "- Public API entries (Modules section, [SRC:CODE]): $apiEntryCount"

