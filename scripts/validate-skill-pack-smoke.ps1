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

  $raw = & pwsh @args 2>$null
  if ([string]::IsNullOrWhiteSpace(($raw -join ""))) {
    throw "Hook '$scriptPath' returned empty output."
  }
  return (($raw -join "`n") | ConvertFrom-Json -Depth 64)
}

function Invoke-HooksHealthJson([string]$repoRoot, [string]$projectRoot, [switch]$DryRun) {
  $scriptPath = Join-Path $repoRoot "scripts/check-target-hooks.ps1"
  $args = @(
    "-NoProfile",
    "-File", $scriptPath,
    "-ProjectRoot", $projectRoot,
    "-SkillRoot", $repoRoot,
    "-Json"
  )
  if ($DryRun) {
    $args += "-DryRun"
  }
  $raw = & pwsh @args
  if ([string]::IsNullOrWhiteSpace(($raw -join ""))) {
    throw "Hooks health check returned empty output."
  }
  return (($raw -join "`n") | ConvertFrom-Json -Depth 64)
}

function Invoke-PlanValidatorJson([string]$projectRoot, [string]$mode = "plan", [string]$package = "") {
  $scriptPath = Join-Path $projectRoot "HAGSWorks/scripts/validate-plan-package.ps1"
  $args = @(
    "-NoProfile",
    "-File", $scriptPath,
    "-Mode", $mode,
    "-Json"
  )
  if (-not [string]::IsNullOrWhiteSpace($package)) {
    $args += @("-Package", $package)
  }
  $raw = & pwsh @args
  if ([string]::IsNullOrWhiteSpace(($raw -join ""))) {
    throw "Plan validator returned empty output."
  }
  return (($raw -join "`n") | ConvertFrom-Json -Depth 64)
}

function Invoke-ArchivePlanPackageJson([string]$projectRoot, [string]$package) {
  $scriptPath = Join-Path $projectRoot "HAGSWorks/scripts/archive-plan-package.ps1"
  $args = @(
    "-NoProfile",
    "-File", $scriptPath,
    "-ProjectRoot", $projectRoot,
    "-Package", $package,
    "-Json"
  )
  $raw = & pwsh @args
  $exitCode = $LASTEXITCODE
  if ([string]::IsNullOrWhiteSpace(($raw -join ""))) {
    throw "Archive script returned empty output."
  }
  $result = (($raw -join "`n") | ConvertFrom-Json -Depth 64)
  $result | Add-Member -NotePropertyName exit_code -NotePropertyValue $exitCode -Force
  return $result
}

