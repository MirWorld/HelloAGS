param(
  [string]$ProjectRoot = "",
  [string]$SkillRoot = "",
  [switch]$DryRun,
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
  return ($configText -match '(?im)^\s*hooks\s*=\s*true\s*(?:#.*)?$')
}

function Test-HookCommandTargetsScript([string]$command, [string]$scriptName) {
  if ([string]::IsNullOrWhiteSpace($command)) {
    return $false
  }
  return ($command -match [regex]::Escape($scriptName))
}

function Invoke-HookDryRun(
  [string]$hookName,
  [string]$scriptPath,
  [string]$fixturePath,
  [string]$projectRoot,
  [bool]$passDryRun
) {
  $result = [ordered]@{
    exit_code = $null
    raw = ""
    json_ok = $false
    parsed = $null
  }

  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    $result.exit_code = 127
    $result.raw = "script not found: $scriptPath"
    return $result
  }
  if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
    $result.exit_code = 126
    $result.raw = "fixture not found: $fixturePath"
    return $result
  }

  $args = @(
    "-NoProfile",
    "-File", $scriptPath,
    "-InputFile", $fixturePath,
    "-ProjectRoot", $projectRoot
  )
  if ($passDryRun) {
    $args += "-DryRun"
  }

  $rawLines = & pwsh @args 2>&1
  $result.exit_code = $LASTEXITCODE
  $result.raw = ($rawLines -join "`n").Trim()
  if ($result.exit_code -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.raw)) {
    try {
      $result.parsed = ($result.raw | ConvertFrom-Json -Depth 64)
      $result.json_ok = $true
    } catch {
      $result.json_ok = $false
    }
  }

  return $result
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
  Add-Check $checks "hooks_enabled" (Test-CodexHooksEnabled $configText) "expect: [features] hooks = true"
} else {
  Add-Check $checks "hooks_enabled" $false "missing .codex/config.toml"
}

$hooksExists = Test-Path -LiteralPath $hooksPath -PathType Leaf
Add-Check $checks "hooks_json_exists" $hooksExists $hooksPath

$requiredHooks = @(
  @{ name = "SessionStart"; script = "helloagents-sessionstart.ps1" },
  @{ name = "UserPromptSubmit"; script = "helloagents-userpromptsubmit.ps1" },
  @{ name = "PreToolUse"; script = "helloagents-pretooluse.ps1" },
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
  "helloagents-pretooluse.ps1",
  "helloagents-stop.ps1",
  "helloagents-compact.ps1"
)) {
  $scriptPath = Join-Path $skillRootResolved ("scripts/hooks/{0}" -f $scriptName)
  Add-Check $checks ("skill_script_{0}" -f ($scriptName -replace '\.ps1$', '')) (Test-Path -LiteralPath $scriptPath -PathType Leaf) $scriptPath
}

if ($DryRun) {
  $dryRunCases = @(
    @{
      name = "SessionStart"
      script = "helloagents-sessionstart.ps1"
      fixture = "sessionstart-hook-fixture.json"
      passDryRun = $false
      requireNonSkip = $false
    },
    @{
      name = "UserPromptSubmit"
      script = "helloagents-userpromptsubmit.ps1"
      fixture = "userpromptsubmit-hook-fixture.json"
      passDryRun = $false
      requireNonSkip = $false
    },
    @{
      name = "PreToolUse"
      script = "helloagents-pretooluse.ps1"
      fixture = "pretooluse-hook-fixture.json"
      passDryRun = $false
      requireNonSkip = $false
    },
    @{
      name = "Stop"
      script = "helloagents-stop.ps1"
      fixture = "stop-hook-fixture.json"
      passDryRun = $true
      requireNonSkip = $true
    },
    @{
      name = "PreCompact"
      script = "helloagents-compact.ps1"
      fixture = "precompact-hook-fixture.json"
      passDryRun = $true
      requireNonSkip = $true
    },
    @{
      name = "PostCompact"
      script = "helloagents-compact.ps1"
      fixture = "postcompact-hook-fixture.json"
      passDryRun = $true
      requireNonSkip = $true
    }
  )

  foreach ($case in $dryRunCases) {
    $scriptPath = Join-Path $skillRootResolved ("scripts/hooks/{0}" -f $case.script)
    $fixturePath = Join-Path $skillRootResolved ("templates/hooks/{0}" -f $case.fixture)
    Add-Check $checks ("dryrun_{0}_fixture_exists" -f $case.name) (Test-Path -LiteralPath $fixturePath -PathType Leaf) $fixturePath

    $dryRunResult = Invoke-HookDryRun `
      -hookName $case.name `
      -scriptPath $scriptPath `
      -fixturePath $fixturePath `
      -projectRoot $projectRootResolved `
      -passDryRun ([bool]$case.passDryRun)

    Add-Check $checks ("dryrun_{0}_exit_zero" -f $case.name) ($dryRunResult.exit_code -eq 0) ("exit_code={0}; output={1}" -f $dryRunResult.exit_code, $dryRunResult.raw)
    Add-Check $checks ("dryrun_{0}_json" -f $case.name) ([bool]$dryRunResult.json_ok) ("output should be valid hook JSON; output={0}" -f $dryRunResult.raw)
    if ([bool]$case.requireNonSkip) {
      Add-Check $checks ("dryrun_{0}_effective" -f $case.name) (-not ($dryRunResult.raw -match '(?im)\bSKIP\s*:')) ("expected non-SKIP dry-run with active HAGSWorks plan package; output={0}" -f $dryRunResult.raw)
    }
  }
}

$failed = @($checks | Where-Object { -not $_.ok })
$result = [ordered]@{
  ok = ($failed.Count -eq 0)
  project_root = $projectRootResolved
  skill_root = $skillRootResolved
  dry_run = [bool]$DryRun
  checks = @($checks)
}

if ($Json) {
  $result | ConvertTo-Json -Depth 64
} else {
  if ($result.ok) {
    Write-Output "OK: helloagents hooks wiring health check passed"
  } elseif ($DryRun) {
    Write-Output "FAIL: helloagents hooks wiring health check failed (dry-run)"
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
