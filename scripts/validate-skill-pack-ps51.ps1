param(
  [switch]$CheckCodexCopy
)

$ErrorActionPreference = "Stop"

function Fail([string]$message) {
  Write-Error $message
  exit 1
}

if (-not $PSScriptRoot) {
  Fail "Cannot determine script directory; run this script from a file on disk."
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$scriptPath = Join-Path $PSScriptRoot "validate-skill-pack.ps1"

if (-not (Test-Path -LiteralPath $scriptPath)) {
  Fail "Missing script: $scriptPath"
}

$hadDefault = $PSDefaultParameterValues.ContainsKey("Get-Content:Encoding")
$oldDefault = $PSDefaultParameterValues["Get-Content:Encoding"]
$PSDefaultParameterValues["Get-Content:Encoding"] = "utf8"

try {
  Push-Location $repoRoot

  $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)
  }

  $sb = [ScriptBlock]::Create($text)
  & $sb @PSBoundParameters
} finally {
  Pop-Location
  if ($hadDefault) {
    $PSDefaultParameterValues["Get-Content:Encoding"] = $oldDefault
  } else {
    $PSDefaultParameterValues.Remove("Get-Content:Encoding")
  }
}