function Invoke-AbandonPlanPackageJson([string]$projectRoot, [string]$package, [switch]$ConfirmCurrent) {
  $scriptPath = Join-Path $projectRoot "HAGSWorks/scripts/abandon-plan-package.ps1"
  $args = @(
    "-NoProfile",
    "-File", $scriptPath,
    "-ProjectRoot", $projectRoot,
    "-Package", $package,
    "-ConfirmAbandon",
    "-Json"
  )
  if ($ConfirmCurrent) {
    $args += "-ConfirmCurrent"
  }

  $raw = & pwsh @args
  $exitCode = $LASTEXITCODE
  if ([string]::IsNullOrWhiteSpace(($raw -join ""))) {
    throw "Abandon cleanup script returned empty output."
  }
  $result = (($raw -join "`n") | ConvertFrom-Json -Depth 64)
  $result | Add-Member -NotePropertyName exit_code -NotePropertyValue $exitCode -Force
  return $result
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

## 技术方案
- **verify_min:** `pwsh -NoProfile -Command "Write-Output smoke"`
- **carry_forward_verify:** `无`

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

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: start

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

function New-ArchiveReadyPackage([string]$projectRoot, [string]$packageName) {
  $packageRel = "HAGSWorks/plan/$packageName"
  $packageDir = Join-Path $projectRoot $packageRel
  New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

  $whyText = @"
# 对齐摘要: archive smoke

## 对齐摘要
- 目标：验证归档脚本的 validate → move → index → clear-current 闭环
"@

  $howText = @"
# 技术设计: archive smoke

## 技术方案
- **verify_min:** `pwsh -NoProfile -Command "Write-Output archive-smoke"`
- **carry_forward_verify:** `无`

## 执行域声明（Allow/Deny）
- Allow: [`HAGSWorks/plan/$packageName`]
"@

  $taskText = @"
# 任务清单: archive smoke

- [√] 1.0 验证归档脚本闭环

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] archive smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: final

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `执行 archive-plan-package.ps1` 预期: 迁移到 history 并清空 current pointer

## Review 记录
- Review: 归档脚本 smoke 方案包已满足终态任务、空 Pending、final progress 与 Review 证据
- 复测: `pwsh -NoProfile -Command "Write-Output archive-smoke"` 结果: 通过
"@

  Write-Utf8Text -path (Join-Path $packageDir "why.md") -text $whyText
  Write-Utf8Text -path (Join-Path $packageDir "how.md") -text $howText
  Write-Utf8Text -path (Join-Path $packageDir "task.md") -text $taskText

  return $packageRel.Replace('\', '/')
}

function New-UnexecutedPackage([string]$projectRoot, [string]$packageName) {
  $packageRel = "HAGSWorks/plan/$packageName"
  $packageDir = Join-Path $projectRoot $packageRel
  New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

  $whyText = @"
# 对齐摘要: abandoned smoke

## 对齐摘要
- 目标：验证未执行旧方案放弃清理脚本
"@

  $howText = @"
# 技术设计: abandoned smoke

## 技术方案
- **verify_min:** `未执行；用户放弃执行`
- **carry_forward_verify:** `无`

## 执行域声明（Allow/Deny）
- Allow: [`HAGSWorks/plan/$packageName`]
"@

  $taskText = @"
# 任务清单: abandoned smoke

- [ ] 1.0 这个方案尚未执行

## 上下文快照

### 已确认事实（可验证）
- [SRC:USER] 用户明确放弃执行该旧方案

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: start

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `执行 abandon-plan-package.ps1` 预期: 按未执行清理迁移
"@

  Write-Utf8Text -path (Join-Path $packageDir "why.md") -text $whyText
  Write-Utf8Text -path (Join-Path $packageDir "how.md") -text $howText
  Write-Utf8Text -path (Join-Path $packageDir "task.md") -text $taskText

  return $packageRel.Replace('\', '/')
}

function Set-CurrentPackage([string]$projectRoot, [string]$packageRel) {
  $pointerPath = Join-Path $projectRoot "HAGSWorks/plan/_current.md"
  Write-Utf8Text -path $pointerPath -text ("# 当前方案包指针`n`ncurrent_package: {0}`n" -f $packageRel.Replace('\', '/'))
}

function Set-FileReadOnly([string]$path, [bool]$readOnly) {
  if (-not (Test-Path -LiteralPath $path)) {
    return
  }

  $attributes = [System.IO.File]::GetAttributes($path)
  if ($readOnly) {
    $attributes = $attributes -bor [System.IO.FileAttributes]::ReadOnly
  } else {
    $attributes = $attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
  }
  [System.IO.File]::SetAttributes($path, $attributes)
}

function Set-SmokeTaskText([string]$projectRoot, [string]$packageRel, [string]$taskText) {
  $taskPath = Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\task.md")
  Write-Utf8Text -path $taskPath -text $taskText
}

function New-ThresholdPayload(
  [string]$path,
  [string]$projectRoot,
  [string]$source,
  [int]$usedTokens,
  [int]$threshold,
  [int]$remainingToCompact,
  [string]$severity = "soft",
  [int]$compactPreTokens = 0
) {
  $payload = [ordered]@{
    source = $source
    project_root = $projectRoot
    used_tokens = $usedTokens
    auto_compact_threshold = $threshold
    remaining_to_compact = $remainingToCompact
    threshold_severity = $severity
    model = "gpt-5.2"
    percentage = "96"
    timestamp = "2026-04-02T12:00:00Z"
  }
  if ($compactPreTokens -gt 0) {
    $payload.compact_pre_tokens = $compactPreTokens
  }
  Write-Utf8Text -path $path -text (($payload | ConvertTo-Json -Depth 16) + "`n")
}

function New-PreToolUsePayload(
  [string]$path,
  [string]$projectRoot,
  [string]$toolName,
  [string]$toolUseId,
  [string]$command,
  [string]$turnId = "turn_demo_pretooluse_001"
) {
  $payload = [ordered]@{
    session_id = "session_demo_pretooluse_001"
    turn_id = $turnId
    cwd = $projectRoot
    transcript_path = (Join-Path $projectRoot ".codex/transcript-demo.jsonl")
    hook_event_name = "PreToolUse"
    model = "gpt-5.2"
    permission_mode = "workspace-write"
    tool_name = $toolName
    tool_use_id = $toolUseId
    tool_input = [ordered]@{
      command = $command
    }
  }
  Write-Utf8Text -path $path -text (($payload | ConvertTo-Json -Depth 16) + "`n")
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

  $codexDir = Join-Path $projectRoot ".codex"
  New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
  Write-Utf8Text -path (Join-Path $codexDir "config.toml") -text (Read-Utf8Text -path (Join-Path $repoRoot "templates/hooks/config.toml.snippet"))
  Write-Utf8Text -path (Join-Path $codexDir "hooks.json") -text (Read-Utf8Text -path (Join-Path $repoRoot "templates/hooks/hooks.json"))
  $hooksHealth = Invoke-HooksHealthJson -repoRoot $repoRoot -projectRoot $projectRoot
  Assert-True ($hooksHealth.ok -eq $true) "Hooks health check should pass for copied config.toml + hooks.json templates."
  $healthNames = @($hooksHealth.checks | ForEach-Object { $_.name })
  Assert-True ($healthNames -contains "codex_hooks_enabled") "Hooks health check should verify codex_hooks_enabled."
  Assert-True ($healthNames -contains "hook_PreToolUse_present") "Hooks health check should verify PreToolUse wiring."
  Assert-True ($healthNames -contains "hook_PreCompact_present") "Hooks health check should verify PreCompact wiring."
  Assert-True ($healthNames -contains "hook_PostCompact_present") "Hooks health check should verify PostCompact wiring."
  Assert-True ($healthNames -contains "skill_script_helloagents-pretooluse") "Hooks health check should verify PreToolUse script availability."
  Assert-True ($healthNames -contains "skill_script_helloagents-compact") "Hooks health check should verify compact script availability."

  $packageRel = New-SmokePackage -projectRoot $projectRoot
  $pointerPath = Join-Path $projectRoot "HAGSWorks/plan/_current.md"
  $hooksHealthDryRun = Invoke-HooksHealthJson -repoRoot $repoRoot -projectRoot $projectRoot -DryRun
  Assert-True ($hooksHealthDryRun.ok -eq $true) "Hooks health dry-run should pass with an active HAGSWorks plan package."
  Assert-True ($hooksHealthDryRun.dry_run -eq $true) "Hooks health dry-run should mark dry_run=true."
  $dryRunHealthNames = @($hooksHealthDryRun.checks | ForEach-Object { $_.name })
  Assert-True ($dryRunHealthNames -contains "dryrun_SessionStart_json") "Hooks health dry-run should execute SessionStart fixture and parse JSON."
  Assert-True ($dryRunHealthNames -contains "dryrun_UserPromptSubmit_json") "Hooks health dry-run should execute UserPromptSubmit fixture and parse JSON."
  Assert-True ($dryRunHealthNames -contains "dryrun_PreToolUse_json") "Hooks health dry-run should execute PreToolUse fixture and parse JSON."
  Assert-True ($dryRunHealthNames -contains "dryrun_Stop_effective") "Hooks health dry-run should execute Stop fixture without SKIP."
  Assert-True ($dryRunHealthNames -contains "dryrun_PreCompact_effective") "Hooks health dry-run should execute PreCompact fixture without SKIP."
  Assert-True ($dryRunHealthNames -contains "dryrun_PostCompact_effective") "Hooks health dry-run should execute PostCompact fixture without SKIP."

  $outsidePackageRel = "HAGSWorks/plan_evil/202603261201_outside_plan"
  $outsidePackageDir = Join-Path $projectRoot $outsidePackageRel
  New-Item -ItemType Directory -Path $outsidePackageDir -Force | Out-Null
  Write-Utf8Text -path (Join-Path $outsidePackageDir "why.md") -text "# outside plan`n`n## 对齐摘要`n- 目标：不应被 hooks 当作 active plan`n"
  Write-Utf8Text -path (Join-Path $outsidePackageDir "how.md") -text "# outside plan`n`n## 执行域声明（Allow/Deny）`n- Allow: []`n`nverify_min: `pwsh -NoProfile -Command ""Write-Output smoke""``ncarry_forward_verify: 无`n"
  Write-Utf8Text -path (Join-Path $outsidePackageDir "task.md") -text "# outside plan`n`n- [ ] 1.0 不应执行`n`n## 上下文快照`n`n### Repo 状态（复现/防漂移，执行域必填）`n- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none`n`n### 决策（做了什么选择 + 为什么）`n- [SRC:CODE|TOOL] progress_phase: start`n`n### 待用户输入（Pending）`n`n### 下一步唯一动作（可执行）`n- 下一步唯一动作: `不应执行` 预期: hooks 应拒绝 plan_evil 前缀路径`n"
  Write-Utf8Text -path $pointerPath -text ("# 当前方案包指针`n`ncurrent_package: {0}`n" -f $outsidePackageRel)

  $sessionOutsideOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-sessionstart.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/sessionstart-hook-fixture.json") -projectRoot $projectRoot
  Assert-Contains $sessionOutsideOut.systemMessage "outside plan root" "SessionStart should reject current_package paths that only share the HAGSWorks/plan prefix."
  Assert-Contains $sessionOutsideOut.hookSpecificOutput.additionalContext "signal: current_package_invalid" "SessionStart outside-plan rejection should expose current_package_invalid."

  $payloadOutside = Join-Path $scratchRoot "userpromptsubmit-outside-plan.json"
  New-SmokePayload -path $payloadOutside -prompt "~exec" -projectRoot $projectRoot -turnId "turn_demo_prompt_outside"
  $userOutsideOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadOutside -projectRoot $projectRoot
  Assert-True ($userOutsideOut.decision -eq "block") "UserPromptSubmit should block current_package paths outside HAGSWorks/plan."

  $thresholdOutsidePayload = Join-Path $scratchRoot "context-threshold-outside-plan.json"
  New-ThresholdPayload -path $thresholdOutsidePayload -projectRoot $projectRoot -source "pre_submit" -usedTokens 188000 -threshold 200000 -remainingToCompact 12000
  $thresholdOutsideOut = & pwsh -NoProfile -File (Join-Path $repoRoot "scripts/hooks/helloagents-context-threshold.ps1") -InputFile $thresholdOutsidePayload -ProjectRoot $projectRoot
  Assert-Contains ($thresholdOutsideOut -join "`n") "SKIP: no active plan package." "Context-threshold hook should skip current_package paths outside HAGSWorks/plan."

  $outsideTaskFileRel = Join-Path ($outsidePackageRel.Replace('/', '\')) "task.md"
  $captureOutsideOut = & pwsh -NoProfile -File (Join-Path $projectRoot "HAGSWorks/scripts/capture-runtime-events.ps1") -Mode append -Kind model_rerouted -TaskFile $outsideTaskFileRel
  Assert-Contains ($captureOutsideOut -join "`n") "SKIP: task.md not found" "Runtime event capture should reject explicit TaskFile paths outside the active plan package."

  $validatorOutside = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "plan" -package $outsidePackageRel
  Assert-True (-not $validatorOutside.ok) "Plan validator should reject explicit -Package paths outside HAGSWorks/plan."
  Assert-Contains (($validatorOutside.errors -join "`n")) "outside plan root" "Plan validator should explain outside-plan package rejection."

  $compactOutsideOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-compact.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/precompact-hook-fixture.json") -projectRoot $projectRoot -DryRun
  Assert-Contains $compactOutsideOut.systemMessage "SKIP: no active plan package." "Compact hook should skip current_package paths outside HAGSWorks/plan."

  Write-Utf8Text -path $pointerPath -text ("# 当前方案包指针`n`ncurrent_package: {0}`n" -f $packageRel.Replace('\', '/'))

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
  Assert-Contains $userFeatureContext "feature_removal_risk: suspected" "Feature-removal risk prompt should normalize heuristic risk into a structured suspected signal."
  Assert-Contains $userFeatureContext "feature_removal_approved: no" "Feature-removal risk prompt should carry guard context."
  Assert-Contains $userFeatureContext "signal: feature_removal_guard" "Feature-removal risk prompt should emit a stable guard signal."
  Assert-Contains $userFeatureContext "severity: Red" "Feature-removal risk prompt should mark the guard as Red."

  $payloadCleanup = Join-Path $scratchRoot "userpromptsubmit-internal-cleanup.json"
  New-SmokePayload -path $payloadCleanup -prompt "删除未使用 helper 并整理注释" -projectRoot $projectRoot -turnId "turn_demo_prompt_003b"
  $userCleanupOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadCleanup -projectRoot $projectRoot
  try { $cleanupDecision = $userCleanupOut.decision } catch { $cleanupDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($cleanupDecision)) "Internal cleanup prompt should not be blocked by feature-removal guard fallback."

  $thresholdPayload = Join-Path $scratchRoot "context-threshold.json"
  New-ThresholdPayload -path $thresholdPayload -projectRoot $projectRoot -source "pre_submit" -usedTokens 188000 -threshold 200000 -remainingToCompact 12000
  & pwsh -NoProfile -File (Join-Path $repoRoot "scripts/hooks/helloagents-context-threshold.ps1") -InputFile $thresholdPayload -ProjectRoot $projectRoot | Out-Null
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "_codex_temp/locks") -PathType Container) "Context-threshold hook should create/use the task.md lock directory."
  $thresholdTask = Read-Utf8Text -path (Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\task.md"))
  Assert-Contains $thresholdTask "threshold_event: near_autocompact" "Context-threshold hook should append threshold_event checkpoint."
  Assert-Contains $thresholdTask "threshold_source: pre_submit" "Context-threshold hook should record threshold source."
  Assert-Contains $thresholdTask "remaining_to_compact: 12000" "Context-threshold hook should record remaining_to_compact."

  $thresholdPayloadDup = Join-Path $scratchRoot "context-threshold-dup.json"
  New-ThresholdPayload -path $thresholdPayloadDup -projectRoot $projectRoot -source "pre_submit" -usedTokens 189000 -threshold 200000 -remainingToCompact 11000
  & pwsh -NoProfile -File (Join-Path $repoRoot "scripts/hooks/helloagents-context-threshold.ps1") -InputFile $thresholdPayloadDup -ProjectRoot $projectRoot | Out-Null
  $thresholdTaskDup = Read-Utf8Text -path (Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\task.md"))
  $thresholdCount = ([regex]::Matches($thresholdTaskDup, 'threshold_event: near_autocompact')).Count
  Assert-True ($thresholdCount -eq 1) "Context-threshold hook should skip near-duplicate checkpoints within the same source band."

  $preCompactOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-compact.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/precompact-hook-fixture.json") -projectRoot $projectRoot -DryRun
  Assert-True ($preCompactOut.continue -eq $true) "PreCompact dry-run should return a valid compact hook continue response."
  Assert-Contains $preCompactOut.systemMessage "hook_event_name: PreCompact" "PreCompact dry-run should preserve hook event name."
  Assert-Contains $preCompactOut.systemMessage "compact_event: pre_compact" "PreCompact dry-run should preview compact_event checkpoint."
  Assert-Contains $preCompactOut.systemMessage "turn_demo_precompact_001" "PreCompact dry-run should preview turn_id."
  Assert-Contains $preCompactOut.systemMessage "repo_state" "PreCompact dry-run should preview repo_state evidence."

  $preCompactWriteOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-compact.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/precompact-hook-fixture.json") -projectRoot $projectRoot
  Assert-True ($preCompactWriteOut.continue -eq $true) "PreCompact hook should not stop compaction in write mode."
  $compactTask = Read-Utf8Text -path (Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\task.md"))
  Assert-Contains $compactTask "compact_event: pre_compact" "PreCompact hook should append compact_event pre_compact."
  Assert-Contains $compactTask "compact_trigger: auto" "PreCompact hook should record compact trigger."
  Assert-Contains $compactTask "turn_id: turn_demo_precompact_001" "PreCompact hook should record turn_id."
  Assert-Contains $compactTask "repo_state:" "PreCompact hook should record repo_state recovery evidence."

  $postCompactWriteOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-compact.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/postcompact-hook-fixture.json") -projectRoot $projectRoot
  Assert-True ($postCompactWriteOut.continue -eq $true) "PostCompact hook should return a valid compact hook continue response."
  $compactTaskAfterPost = Read-Utf8Text -path (Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\task.md"))
  Assert-Contains $compactTaskAfterPost "compact_event: post_compact" "PostCompact hook should append compact_event post_compact."
  Assert-Contains $compactTaskAfterPost "resume_hydration_required: yes" "PostCompact hook should mark resume hydration as required."
  Assert-Contains $compactTaskAfterPost "reboot_check: required" "PostCompact hook should mark reboot check as required."
  Assert-Contains $compactTaskAfterPost "hydration_source: _current.md + task.md + repo_state" "PostCompact hook should record hydration source."

  $preToolScript = Join-Path $repoRoot "scripts/hooks/helloagents-pretooluse.ps1"
  $preToolBusinessReadPayload = Join-Path $scratchRoot "pretooluse-postcompact-business-read.json"
  New-PreToolUsePayload -path $preToolBusinessReadPayload -projectRoot $projectRoot -toolName "Bash" -toolUseId "tool_demo_pretooluse_business_read" -command "Get-Content src/app.ts"
  $preToolBusinessReadOut = Invoke-HookJson -scriptPath $preToolScript -inputFile $preToolBusinessReadPayload -projectRoot $projectRoot
  Assert-True ($preToolBusinessReadOut.decision -eq "block") "PreToolUse should block business file reads while post_compact hydration is unresolved."
  Assert-Contains $preToolBusinessReadOut.reason "compact_resume_required" "PreToolUse business read block should explain compact_resume_required."
  Assert-Contains $preToolBusinessReadOut.hookSpecificOutput.additionalContext "mode: hydration_only" "PreToolUse business read block should expose hydration_only context."

  $preToolBusinessWritePayload = Join-Path $scratchRoot "pretooluse-postcompact-business-write.json"
  New-PreToolUsePayload -path $preToolBusinessWritePayload -projectRoot $projectRoot -toolName "Bash" -toolUseId "tool_demo_pretooluse_business_write" -command "Set-Content src/app.ts 'changed'"
  $preToolBusinessWriteOut = Invoke-HookJson -scriptPath $preToolScript -inputFile $preToolBusinessWritePayload -projectRoot $projectRoot
  Assert-True ($preToolBusinessWriteOut.decision -eq "block") "PreToolUse should block code writes while post_compact hydration is unresolved."
  Assert-Contains $preToolBusinessWriteOut.hookSpecificOutput.additionalContext "forbidden: business_files; code_changes; verify_commands; temporary_replan" "PreToolUse code write block should expose forbidden actions."

  $preToolAllowedPointerPayload = Join-Path $scratchRoot "pretooluse-postcompact-current-pointer.json"
  New-PreToolUsePayload -path $preToolAllowedPointerPayload -projectRoot $projectRoot -toolName "Bash" -toolUseId "tool_demo_pretooluse_current_pointer" -command "Get-Content HAGSWorks/plan/_current.md"
  $preToolAllowedPointerOut = Invoke-HookJson -scriptPath $preToolScript -inputFile $preToolAllowedPointerPayload -projectRoot $projectRoot
  try { $preToolAllowedPointerDecision = $preToolAllowedPointerOut.decision } catch { $preToolAllowedPointerDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($preToolAllowedPointerDecision)) "PreToolUse should allow reading _current.md during hydration_only."
  Assert-Contains $preToolAllowedPointerOut.hookSpecificOutput.additionalContext "compact_resume_required" "Allowed PreToolUse hydration reads should still carry compact_resume_required context."

  $preToolAllowedGitPayload = Join-Path $scratchRoot "pretooluse-postcompact-git-status.json"
  New-PreToolUsePayload -path $preToolAllowedGitPayload -projectRoot $projectRoot -toolName "Bash" -toolUseId "tool_demo_pretooluse_git_status" -command "git status --short"
  $preToolAllowedGitOut = Invoke-HookJson -scriptPath $preToolScript -inputFile $preToolAllowedGitPayload -projectRoot $projectRoot
  try { $preToolAllowedGitDecision = $preToolAllowedGitOut.decision } catch { $preToolAllowedGitDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($preToolAllowedGitDecision)) "PreToolUse should allow git status during hydration_only."

  $preToolAllowedTaskWritePayload = Join-Path $scratchRoot "pretooluse-postcompact-task-write.json"
  New-PreToolUsePayload -path $preToolAllowedTaskWritePayload -projectRoot $projectRoot -toolName "Bash" -toolUseId "tool_demo_pretooluse_task_write" -command ("Set-Content {0}/task.md '- [SRC:TOOL] reboot_check: ok'" -f $packageRel)
  $preToolAllowedTaskWriteOut = Invoke-HookJson -scriptPath $preToolScript -inputFile $preToolAllowedTaskWritePayload -projectRoot $projectRoot
  try { $preToolAllowedTaskWriteDecision = $preToolAllowedTaskWriteOut.decision } catch { $preToolAllowedTaskWriteDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($preToolAllowedTaskWriteDecision)) "PreToolUse should allow writing the current task.md recovery checkpoint during hydration_only."

  $validatorPostCompactBlocked = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "exec" -package $packageRel
  Assert-True (-not $validatorPostCompactBlocked.ok) "Exec validation should fail after post_compact until Resume Hydration Gate writes reboot_check: ok."
  Assert-Contains (($validatorPostCompactBlocked.errors -join "`n")) "reboot_check: ok" "Exec validation should explain missing reboot_check: ok after post_compact."

  $sessionPostCompactOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-sessionstart.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/sessionstart-hook-fixture.json") -projectRoot $projectRoot
  Assert-Contains $sessionPostCompactOut.systemMessage "post_compact" "SessionStart should warn when current_package contains unresolved post_compact."
  Assert-Contains $sessionPostCompactOut.hookSpecificOutput.additionalContext "signal: compact_resume_required" "SessionStart post_compact warning should expose compact_resume_required."
  Assert-Contains $sessionPostCompactOut.hookSpecificOutput.additionalContext "mode: hydration_only" "SessionStart post_compact warning should expose hydration_only mode."
  Assert-Contains $sessionPostCompactOut.hookSpecificOutput.additionalContext "allowed_reads: HAGSWorks/plan/_current.md; current package why.md/how.md/task.md; git status/rev-parse/diff --stat" "SessionStart hydration_only should expose allowed reads."
  Assert-Contains $sessionPostCompactOut.hookSpecificOutput.additionalContext "forbidden: business_files; code_changes; verify_commands; temporary_replan" "SessionStart hydration_only should expose forbidden actions."

  $payloadPostCompact = Join-Path $scratchRoot "userpromptsubmit-postcompact.json"
  New-SmokePayload -path $payloadPostCompact -prompt "继续" -projectRoot $projectRoot -turnId "turn_demo_prompt_postcompact"
  $userPostCompactOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadPostCompact -projectRoot $projectRoot
  try { $postCompactResumeDecision = $userPostCompactOut.decision } catch { $postCompactResumeDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($postCompactResumeDecision)) "Unresolved post_compact should allow plain resume prompts to enter hydration_only instead of blocking the whole turn."
  Assert-Contains $userPostCompactOut.hookSpecificOutput.additionalContext "compact_resume_required" "UserPromptSubmit should emit compact_resume_required context."
  Assert-Contains $userPostCompactOut.hookSpecificOutput.additionalContext "mode: hydration_only" "Plain resume after post_compact should expose hydration_only mode."
  Assert-Contains $userPostCompactOut.hookSpecificOutput.additionalContext "forbidden: business_files; code_changes; verify_commands; temporary_replan" "hydration_only should prohibit implementation actions."

  $payloadPostCompactExec = Join-Path $scratchRoot "userpromptsubmit-postcompact-exec.json"
  New-SmokePayload -path $payloadPostCompactExec -prompt "~exec" -projectRoot $projectRoot -turnId "turn_demo_prompt_postcompact_exec"
  $userPostCompactExecOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadPostCompactExec -projectRoot $projectRoot
  Assert-True ($userPostCompactExecOut.decision -eq "block") "Unresolved post_compact should still block explicit execute commands."
  Assert-Contains $userPostCompactExecOut.hookSpecificOutput.additionalContext "mode: hydration_only" "Blocked post_compact execute commands should still explain hydration_only mode."

  $payloadPostCompactQuestion = Join-Path $scratchRoot "userpromptsubmit-postcompact-question.json"
  New-SmokePayload -path $payloadPostCompactQuestion -prompt "这个方案现在是什么状态？" -projectRoot $projectRoot -turnId "turn_demo_prompt_postcompact_question"
  $userPostCompactQuestionOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadPostCompactQuestion -projectRoot $projectRoot
  try { $postCompactQuestionDecision = $userPostCompactQuestionOut.decision } catch { $postCompactQuestionDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($postCompactQuestionDecision)) "Unresolved post_compact should not block non-execution questions."
  Assert-Contains $userPostCompactQuestionOut.hookSpecificOutput.additionalContext "compact_resume_required" "Non-execution post_compact prompts should still inject hydration context."

  $compactTaskAfterPostNoPending = [regex]::Replace($compactTaskAfterPost, '(?m)^\s*-\s*\[SRC:TODO\]\s*请选择继续路径\s*\r?\n', '')
  $deceptiveHydrationTask = $compactTaskAfterPostNoPending + @"

### 错误示例（不应被当成结构化恢复）
- [SRC:TOOL] 说明: 文本里出现 reboot_check: ok，但字段名不是本行结构键
- [SRC:CODE|TOOL] 说明: 文本里出现 contract_checkpoint: ok，但字段名不是本行结构键
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $deceptiveHydrationTask
  $validatorPostCompactDeceptive = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "exec" -package $packageRel
  Assert-True (-not $validatorPostCompactDeceptive.ok) "Exec validation should not accept natural-language mentions of reboot_check: ok / contract_checkpoint: ok as structured recovery fields."
  Assert-Contains (($validatorPostCompactDeceptive.errors -join "`n")) "reboot_check: ok" "Deceptive hydration text should still fail with missing structured reboot_check: ok."

  $hydratedTask = $compactTaskAfterPostNoPending + @"

### 压缩恢复 Hydration
- [SRC:TOOL] resume_hydration_required: yes
- [SRC:TOOL] reboot_check: ok
- [SRC:TOOL] hydrated_from_package: $packageRel
- [SRC:TOOL] hydration_source: _current.md + task.md + repo_state
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none
- [SRC:CODE|TOOL] contract_checkpoint: ok
- 下一步唯一动作: `继续执行 1.0 验证 hooks 守卫` 预期: Hydration 已通过后按当前包续作
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $hydratedTask
  $validatorPostCompactRecovered = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "exec" -package $packageRel
  Assert-True ($validatorPostCompactRecovered.ok) "Exec validation should pass after reboot_check: ok + contract_checkpoint: ok are recorded."
  $sessionPostCompactRecoveredOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-sessionstart.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/sessionstart-hook-fixture.json") -projectRoot $projectRoot
  try { $sessionPostCompactRecoveredMessage = $sessionPostCompactRecoveredOut.systemMessage } catch { $sessionPostCompactRecoveredMessage = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($sessionPostCompactRecoveredMessage)) "SessionStart should be silent after structured post_compact hydration is complete."

  $payloadPostCompactRecovered = Join-Path $scratchRoot "userpromptsubmit-postcompact-recovered.json"
  New-SmokePayload -path $payloadPostCompactRecovered -prompt "继续" -projectRoot $projectRoot -turnId "turn_demo_prompt_postcompact_recovered"
  $userPostCompactRecoveredOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadPostCompactRecovered -projectRoot $projectRoot
  try { $postCompactRecoveredDecision = $userPostCompactRecoveredOut.decision } catch { $postCompactRecoveredDecision = $null }
  try { $postCompactRecoveredContext = $userPostCompactRecoveredOut.hookSpecificOutput.additionalContext } catch { $postCompactRecoveredContext = "" }
  Assert-True ([string]::IsNullOrWhiteSpace($postCompactRecoveredDecision)) "UserPromptSubmit should not block plain resume after structured post_compact hydration is complete."
  Assert-True (($postCompactRecoveredContext -notmatch "compact_resume_required") -and ($postCompactRecoveredContext -notmatch "mode: hydration_only")) "UserPromptSubmit should not inject compact_resume_required after hydration is complete."

  $preToolRecoveredBusinessReadPayload = Join-Path $scratchRoot "pretooluse-recovered-business-read.json"
  New-PreToolUsePayload -path $preToolRecoveredBusinessReadPayload -projectRoot $projectRoot -toolName "Bash" -toolUseId "tool_demo_pretooluse_recovered_read" -command "Get-Content src/app.ts"
  $preToolRecoveredBusinessReadOut = Invoke-HookJson -scriptPath $preToolScript -inputFile $preToolRecoveredBusinessReadPayload -projectRoot $projectRoot
  try { $preToolRecoveredBusinessReadDecision = $preToolRecoveredBusinessReadOut.decision } catch { $preToolRecoveredBusinessReadDecision = $null }
  try { $preToolRecoveredBusinessReadContext = $preToolRecoveredBusinessReadOut.hookSpecificOutput.additionalContext } catch { $preToolRecoveredBusinessReadContext = "" }
  Assert-True ([string]::IsNullOrWhiteSpace($preToolRecoveredBusinessReadDecision)) "PreToolUse should not block ordinary business reads after structured post_compact hydration is complete."
  Assert-True (($preToolRecoveredBusinessReadContext -notmatch "compact_resume_required") -and ($preToolRecoveredBusinessReadContext -notmatch "mode: hydration_only")) "PreToolUse should not inject hydration_only after hydration is complete."

  $responseIncompleteTask = @"
# 任务清单: smoke

- [ ] 1.0 先恢复再继续

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: mid

### 功能删减审批
- `feature_removal_risk: clear`
- `feature_removal_approved: no`

### 运行时/模型事件（可选，结构化）
- [SRC:TOOL] model_event: response_incomplete
- [SRC:TOOL] turn_id: turn_demo_incomplete_001

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] contract_checkpoint: ok

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `等待补恢复检查点` 预期: 先补 repo_state + 下一步唯一动作 + contract_checkpoint
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $responseIncompleteTask

  $sessionIncompleteOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-sessionstart.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/sessionstart-hook-fixture.json") -projectRoot $projectRoot
  Assert-Contains $sessionIncompleteOut.systemMessage "response_incomplete" "SessionStart should warn when current_package contains unresolved response_incomplete."
  Assert-Contains $sessionIncompleteOut.hookSpecificOutput.additionalContext "signal: response_incomplete" "SessionStart response_incomplete warning should expose a stable signal."
  Assert-Contains $sessionIncompleteOut.hookSpecificOutput.additionalContext "severity: Red" "SessionStart response_incomplete warning should expose Red severity."
  Assert-Contains $sessionIncompleteOut.hookSpecificOutput.additionalContext "mode: recovery_only" "SessionStart response_incomplete warning should expose recovery_only mode."
  Assert-Contains $sessionIncompleteOut.hookSpecificOutput.additionalContext "allowed_reads: HAGSWorks/plan/_current.md; current package why.md/how.md/task.md; git status/rev-parse/diff --stat" "SessionStart recovery_only should expose allowed reads."
  Assert-Contains $sessionIncompleteOut.hookSpecificOutput.additionalContext "forbidden: business_files; code_changes; verify_commands; temporary_replan" "SessionStart recovery_only should expose forbidden actions."

  $payloadIncomplete = Join-Path $scratchRoot "userpromptsubmit-incomplete.json"
  New-SmokePayload -path $payloadIncomplete -prompt "继续" -projectRoot $projectRoot -turnId "turn_demo_prompt_004"
  $userIncompleteOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadIncomplete -projectRoot $projectRoot
  try { $incompleteResumeDecision = $userIncompleteOut.decision } catch { $incompleteResumeDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($incompleteResumeDecision)) "Unresolved response_incomplete should allow plain resume prompts to enter recovery_only instead of blocking the whole turn."
  Assert-Contains $userIncompleteOut.systemMessage "response_incomplete" "UserPromptSubmit should explain unresolved response_incomplete."
  Assert-Contains $userIncompleteOut.hookSpecificOutput.additionalContext "severity: Red" "response_incomplete recovery context should emit a Red severity signal."
  Assert-Contains $userIncompleteOut.hookSpecificOutput.additionalContext "mode: recovery_only" "Plain resume after response_incomplete should expose recovery_only mode."

  $payloadIncompleteExec = Join-Path $scratchRoot "userpromptsubmit-incomplete-exec.json"
  New-SmokePayload -path $payloadIncompleteExec -prompt "~exec" -projectRoot $projectRoot -turnId "turn_demo_prompt_004_exec"
  $userIncompleteExecOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadIncompleteExec -projectRoot $projectRoot
  Assert-True ($userIncompleteExecOut.decision -eq "block") "Unresolved response_incomplete should still block explicit execute commands."
  Assert-Contains $userIncompleteExecOut.hookSpecificOutput.additionalContext "mode: recovery_only" "Blocked response_incomplete execute commands should still explain recovery_only mode."

  $completedTask = @"
# 任务清单: smoke

- [√] 1.0 hooks 守卫已验证

## 任务状态符号
- [ ] 待执行
- [√] 已完成
- [X] 执行失败
- [-] 已跳过
- [?] 待确认

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: final

### 功能删减审批
- `feature_removal_risk: clear`
- `feature_removal_approved: no`

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `执行 Archive Readiness Gate` 预期: 门禁通过才归档，否则保持 active 并补收尾证据
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $completedTask

  $sessionCompletedOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-sessionstart.ps1") -inputFile (Join-Path $repoRoot "templates/hooks/sessionstart-hook-fixture.json") -projectRoot $projectRoot
  Assert-Contains $sessionCompletedOut.systemMessage "tasks are terminal" "SessionStart should warn when current_package tasks are terminal."
  Assert-Contains $sessionCompletedOut.hookSpecificOutput.additionalContext "signal: package_completed" "SessionStart completed warning should expose package_completed signal."
  Assert-Contains $sessionCompletedOut.hookSpecificOutput.additionalContext "package_status: completed_looking" "SessionStart completed warning should expose completed-looking package status."
  Assert-Contains $sessionCompletedOut.hookSpecificOutput.additionalContext "Archive Readiness Gate" "SessionStart completed warning should route to Archive Readiness Gate."

  $payloadCompleted = Join-Path $scratchRoot "userpromptsubmit-completed.json"
  New-SmokePayload -path $payloadCompleted -prompt "~exec" -projectRoot $projectRoot -turnId "turn_demo_prompt_005"
  $userCompletedOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadCompleted -projectRoot $projectRoot
  Assert-True ([string]::IsNullOrWhiteSpace($userCompletedOut.decision)) "Completed-looking package should not block the prompt; it should allow the model to run Archive Readiness Gate."
  Assert-Contains $userCompletedOut.systemMessage "不得继续改代码" "Completed-package warning should prohibit code edits while allowing closeout."
  Assert-Contains $userCompletedOut.hookSpecificOutput.additionalContext "package_status: completed_looking" "Completed-package warning should expose package_status for downstream consumption."
  Assert-Contains $userCompletedOut.hookSpecificOutput.additionalContext "severity: Red" "Completed-package warning should emit a Red severity signal."
  Assert-Contains $userCompletedOut.hookSpecificOutput.additionalContext "Archive Readiness Gate" "Completed-package warning should route to Archive Readiness Gate before archive."

  $payloadCompletedNewTask = Join-Path $scratchRoot "userpromptsubmit-completed-new-task.json"
  New-SmokePayload -path $payloadCompletedNewTask -prompt "新增一个新功能" -projectRoot $projectRoot -turnId "turn_demo_prompt_005b"
  $userCompletedNewTaskOut = Invoke-HookJson -scriptPath (Join-Path $repoRoot "scripts/hooks/helloagents-userpromptsubmit.ps1") -inputFile $payloadCompletedNewTask -projectRoot $projectRoot
  try { $completedNewTaskDecision = $userCompletedNewTaskOut.decision } catch { $completedNewTaskDecision = $null }
  Assert-True ([string]::IsNullOrWhiteSpace($completedNewTaskDecision)) "Completed-looking package should not block a new requirement prompt."
  Assert-Contains $userCompletedNewTaskOut.hookSpecificOutput.additionalContext "package_status: completed_looking" "Completed-looking package should still inject context for new requirement prompts."
  Assert-Contains $userCompletedNewTaskOut.hookSpecificOutput.additionalContext "new_requirement_policy" "Completed-looking context should tell the model not to reuse the old package for new work."

  $validatorArchiveMissingReview = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "archive" -package $packageRel
  Assert-True (-not $validatorArchiveMissingReview.ok) "Archive mode should fail completed-looking packages that still lack closeout Review evidence."
  $archiveMissingReviewText = ($validatorArchiveMissingReview.errors -join "`n")
  Assert-Contains $archiveMissingReviewText "Review 记录" "Archive mode should require a non-empty Review record before history migration."

  $archiveReviewSummaryOnlyTask = $completedTask + @"

## Review 记录
- Review: 只有结论没有证据
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $archiveReviewSummaryOnlyTask
  $validatorArchiveReviewSummaryOnly = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "archive" -package $packageRel
  Assert-True (-not $validatorArchiveReviewSummaryOnly.ok) "Archive mode should fail Review records that lack verification or retest evidence."
  Assert-Contains (($validatorArchiveReviewSummaryOnly.errors -join "`n")) "verification or retest evidence" "Archive mode should explain missing evidence."

  $archiveReviewNotRunTask = $completedTask + @"

## Review 记录
- Review: 规格一致性与结构质量已检查
- 验证: 未执行，原因: 忘记补证据
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $archiveReviewNotRunTask
  $validatorArchiveReviewNotRun = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "archive" -package $packageRel
  Assert-True (-not $validatorArchiveReviewNotRun.ok) "Archive mode should fail Review records that say validation was not run."
  Assert-Contains (($validatorArchiveReviewNotRun.errors -join "`n")) "未执行验证" "Archive mode should explain that not-run validation is not evidence."

  $archiveProgressOnlyInInstructionTask = @"
# 任务清单: smoke

- [√] 1.0 hooks 守卫已验证
- [√] 2.0 归档就绪检查：仅当 `progress_phase: final` 已写入快照时才允许归档

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: mid

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `执行 Archive Readiness Gate` 预期: 验证 progress_phase 是否真的在快照中 final

## Review 记录
- Review: 规格一致性与结构质量已检查
- 复测: `pwsh -NoProfile -Command "Write-Output smoke"` 结果: 通过
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $archiveProgressOnlyInInstructionTask
  $validatorArchiveProgressOnlyInInstruction = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "archive" -package $packageRel
  Assert-True (-not $validatorArchiveProgressOnlyInInstruction.ok) "Archive mode should not accept progress_phase: final when it only appears in task instructions."
  Assert-Contains (($validatorArchiveProgressOnlyInInstruction.errors -join "`n")) "inside '## 上下文快照'" "Archive mode should require final progress inside the snapshot section."

  $archiveReadyTask = $completedTask + @"

## Review 记录
- Review: 规格一致性与结构质量已检查
- 复测: `pwsh -NoProfile -Command "Write-Output smoke"` 结果: 通过
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $archiveReadyTask
  $validatorArchiveReady = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "archive" -package $packageRel
  Assert-True ($validatorArchiveReady.ok) "Archive mode should pass only after tasks are terminal, Pending is empty, progress is final, Review is recorded, and status legend lines are ignored."

  $archiveSkippedNoReasonTask = @"
# 任务清单: smoke

- [-] 1.0 明确跳过的任务

## 上下文快照

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: final

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `执行 Archive Readiness Gate` 预期: 检查跳过原因

## Review 记录
- Review: smoke
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $archiveSkippedNoReasonTask
  $validatorArchiveSkippedNoReason = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "archive" -package $packageRel
  Assert-True (-not $validatorArchiveSkippedNoReason.ok) "Archive mode should fail skipped tasks without explicit reasons."
  Assert-Contains (($validatorArchiveSkippedNoReason.errors -join "`n")) "skipped task without" "Archive mode should explain missing skip reason."

  $archiveSkippedWithReasonTask = @"
# 任务清单: smoke

- [-] 1.0 明确跳过的任务
> 备注: 用户明确确认本项不执行

## 上下文快照

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: final

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `执行 Archive Readiness Gate` 预期: 检查跳过原因

## Review 记录
- Review: 规格一致性与跳过原因已记录
- 复测: `pwsh -NoProfile -Command "Write-Output smoke"` 结果: 通过
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $archiveSkippedWithReasonTask
  $validatorArchiveSkippedWithReason = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "archive" -package $packageRel
  Assert-True ($validatorArchiveSkippedWithReason.ok) "Archive mode should allow skipped tasks only when a reason is recorded."

  $missingCarryForwardHow = @"
# 技术设计: smoke

## 执行域声明（Allow/Deny）
- Allow: [`a.ps1`]

verify_min: `pwsh -NoProfile -Command ""Write-Output smoke""`
"@
  Write-Utf8Text -path (Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\how.md")) -text $missingCarryForwardHow
  $validatorMissingCarry = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "plan" -package $packageRel
  $carryWarnText = ($validatorMissingCarry.warnings -join "`n")
  Assert-Contains $carryWarnText "carry_forward_verify" "Plan validator should warn when how.md omits carry_forward_verify."

  $longTaskHow = @"
# 技术设计: smoke

## 执行域声明（Allow/Deny）
- Allow: [`a.ps1`]

verify_min: `pwsh -NoProfile -Command ""Write-Output smoke""`
carry_forward_verify: 无
"@
  $longTaskText = @"
# 任务清单: smoke

- [ ] 1.0 第一步
- [ ] 1.1 第二步
- [ ] 1.2 第三步
- [ ] 1.3 第四步

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: start

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `继续第一个任务` 预期: 完成第一个任务
"@
  Write-Utf8Text -path (Join-Path $projectRoot ($packageRel.Replace('/', '\') + "\how.md")) -text $longTaskHow
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $longTaskText
  $validatorLongTask = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "exec" -package $packageRel
  $longTaskWarnText = ($validatorLongTask.warnings -join "`n")
  Assert-Contains $longTaskWarnText "mid/late/final progress_phase" "Plan validator should warn when long tasks never advance progress_phase beyond start."

  $reroutedTask = @"
# 任务清单: smoke

- [ ] 1.0 继续恢复

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: mid

### 运行时/模型事件（可选，结构化）
- [SRC:TOOL] model_event: model_rerouted

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `继续恢复` 预期: 先做 contract 复核
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $reroutedTask
  $validatorRerouted = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "exec" -package $packageRel
  $reroutedWarnText = ($validatorRerouted.warnings -join "`n")
  Assert-Contains $reroutedWarnText "contract_checkpoint" "Plan validator should warn when model_rerouted is missing contract_checkpoint."

  $designDebtTask = @"
# 任务清单: smoke

- [ ] 1.0 临时方案

## 上下文快照

### 已确认事实（可验证）
- [SRC:CODE] smoke package fixture is present

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: mid

### 结构债务（可选，明确知道是权宜实现时填写）
- [SRC:CODE|USER|TOOL] design_debt: 临时把逻辑收在单点，后续需要拆分

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `继续实现` 预期: 完成临时方案
"@
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $packageRel -taskText $designDebtTask
  $validatorDebt = Invoke-PlanValidatorJson -projectRoot $projectRoot -mode "exec" -package $packageRel
  Assert-True (-not $validatorDebt.ok) "Plan validator should fail when design_debt is recorded without why_now/revisit_trigger."
  $debtErrorText = ($validatorDebt.errors -join "`n")
  Assert-Contains $debtErrorText "revisit_trigger" "Design debt validation should require revisit_trigger."

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
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "recovery_checkpoint: repo_state + 下一步唯一动作" "Stop hook dry-run should preview the recovery checkpoint contract."
  Assert-Contains $stopEventOut.hookSpecificOutput.hookMessage "repo_state:" "Stop hook dry-run should preview repo_state recovery evidence."

  $archivePackageRel = New-ArchiveReadyPackage -projectRoot $projectRoot -packageName "202604011200_archive_ready"
  Set-CurrentPackage -projectRoot $projectRoot -packageRel $archivePackageRel
  $archiveOut = Invoke-ArchivePlanPackageJson -projectRoot $projectRoot -package $archivePackageRel
  Assert-True ($archiveOut.ok -eq $true) "Archive script should archive a ready package."
  Assert-True ($archiveOut.exit_code -eq 0) "Archive script should exit 0 for a ready package."
  Assert-Contains $archiveOut.history_package "HAGSWorks/history/2026-04/202604011200_archive_ready/" "Archive script should place packages under history/YYYY-MM."
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/plan/202604011200_archive_ready") -PathType Container)) "Archive script should remove the source package from HAGSWorks/plan."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/2026-04/202604011200_archive_ready") -PathType Container) "Archive script should create the history package directory."
  $pointerAfterArchive = Read-Utf8Text -path (Join-Path $projectRoot "HAGSWorks/plan/_current.md")
  Assert-Contains $pointerAfterArchive "current_package:" "Archive script should preserve the current_package key."
  Assert-NotContains $pointerAfterArchive "202604011200_archive_ready" "Archive script should clear _current.md when it pointed to the archived package."
  $historyIndexAfterArchive = Read-Utf8Text -path (Join-Path $projectRoot "HAGSWorks/history/index.md")
  Assert-Contains $historyIndexAfterArchive "202604011200_archive_ready" "Archive script should append history/index.md."
  Assert-Contains $historyIndexAfterArchive "validate-plan-package.ps1 -Mode archive" "Archive index entry should include validation evidence."

  $abandonRel = New-UnexecutedPackage -projectRoot $projectRoot -packageName "202604011210_abandon_unexecuted"
  $abandonOut = Invoke-AbandonPlanPackageJson -projectRoot $projectRoot -package $abandonRel
  Assert-True ($abandonOut.ok -eq $true) "Abandon cleanup script should archive an unexecuted non-active package."
  Assert-True ($abandonOut.exit_code -eq 0) "Abandon cleanup script should exit 0 for an unexecuted package."
  Assert-Contains $abandonOut.history_package "HAGSWorks/history/2026-04/202604011210_abandon_unexecuted/" "Abandon cleanup script should place packages under history/YYYY-MM."
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/plan/202604011210_abandon_unexecuted") -PathType Container)) "Abandon cleanup script should remove the source package from HAGSWorks/plan."
  $abandonedTask = Read-Utf8Text -path (Join-Path $projectRoot "HAGSWorks/history/2026-04/202604011210_abandon_unexecuted/task.md")
  Assert-Contains $abandonedTask "archive_intent: abandoned_unexecuted" "Abandon cleanup script should stamp abandoned intent into task.md."
  Assert-Contains $abandonedTask "未执行（用户放弃执行；这不是完成证据）" "Abandon cleanup script should mark not-run validation as non-completion evidence."
  $historyIndexAfterAbandon = Read-Utf8Text -path (Join-Path $projectRoot "HAGSWorks/history/index.md")
  Assert-Contains $historyIndexAfterAbandon "abandoned_unexecuted" "Abandon cleanup script should append abandoned_unexecuted index metadata."

  $templateAbandonRel = "HAGSWorks/plan/202604011213_abandon_template_placeholders"
  $templateAbandonDir = Join-Path $projectRoot $templateAbandonRel
  New-Item -ItemType Directory -Path $templateAbandonDir -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot "templates/plan-why-template.md") -Destination (Join-Path $templateAbandonDir "why.md") -Force
  Copy-Item -LiteralPath (Join-Path $repoRoot "templates/plan-how-template.md") -Destination (Join-Path $templateAbandonDir "how.md") -Force
  Copy-Item -LiteralPath (Join-Path $repoRoot "templates/plan-task-template.md") -Destination (Join-Path $templateAbandonDir "task.md") -Force
  $templateAbandonOut = Invoke-AbandonPlanPackageJson -projectRoot $projectRoot -package $templateAbandonRel
  Assert-True ($templateAbandonOut.ok -eq $true) "Abandon cleanup script should ignore template HTML comments/placeholders when classifying execution evidence."
  $templateAbandonedTask = Read-Utf8Text -path (Join-Path $projectRoot "HAGSWorks/history/2026-04/202604011213_abandon_template_placeholders/task.md")
  Assert-Contains $templateAbandonedTask "archive_intent: abandoned_unexecuted" "Template-based abandoned cleanup should stamp abandoned intent into task.md."

  $abandonCurrentRel = New-UnexecutedPackage -projectRoot $projectRoot -packageName "202604011211_abandon_current_guard"
  Set-CurrentPackage -projectRoot $projectRoot -packageRel $abandonCurrentRel
  $abandonCurrentBlocked = Invoke-AbandonPlanPackageJson -projectRoot $projectRoot -package $abandonCurrentRel
  Assert-True ($abandonCurrentBlocked.ok -eq $false) "Abandon cleanup script should reject current_package without ConfirmCurrent."
  Assert-Contains (($abandonCurrentBlocked.errors -join "`n")) "current_package" "Abandon current-package rejection should explain the current pointer risk."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/plan/202604011211_abandon_current_guard") -PathType Container) "Abandon cleanup script should keep current packages active when ConfirmCurrent is absent."

  $abandonExecutedRel = New-ArchiveReadyPackage -projectRoot $projectRoot -packageName "202604011212_abandon_executed_guard"
  $abandonExecutedBlocked = Invoke-AbandonPlanPackageJson -projectRoot $projectRoot -package $abandonExecutedRel
  Assert-True ($abandonExecutedBlocked.ok -eq $false) "Abandon cleanup script should reject packages that contain execution evidence."
  Assert-Contains (($abandonExecutedBlocked.errors -join "`n")) "execution evidence" "Abandon executed-package rejection should explain that resume/archive gate is required."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/plan/202604011212_abandon_executed_guard") -PathType Container) "Abandon cleanup script should keep executed packages under HAGSWorks/plan."

  $archiveConflictRel = New-ArchiveReadyPackage -projectRoot $projectRoot -packageName "202604011200_archive_ready"
  Set-CurrentPackage -projectRoot $projectRoot -packageRel $archiveConflictRel
  $archiveConflictOut = Invoke-ArchivePlanPackageJson -projectRoot $projectRoot -package $archiveConflictRel
  Assert-True ($archiveConflictOut.ok -eq $true) "Archive script should archive conflict packages by suffixing instead of overwriting."
  Assert-True ($archiveConflictOut.history_conflict -eq $true) "Archive script should report a history conflict when suffixing."
  Assert-Contains $archiveConflictOut.history_package "202604011200_archive_ready_v2/" "Archive script should append _v2 on first history conflict."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/2026-04/202604011200_archive_ready") -PathType Container) "Archive script should keep the original history package."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/2026-04/202604011200_archive_ready_v2") -PathType Container) "Archive script should create the suffixed history package."

  $archiveIndexBlockedRel = New-ArchiveReadyPackage -projectRoot $projectRoot -packageName "202604011201_archive_index_blocked"
  Set-CurrentPackage -projectRoot $projectRoot -packageRel $archiveIndexBlockedRel
  if (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/index.md")) {
    Remove-Item -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/index.md") -Force
  }
  New-Item -ItemType Directory -Path (Join-Path $projectRoot "HAGSWorks/history/index.md") -Force | Out-Null
  $archiveIndexBlockedOut = Invoke-ArchivePlanPackageJson -projectRoot $projectRoot -package $archiveIndexBlockedRel
  Assert-True ($archiveIndexBlockedOut.ok -eq $false) "Archive script should reject a non-writable history index target before moving."
  Assert-True (($archiveIndexBlockedOut.rollback_attempted -eq $false) -or ($archiveIndexBlockedOut.rollback_succeeded -eq $true)) "Pre-move index failures should not leave a half-migrated package."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/plan/202604011201_archive_index_blocked") -PathType Container) "Archive script should keep blocked packages active under HAGSWorks/plan when index target is invalid."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/index.md") -PathType Container) "Smoke setup should keep the index path as a directory for this check."
  Remove-Item -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/index.md") -Force
  Write-Utf8Text -path (Join-Path $projectRoot "HAGSWorks/history/index.md") -text "# 历史方案索引`n"

  $archiveRollbackRel = New-ArchiveReadyPackage -projectRoot $projectRoot -packageName "202604011202_archive_rollback"
  Set-CurrentPackage -projectRoot $projectRoot -packageRel $archiveRollbackRel
  Set-FileReadOnly -path (Join-Path $projectRoot "HAGSWorks/history/index.md") -readOnly $true
  try {
    $archiveRollbackOut = Invoke-ArchivePlanPackageJson -projectRoot $projectRoot -package $archiveRollbackRel
    Assert-True ($archiveRollbackOut.ok -eq $false) "Archive script should fail when index append is blocked."
    Assert-True ($archiveRollbackOut.rollback_attempted -eq $true) "Archive script should attempt rollback after post-move failure."
    Assert-True ($archiveRollbackOut.rollback_succeeded -eq $true) "Archive script should roll back a post-move failure."
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/plan/202604011202_archive_rollback") -PathType Container) "Rollback should restore the package to plan."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/2026-04/202604011202_archive_rollback") -PathType Container)) "Rollback should remove the half-migrated history package."
  } finally {
    Set-FileReadOnly -path (Join-Path $projectRoot "HAGSWorks/history/index.md") -readOnly $false
    Write-Utf8Text -path (Join-Path $projectRoot "HAGSWorks/history/index.md") -text "# 历史方案索引`n"
  }

  $archiveBlockedRel = New-ArchiveReadyPackage -projectRoot $projectRoot -packageName "202604011201_archive_blocked"
  Set-SmokeTaskText -projectRoot $projectRoot -packageRel $archiveBlockedRel -taskText @"
# 任务清单: archive blocked smoke

- [ ] 1.0 仍未完成的任务

## 上下文快照

### Repo 状态（复现/防漂移，执行域必填）
- [SRC:TOOL] repo_state: branch=smoke head=smoke dirty=false diffstat=none

### 决策（做了什么选择 + 为什么）
- [SRC:CODE|TOOL] progress_phase: mid

### 待用户输入（Pending）

### 下一步唯一动作（可执行）
- 下一步唯一动作: `继续完成任务` 预期: 未完成任务不能归档
"@
  Set-CurrentPackage -projectRoot $projectRoot -packageRel $archiveBlockedRel
  $archiveBlockedOut = Invoke-ArchivePlanPackageJson -projectRoot $projectRoot -package $archiveBlockedRel
  Assert-True ($archiveBlockedOut.ok -eq $false) "Archive script should reject packages that fail Archive Readiness Gate."
  Assert-True ($archiveBlockedOut.exit_code -ne 0) "Archive script should exit non-zero when Archive Readiness Gate fails."
  Assert-Contains (($archiveBlockedOut.errors -join "`n")) "pending tasks" "Archive script should surface validator errors for not-ready packages."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/plan/202604011201_archive_blocked") -PathType Container) "Archive script should keep blocked packages active under HAGSWorks/plan."
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot "HAGSWorks/history/2026-04/202604011201_archive_blocked") -PathType Container)) "Archive script should not create history entries for blocked packages."

  Write-Output "OK: skill pack smoke validation passed"
} finally {
  if (-not $KeepArtifacts -and (Test-Path -LiteralPath $scratchRoot)) {
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force
  }
}
