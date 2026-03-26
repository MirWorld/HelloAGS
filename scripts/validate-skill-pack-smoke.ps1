param(
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot() {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Write-Utf8Text([string]$path, [string]$text) {
  $parent = Split-Path -Parent $path
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

function Read-Utf8Text([string]$path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)
  }
  return $text
}

function Assert-True([bool]$condition, [string]$message) {
  if (-not $condition) {
    throw $message
  }
}

function Assert-Contains([string]$text, [string]$needle, [string]$message) {
  if ($null -eq $text -or -not $text.Contains($needle)) {
    throw $message
  }
}

function Assert-NotContains([string]$text, [string]$needle, [string]$message) {
  if ($null -ne $text -and $text.Contains($needle)) {
    throw $message
  }
}

function Invoke-HookJson([string]$scriptPath, [string]$inputFile, [string]$projectRoot, [switch]$DryRun) {
  $args = @(
    "-NoProfile",
    "-File", $scriptPath,
    "-InputFile", $inputFile,
    "-ProjectRoot", $projectRoot
  )
  if ($DryRun) {
    $args += "-DryRun"
  }

  $raw = & pwsh @args
  if ([string]::IsNullOrWhiteSpace(($raw -join ""))) {
    throw "Hook '$scriptPath' returned empty output."
  }
  return (($raw -join "`n") | ConvertFrom-Json -Depth 64)
}

function New-SmokePayload([string]$path, [string]$prompt, [string]$projectRoot) {
  $payload = [ordered]@{
    prompt = $prompt
    project_root = $projectRoot
  }
  Write-Utf8Text -path $path -text (($payload | ConvertTo-Json -Depth 16) + "`n")
}

function Initialize-Workspace([string]$repoRoot, [string]$projectRoot) {
  $manifestPath = Join-Path $repoRoot "templates/workspace-bootstrap-manifest.json"
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 32

  foreach ($relativeDir in @($manifest.directories)) {
    $full = Join-Path $projectRoot $relativeDir
    New-Item -ItemType Directory -Path $full -Force | Out-Null
  }

  foreach ($entry in @($manifest.files)) {
    $templatePath = Join-Path $repoRoot $entry.template
    $targetPath = Join-Path $projectRoot $entry.target
    Write-Utf8Text -path $targetPath -text (Read-Utf8Text -path $templatePath)
  }

  return $manifest
}

function New-SmokePackage([string]$projectRoot) {
  $packageRel = "HAGSWorks/plan/202603261200_smoke_hooks"
  $packageDir = Join-Path $projectRoot $packageRel
  New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

  $whyText = @"
# 对齐摘要: smoke

## 对齐摘要
- 目标：验证 skill 仓库关键脚本的最小行为闭环
"@

  $howText = @"
# 技术设计: smoke

## 功能删减审批（如触发）
- `feature_removal_approved: no`
- `approved_scope:`
- `approved_target:`
- `approved_reason:`
- `replacement_behavior:`
- `fallback_if_rejected:`

## 执行域声明（Allow/Deny）
- **Feature Removal（允许功能删减）:** [否 / 是（必须对应 `feature_removal_approved: yes`）]
"@

  $taskText = @"
# 任务清单: smoke

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 功能删减审批
- `feature_removal_approved: no`
- `approved_scope:`
- `approved_target:`
- `approved_reason:`
- `replacement_behavior:`

### 待用户输入（Pending）
- [SRC:TODO] 请选择继续路径

### 下一步唯一动作（可执行）
- 下一步唯一动作: `等待用户回复` 预期: 用户给出选择
"@

  Write-Utf8Text -path (Join-Path $packageDir "why.md") -text $whyText
  Write-Utf8Text -path (Join-Path $packageDir "how.md") -text $howText
  Write-Utf8Text -path (Join-Path $packageDir "task.md") -text $taskText

  $pointerPath = Join-Path $projectRoot "HAGSWorks/plan/_current.md"
  Write-Utf8Text -path $pointerPath -text ("# 当前方案包指针`n`ncurrent_package: {0}`n" -f $packageRel.Replace('\', '/'))

  return $packageRel.Replace('\', '/')
}

$repoRoot = Get-RepoRoot
$scratchRoot = Join-Path $repoRoot "_codex_temp/scratch/validate-skill-pack-smoke"
$projectRoot = Join-Path $scratchRoot "project"

if (Test-Path -LiteralPath $scratchRoot) {
  Remove-Item -LiteralPath $scratchRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

try {
  $manifest = Initialize-Workspace -repoRoot $repoRoot -projectRoot $projectRoot
  foreach ($relativeDir in @($manifest.directories)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot $relativeDir) -PathType Container) ("Missing generated directory: {0}" -f $relativeDir)
  }
  foreach ($entry in @($manifest.files)) {
    $targetPath = Join-Path $projectRoot $entry.target
    Assert-True (Test-Path -LiteralPath $targetPath -PathType Leaf) ("Missing generated file: {0}" -f $entry.target)
    Assert-True (-not [string]::IsNullOrWhiteSpace((Read-Utf8Text -path $targetPath))) ("Generated file is empty: {0}" -f $entry.target)
  }

  $packageRel = New-SmokePackage -projectRoot $projectRoot

  $sessionOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-sessionstart.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/sessionstart-hook-fixture.json") -projectRoot $projectRoot
  try { $sessionMessage = $sessionOut.systemMessage } catch { $sessionMessage = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($sessionMessage)) "SessionStart smoke should pass silently for a valid current package."

  $payloadNormal = Join-Path $scratchRoot "userpromptsubmit-normal.json"
  New-SmokePayload -path $payloadNormal -prompt "1" -projectRoot $projectRoot
  $userNormalOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadNormal -projectRoot $projectRoot
  $userNormalContext = $userNormalOut.hookSpecificOutput.additionalContext
  Assert-Contains $userNormalContext "pending:" "UserPromptSubmit should inject pending context when task.md has pending items."
  Assert-Contains $userNormalContext "[HelloAGENTS Guard] 检测到待用户输入（Pending）" "UserPromptSubmit should mark pending waiting state."
  Assert-NotContains $userNormalContext "feature_removal_approved:" "Ordinary pending prompts should not pay feature-removal guard context tax."

  $payloadCommand = Join-Path $scratchRoot "userpromptsubmit-command.json"
  New-SmokePayload -path $payloadCommand -prompt "~plan" -projectRoot $projectRoot
  $userCommandOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadCommand -projectRoot $projectRoot
  Assert-True ($userCommandOut.decision -eq "block") "Pending command input should be blocked."

  $payloadFeature = Join-Path $scratchRoot "userpromptsubmit-feature-removal.json"
  New-SmokePayload -path $payloadFeature -prompt "请删除旧入口并简化实现" -projectRoot $projectRoot
  $userFeatureOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadFeature -projectRoot $projectRoot
  $userFeatureContext = $userFeatureOut.hookSpecificOutput.additionalContext
  Assert-Contains $userFeatureContext "feature_removal_approved: no" "Feature-removal risk prompt should inject guard context."

  $stopFeatureOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-stop.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/stop-hook-feature-removal-fixture.json") -projectRoot $projectRoot -DryRun
  $stopFeatureContext = $stopFeatureOut.hookSpecificOutput.additionalContext
  Assert-Contains $stopFeatureOut.systemMessage "功能删减确认等待态" "Stop hook should surface feature-removal waiting state."
  Assert-Contains $stopFeatureContext "awaiting_topic: feature_removal_guard" "Stop hook should emit awaiting_topic context for feature-removal wait."

  $stopEventOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-stop.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/stop-hook-fixture.json") -projectRoot $projectRoot -DryRun
  Assert-Contains $stopEventOut.systemMessage "OK: stop hook forwarded 2 event(s)." "Stop hook should forward runtime/model events in dry-run mode."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "DRYRUN: would append 1 event(s)" "Stop hook dry-run should expose append preview from capture-runtime-events."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "model_event: model_rerouted" "Stop hook dry-run should include model_rerouted preview."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "model_event: response_incomplete" "Stop hook dry-run should include response_incomplete preview."

  Write-Output "OK: skill pack smoke validation passed"
} finally {
  if (-not $KeepArtifacts -and (Test-Path -LiteralPath $scratchRoot)) {
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force
  }
}
