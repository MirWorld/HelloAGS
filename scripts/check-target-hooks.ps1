param(
  [string]$ProjectRoot = "",
  [string]$SkillRoot = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) {
    return ""
  }
  return [System.IO.Path]::GetFullPath($path)
}

function Read-Utf8Text([string]$path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)
  }
  return $text
}

function New-Check([string]$name, [bool]$ok, [string]$message) {
  return [ordered]@{
    name = $name
    ok = $ok
    message = $message
  }
}

function Add-Check([System.Collections.ArrayList]$checks, [string]$name, [bool]$ok, [string]$message) {
  [void]$checks.Add((New-Check -name $name -ok $ok -message $message))
}

function Resolve-SkillRoot([string]$explicitSkillRoot) {
  if (-not [string]::IsNullOrWhiteSpace($explicitSkillRoot)) {
    return Resolve-FullPath $explicitSkillRoot
  }

  if (-not [string]::IsNullOrWhiteSpace($env:HELLOAGENTS_SKILL_ROOT)) {
    return Resolve-FullPath $env:HELLOAGENTS_SKILL_ROOT
  }

  $codexHome = $env:CODEX_HOME
  if ([string]::IsNullOrWhiteSpace($codexHome)) {
    $codexHome = Join-Path $HOME ".codex"
  }
  return Resolve-FullPath (Join-Path $codexHome "skills/helloagents")
}

function Test-CodexHooksEnabled([string]$configText) {
  return ($configText -match '(?im)^\s*codex_hooks\s*=\s*true\s*(?:#.*)?$')
}

function Test-HookCommandTargetsScript([string]$command, [string]$scriptName) {
  if ([string]::IsNullOrWhiteSpace($command)) {
    return $false
  }
  return ($command -match [regex]::Escape($scriptName))
}

$checks = [System.Collections.ArrayList]::new()
$projectRootResolved = ""
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
  $projectRootResolved = (Get-Location).Path
} else {
  $projectRootResolved = Resolve-FullPath $ProjectRoot
}

Add-Check $checks "project_root_exists" (Test-Path -LiteralPath $projectRootResolved -PathType Container) $projectRootResolved

$codexDir = Join-Path $projectRootResolved ".codex"
$configPath = Join-Path $codexDir "config.toml"
$hooksPath = Join-Path $codexDir "hooks.json"

$configExists = Test-Path -LiteralPath $configPath -PathType Leaf
Add-Check $checks "config_toml_exists" $configExists $configPath
if ($configExists) {
  $configText = Read-Utf8Text $configPath
  Add-Check $checks "codex_hooks_enabled" (Test-CodexHooksEnabled $configText) "expect: [features] codex_hooks = true"
} else {
  Add-Check $checks "codex_hooks_enabled" $false "missing .codex/config.toml"
}

$hooksExists = Test-Path -LiteralPath $hooksPath -PathType Leaf
Add-Check $checks "hooks_json_exists" $hooksExists $hooksPath

$requiredHooks = @(
  @{ name = "SessionStart"; script = "helloagents-sessionstart.ps1" },
  @{ name = "UserPromptSubmit"; script = "helloagents-userpromptsubmit.ps1" },
  @{ name = "Stop"; script = "helloagents-stop.ps1" },
  @{ name = "PreCompact"; script = "helloagents-compact.ps1" },
  @{ name = "PostCompact"; script = "helloagents-compact.ps1" }
)

if ($hooksExists) {
  $hooksText = Read-Utf8Text $hooksPath
  $hooksJson = $null
  try {
    $hooksJson = $hooksText | ConvertFrom-Json -Depth 64
    Add-Check $checks "hooks_json_valid" $true "valid JSON"
  } catch {
    Add-Check $checks "hooks_json_valid" $false $_.Exception.Message
  }

  if ($null -ne $hooksJson) {
    foreach ($hook in $requiredHooks) {
      $hookName = [string]$hook.name
      $scriptName = [string]$hook.script
      $hookValue = $null
      try {
        $hookValue = $hooksJson.hooks.$hookName
      } catch {
        $hookValue = $null
      }

      $hookPresent = $null -ne $hookValue
      Add-Check $checks ("hook_{0}_present" -f $hookName) $hookPresent ("expect hook: {0}" -f $hookName)

      $hookSerialized = ""
      if ($hookPresent) {
        $hookSerialized = ($hookValue | ConvertTo-Json -Depth 64 -Compress)
      }
      Add-Check $checks ("hook_{0}_script" -f $hookName) (Test-HookCommandTargetsScript $hookSerialized $scriptName) ("expect script: {0}" -f $scriptName)
    }

    Add-Check $checks "skill_root_resolution_in_template" ($hooksText.Contains("HELLOAGENTS_SKILL_ROOT") -and $hooksText.Contains("CODEX_HOME") -and $hooksText.Contains("skills/helloagents")) "expect HELLOAGENTS_SKILL_ROOT -> CODEX_HOME/skills/helloagents fallback"
  }
} else {
  Add-Check $checks "hooks_json_valid" $false "missing .codex/hooks.json"
  foreach ($hook in $requiredHooks) {
    Add-Check $checks ("hook_{0}_present" -f $hook.name) $false ("missing hook: {0}" -f $hook.name)
    Add-Check $checks ("hook_{0}_script" -f $hook.name) $false ("missing script mapping: {0}" -f $hook.script)
  }
  Add-Check $checks "skill_root_resolution_in_template" $false "missing .codex/hooks.json"
}

$skillRootResolved = Resolve-SkillRoot $SkillRoot
Add-Check $checks "skill_root_exists" (Test-Path -LiteralPath $skillRootResolved -PathType Container) $skillRootResolved

foreach ($scriptName in @(
  "helloagents-sessionstart.ps1",
  "helloagents-userpromptsubmit.ps1",
  "helloagents-stop.ps1",
  "helloagents-compact.ps1"
)) {
  $scriptPath = Join-Path $skillRootResolved ("scripts/hooks/{0}" -f $scriptName)
  Add-Check $checks ("skill_script_{0}" -f ($scriptName -replace '\.ps1$', '')) (Test-Path -LiteralPath $scriptPath -PathType Leaf) $scriptPath
}

$failed = @($checks | Where-Object { -not $_.ok })
$result = [ordered]@{
  ok = ($failed.Count -eq 0)
  project_root = $projectRootResolved
  skill_root = $skillRootResolved
  checks = @($checks)
}

if ($Json) {
  $result | ConvertTo-Json -Depth 64
} else {
  if ($result.ok) {
    Write-Output "OK: helloagents hooks wiring health check passed"
  } else {
    Write-Output "FAIL: helloagents hooks wiring health check failed"
  }
  foreach ($check in $checks) {
    $status = if ($check.ok) { "OK" } else { "FAIL" }
    Write-Output ("[{0}] {1}: {2}" -f $status, $check.name, $check.message)
  }
}

if (-not $result.ok) {
  exit 1
}
