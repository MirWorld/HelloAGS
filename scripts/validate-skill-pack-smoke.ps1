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

function New-SmokePayload([string]$path, [string]$prompt, [string]$projectRoot, [string]$turnId = "") {
  $payload = [ordered]@{
    prompt = $prompt
    project_root = $projectRoot
  }
  if (-not [string]::IsNullOrWhiteSpace($turnId)) {
    $payload.turn_id = $turnId
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
- `feature_removal_risk: clear`
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

- [ ] 1.0 验证 hooks 守卫

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 功能删减审批
- `feature_removal_risk: clear`
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

function Set-SmokeTaskText([string]$projectRoot, [string]$packageRel, [string]$taskText) {
  $taskPath = Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\task.md")
  Write-Utf8Text -path $taskPath -text $taskText
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
  New-SmokePayload -path $payloadNormal -prompt "1" -projectRoot $projectRoot -turnId "turn_demo_prompt_001"
  $userNormalOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadNormal -projectRoot $projectRoot
  $userNormalContext = $userNormalOut.hookSpecificOutput.additionalContext
  Assert-Contains $userNormalContext "pending:" "UserPromptSubmit should inject pending context when task.md has pending items."
  Assert-Contains $userNormalContext "[HelloAGENTS Guard] 检测到待用户输入（Pending）" "UserPromptSubmit should mark pending waiting state."
  Assert-Contains $userNormalContext "current_turn_id: turn_demo_prompt_001" "UserPromptSubmit should propagate turn_id into minimal context."
  Assert-NotContains $userNormalContext "feature_removal_approved:" "Ordinary pending prompts should not pay feature-removal guard context tax."

  $payloadCommand = Join-Path $scratchRoot "userpromptsubmit-command.json"
  New-SmokePayload -path $payloadCommand -prompt "~plan" -projectRoot $projectRoot -turnId "turn_demo_prompt_002"
  $userCommandOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadCommand -projectRoot $projectRoot
  Assert-True ($userCommandOut.decision -eq "block") "Pending command input should be blocked."

  $payloadFeature = Join-Path $scratchRoot "userpromptsubmit-feature-removal.json"
  New-SmokePayload -path $payloadFeature -prompt "请删除旧入口并简化实现" -projectRoot $projectRoot -turnId "turn_demo_prompt_003"
  $userFeatureOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadFeature -projectRoot $projectRoot
  $userFeatureContext = $userFeatureOut.hookSpecificOutput.additionalContext
  Assert-True ($userFeatureOut.decision -eq "block") "Feature-removal risk prompt should be blocked before execution."
  Assert-Contains $userFeatureOut.systemMessage "功能删减高风险" "Feature-removal risk block should explain why it was stopped."
  Assert-Contains $userFeatureContext "feature_removal_approved: no" "Feature-removal risk prompt should carry guard context."

  $payloadCleanup = Join-Path $scratchRoot "userpromptsubmit-internal-cleanup.json"
  New-SmokePayload -path $payloadCleanup -prompt "删除未使用 helper 并整理注释" -projectRoot $projectRoot -turnId "turn_demo_prompt_003b"
  $userCleanupOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadCleanup -projectRoot $projectRoot
  try { $cleanupDecision = $userCleanupOut.decision } catch { $cleanupDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($cleanupDecision)) "Internal cleanup prompt should not be blocked by feature-removal guard fallback."

  $responseIncompleteTask = @"
# 任务清单: smoke

- [ ] 1.0 先恢复再继续

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 功能删减审批
- `feature_removal_risk: clear`
- `feature_removal_approved: no`

### 运行时/模型事件（可选，结构化）
- [SRC:TOOL] model_event: response_incomplete
- [SRC:TOOL] turn_id: turn_demo_incomplete_001

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `等待补恢复检查点` 预期: 先补 repo_state + 下一步唯一动作
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $responseIncompleteTask

  $payloadIncomplete = Join-Path $scratchRoot "userpromptsubmit-incomplete.json"
  New-SmokePayload -path $payloadIncomplete -prompt "继续" -projectRoot $projectRoot -turnId "turn_demo_prompt_004"
  $userIncompleteOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadIncomplete -projectRoot $projectRoot
  Assert-True ($userIncompleteOut.decision -eq "block") "Unresolved response_incomplete should block execution-like prompts."
  Assert-Contains $userIncompleteOut.systemMessage "response_incomplete" "UserPromptSubmit should explain unresolved response_incomplete."

  $completedTask = @"
# 任务清单: smoke

- [√] 1.0 hooks 守卫已验证

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 功能删减审批
- `feature_removal_risk: clear`
- `feature_removal_approved: no`

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `等待新需求` 预期: 用户提出新任务或新建方案包
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $completedTask

  $sessionCompletedOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-sessionstart.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/sessionstart-hook-fixture.json") -projectRoot $projectRoot
  Assert-Contains $sessionCompletedOut.systemMessage "already completed" "SessionStart should warn when current_package is already completed."

  $payloadCompleted = Join-Path $scratchRoot "userpromptsubmit-completed.json"
  New-SmokePayload -path $payloadCompleted -prompt "~exec" -projectRoot $projectRoot -turnId "turn_demo_prompt_005"
  $userCompletedOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadCompleted -projectRoot $projectRoot
  Assert-True ($userCompletedOut.decision -eq "block") "Completed package should block resume/execute-like prompts."
  Assert-Contains $userCompletedOut.systemMessage "已完成且无 Pending" "Completed-package block should explain why execution was stopped."

  $stopFeatureOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-stop.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/stop-hook-feature-removal-fixture.json") -projectRoot $projectRoot -DryRun
  $stopFeatureContext = $stopFeatureOut.hookSpecificOutput.additionalContext
  Assert-Contains $stopFeatureOut.systemMessage "功能删减确认等待态" "Stop hook should surface feature-removal waiting state."
  Assert-Contains $stopFeatureContext "awaiting_topic: feature_removal_guard" "Stop hook should emit awaiting_topic context for feature-removal wait."
  Assert-Contains $stopFeatureContext "current_turn_id: turn_demo_feature_wait_001" "Stop hook should include current turn id in feature-removal wait context."

  $stopEventOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-stop.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/stop-hook-fixture.json") -projectRoot $projectRoot -DryRun
  Assert-Contains $stopEventOut.systemMessage "OK: stop hook forwarded 2 event(s)." "Stop hook should forward runtime/model events in dry-run mode."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "DRYRUN: would append 1 event(s)" "Stop hook dry-run should expose append preview from capture-runtime-events."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "model_event: model_rerouted" "Stop hook dry-run should include model_rerouted preview."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "model_event: response_incomplete" "Stop hook dry-run should include response_incomplete preview."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "turn_id=turn_demo_stop_001" "Stop hook dry-run should pass turn_id through to capture-runtime-events."

  Write-Output "OK: skill pack smoke validation passed"
} finally {
  if (-not $KeepArtifacts -and (Test-Path -LiteralPath $scratchRoot)) {
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force
  }
}
