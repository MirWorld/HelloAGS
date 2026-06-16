param(
  [string]$PlanRoot = "HAGSWorks/plan",
  [string]$Package = "",
  [ValidateSet("plan", "exec", "archive")]
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
  $pattern = '(?m)^\s*(?:' + $headingRegex + ')\s*$\r?\n'
  $m = [regex]::Match($text, $pattern)
  if ($m.Success) {
    $start = $m.Index + $m.Length
    $tail = $text.Substring($start)
    $next = [regex]::Match($tail, '(?m)^\s*#{2,6}\s+')
    if ($next.Success) {
      return $tail.Substring(0, $next.Index)
    }
    return $tail
  }
  return ""
}

function Get-MarkdownH2SectionBody([string]$text, [string]$headingRegex) {
  if ($null -eq $text) {
    return ""
  }
  $pattern = '(?m)^\s*(?:' + $headingRegex + ')\s*$\r?\n'
  $m = [regex]::Match($text, $pattern)
  if ($m.Success) {
    $start = $m.Index + $m.Length
    $tail = $text.Substring($start)
    $next = [regex]::Match($tail, '(?m)^\s*##\s+')
    if ($next.Success) {
      return $tail.Substring(0, $next.Index)
    }
    return $tail
  }
  return ""
}

function Get-KeyValueLines([string]$text, [string]$key) {
  if ($null -eq $text) {
    return @()
  }
  $escapedKey = [regex]::Escape($key)
  $lines = @()
  foreach ($line in ($text -split "\r?\n")) {
    $m = [regex]::Match($line, "(?i)\b${escapedKey}\b\s*[:：]\s*(?<rest>.+)$")
    if (-not $m.Success) {
      continue
    }
    $rest = $m.Groups["rest"].Value.Trim()
    $rest = $rest.Trim("*").Trim()
    $lines += $rest
  }
  return $lines
}

function Test-ConcreteValue([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $false
  }
  $trimmed = $value.Trim().Trim([char]0x60, '"', "'", "*").Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return $false
  }
  if ($trimmed -match '^(?:unknown|未定|待确认|none|n/a|na|无)(?:\b|$)') {
    return $false
  }
  if ($trimmed -match '^(?:\.{3}|…|\[.*\]|<.*>)$') {
    return $false
  }
  if ($trimmed -match '^(?:\.{3}|…)$') {
    return $false
  }
  return $true
}

function Test-IsPathUnderDirectory([string]$path, [string]$directory) {
  if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($directory)) {
    return $false
  }

  try {
    $fullPath = [System.IO.Path]::GetFullPath($path)
    $fullDirectory = [System.IO.Path]::GetFullPath($directory)
  } catch {
    return $false
  }

  $separator = [System.IO.Path]::DirectorySeparatorChar
  $altSeparator = [System.IO.Path]::AltDirectorySeparatorChar
  if (-not ($fullDirectory.EndsWith($separator) -or $fullDirectory.EndsWith($altSeparator))) {
    $fullDirectory = $fullDirectory + $separator
  }

  return $fullPath.StartsWith($fullDirectory, [System.StringComparison]::OrdinalIgnoreCase)
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
  git_root = ""
  plan_root = ""
  mode = $Mode
  checked_packages = @()
  errors = @()
  warnings = @()
}

function Add-Error([string]$message) {
  $script:report.ok = $false
  $script:report.errors += $message
}

function Add-Warn([string]$message) {
  $script:report.warnings += $message
  if (-not $Json) {
    Write-Output "WARN: $message"
  }
}

function Emit-Json() {
  $script:report | ConvertTo-Json -Depth 8
}

$projectRoot = Get-ProjectRoot
$gitRoot = $null
try {
  Push-Location $projectRoot
  $gitRoot = Get-GitRoot
} finally {
  Pop-Location
}
$planRootFull = (Join-Path $projectRoot $PlanRoot)
$report.project_root = $projectRoot
$report.git_root = $gitRoot
$report.plan_root = $planRootFull

if (-not (Test-Path -LiteralPath $planRootFull)) {
  Add-Error "plan root not found: $PlanRoot (resolved: $planRootFull)"
  if ($Json) { Emit-Json }
  exit 1
}

$currentPointer = Join-Path $planRootFull "_current.md"
if (Test-Path -LiteralPath $currentPointer) {
  $pointerText = Read-Text $currentPointer
  $m = [regex]::Match($pointerText, '(?m)^\s*current_package\s*:\s*(?<path>.*)\s*$')
  if ($m.Success) {
    $raw = $m.Groups["path"].Value
    $raw = [regex]::Replace($raw, '\s+#.*$', '')
    $raw = $raw.Trim()

    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      $pathValue = $raw.Trim('"', "'", [char]0x60)
      $looksPlaceholder = [regex]::IsMatch($pathValue, '^(?:\.{3}|…)$')
      if ($looksPlaceholder) {
        Add-Warn "_current.md current_package looks like a placeholder: '$raw'"
      } else {
        if ($pathValue -match '(?i)\bHAGSWorks[\\/]+history\b') {
          Add-Warn "_current.md current_package points to history (invalid; should be under HAGSWorks/plan): '$pathValue'"
        }

        $normalized = $pathValue.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
        $full = $normalized
        if (-not ([System.IO.Path]::IsPathRooted($full))) {
          $full = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $normalized))
        } else {
          $full = [System.IO.Path]::GetFullPath($full)
        }

        $planFull = [System.IO.Path]::GetFullPath($planRootFull)
        $inPlan = Test-IsPathUnderDirectory -path $full -directory $planFull
        if (-not $inPlan) {
          Add-Warn "_current.md current_package is outside plan root (expected under: $PlanRoot): '$pathValue' (resolved: $full)"
        } elseif (-not (Test-Path -LiteralPath $full -PathType Container)) {
          Add-Warn "_current.md current_package directory not found: '$pathValue' (resolved: $full)"
        }
      }
    }
  } else {
    Add-Warn "_current.md missing current_package key: $currentPointer"
  }
}

$packages = @()
if (-not [string]::IsNullOrWhiteSpace($Package)) {
  if ([System.IO.Path]::IsPathRooted($Package)) {
    $packageFull = $Package
  } else {
    $packageFull = Join-Path $projectRoot $Package
  }
  if (-not (Test-Path -LiteralPath $packageFull)) {
    Add-Error "package not found: $Package (resolved: $packageFull)"
    if ($Json) { Emit-Json }
    exit 1
  }
  $packageResolved = (Resolve-Path -LiteralPath $packageFull).Path
  if (-not (Test-IsPathUnderDirectory -path $packageResolved -directory $planRootFull)) {
    Add-Error "package is outside plan root: $Package (resolved: $packageResolved; expected under: $PlanRoot)"
    if ($Json) { Emit-Json }
    exit 1
  }
  $packages = @($packageResolved)
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
      $textNoCode = Strip-HtmlComments (Strip-FencedCodeBlocks $text)
      $verifyMinLines = @(Get-KeyValueLines -text $textNoCode -key "verify_min")
      if ($verifyMinLines.Count -eq 0) {
        Add-Error "package '${pkgName}' how.md missing verify_min (expected a line like: verify_min: <command/steps>; signal: archive_gate_missing_evidence)"
      } else {
        $hasConcreteVerifyMin = $false
        foreach ($line in $verifyMinLines) {
          if (Test-ConcreteValue $line) {
            $hasConcreteVerifyMin = $true
            break
          }
        }
        if (($Mode -in @("exec", "archive")) -and -not $hasConcreteVerifyMin) {
          Add-Error "package '${pkgName}' how.md verify_min is not concrete (${Mode} mode requires a runnable verify_min, not unknown/无/placeholders; signal: archive_gate_missing_evidence)"
        }
      }

      $carryForwardLines = @(Get-KeyValueLines -text $textNoCode -key "carry_forward_verify")
      if ($carryForwardLines.Count -eq 0) {
        Add-Warn "package '${pkgName}' how.md missing carry_forward_verify. Recommended: explicitly state '无' or list the previous validations that must be rerun when the same Workset is touched again."
      } else {
        $hasConcreteCarryForward = $false
        foreach ($line in $carryForwardLines) {
          if ((Test-ConcreteValue $line) -or ($line -match '^\s*无\s*$')) {
            $hasConcreteCarryForward = $true
            break
          }
        }
        if (-not $hasConcreteCarryForward) {
        Add-Warn "package '${pkgName}' how.md carry_forward_verify still looks like a placeholder. Replace it with a concrete list or explicit '无'."
        }
      }
    }

    if ($fileName -eq "task.md") {
      $textNoCode = Strip-FencedCodeBlocks $text
      $snapshotBody = Get-MarkdownH2SectionBody -text $textNoCode -headingRegex '##\s*上下文快照'
      $snapshotBody = Strip-HtmlComments $snapshotBody
      $taskListText = $textNoCode
      $taskLegendMatch = [regex]::Match($taskListText, '(?ms)^\s*##\s*任务状态符号\s*$')
      if ($taskLegendMatch.Success) {
        $taskListText = $taskListText.Substring(0, $taskLegendMatch.Index)
      }
      $taskItemAnyPattern = '(?m)^\s*-\s*\[(?:\s|√|✓|X|x|-|\?)\]\s+'
      $taskItemOpenPattern = '(?m)^\s*-\s*\[\s\]\s+'
      $taskItemFailedPattern = '(?m)^\s*-\s*\[(?:X|x)\]\s+'
      $taskItemConfirmPattern = '(?m)^\s*-\s*\[\?\]\s+'
      $taskItemSkippedPattern = '(?m)^\s*-\s*\[-\]\s+'

      if ($taskListText -notmatch $taskItemAnyPattern) {
        Add-Error "package '${pkgName}' task.md has no task items (- [ ]/[√]/[✓]/[X]/[x]/[-]/[?])"
      }

      if ($Mode -eq "exec") {
        if ($taskListText -notmatch $taskItemOpenPattern) {
          Add-Error "package '${pkgName}' task.md has no pending tasks (- [ ]) (exec mode requires at least one pending task). If you need follow-up work, add a Delta to ## 上下文快照 and create a new - [ ] task."
        }
      }

      if ($Mode -eq "archive") {
        if ($taskListText -match $taskItemOpenPattern) {
          Add-Error "package '${pkgName}' task.md still has pending tasks (- [ ]) (archive mode requires all tasks to be terminal). Keep the package under HAGSWorks/plan and continue from _current.md."
        }
        if ($taskListText -match $taskItemFailedPattern) {
          Add-Error "package '${pkgName}' task.md still has failed tasks (- [X]/[x]) (archive mode requires failures to be resolved or explicitly converted to skipped with a reason)."
        }
        if ($taskListText -match $taskItemConfirmPattern) {
          Add-Error "package '${pkgName}' task.md still has confirmation tasks (- [?]) (archive mode requires all confirmations to be closed or left as Pending)."
        }
        $taskLines = $taskListText -split "\r?\n"
        for ($i = 0; $i -lt $taskLines.Count; $i++) {
          if ($taskLines[$i] -notmatch $taskItemSkippedPattern) {
            continue
          }

          $hasSkipReason = $false
          for ($j = $i + 1; $j -lt [Math]::Min($taskLines.Count, $i + 4); $j++) {
            $next = $taskLines[$j].Trim()
            if ([string]::IsNullOrWhiteSpace($next)) {
              continue
            }
            if ($next -match $taskItemAnyPattern) {
              break
            }
            if ($next -match '^>\s*备注\s*[:：]\s*\S') {
              $hasSkipReason = $true
            }
            break
          }
          if (-not $hasSkipReason) {
            Add-Error "package '${pkgName}' task.md has skipped task without a following '> 备注: <reason>' (archive mode requires explicit reasons for [-] tasks; signal: archive_gate_missing_evidence)."
          }
        }
      }

      if ($Mode -in @("exec", "archive")) {
        $nextBody = Get-MarkdownSectionBody -text $textNoCode -headingRegex '###\s*下一步唯一动作.*'
        $nextBody = Strip-HtmlComments $nextBody
        $nextLines = $nextBody -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $nextActionLines = $nextLines | Where-Object { $_ -match '下一步唯一动作\s*[:：]\s*\S' }
        if ($nextActionLines.Count -eq 0) {
          Add-Error "package '${pkgName}' task.md missing next_unique_action under '### 下一步唯一动作' (${Mode} mode requires a concrete next_unique_action)"
        } else {
          $okNextAction = $false
          foreach ($line in $nextActionLines) {
            $m = [regex]::Match($line, '下一步唯一动作\s*[:：]\s*(?<rest>.+)$')
            if (-not $m.Success) {
              continue
            }

            $rest = $m.Groups["rest"].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($rest)) {
              continue
            }

            $isEllipsisOnly = [regex]::IsMatch($rest, '^(?:`)?\s*(?:\.{3}|…)\s*(?:`)?\s*$')
            $hasBacktickedEllipsis = [regex]::IsMatch($rest, '`\s*(?:\.{3}|…)\s*`')
            if ($isEllipsisOnly -or $hasBacktickedEllipsis) {
              continue
            }

            $okNextAction = $true
            break
          }

          if (-not $okNextAction) {
            Add-Error "package '${pkgName}' task.md next_unique_action looks like a template placeholder (${Mode} mode requires a concrete next_unique_action). Expected a line like: 下一步唯一动作: `<command>` 预期: ..."
          }
        }

        if ($Mode -eq "archive") {
          $progressLines = @(Get-KeyValueLines -text $snapshotBody -key "progress_phase")
          $hasFinalProgress = $false
          foreach ($line in $progressLines) {
            if ($line -match '^\s*final\b') {
              $hasFinalProgress = $true
              break
            }
          }
          if (-not $hasFinalProgress) {
            Add-Error "package '${pkgName}' task.md archive mode requires progress_phase: final inside '## 上下文快照' before migration to history. If work is partial, keep the package active under HAGSWorks/plan. signal: archive_gate_missing_evidence"
          }
        } elseif ($snapshotBody -notmatch '(?mi)\bprogress_phase\s*[:：]\s*(start|mid|late|final)\b') {
          Add-Warn "package '${pkgName}' task.md snapshot missing progress_phase. Recommended: record start|mid|late|final so long tasks do not wait until the end to expose drift."
        } else {
          $taskCount = ([regex]::Matches($taskListText, $taskItemAnyPattern)).Count
          $hasMidOrLater = ($snapshotBody -match '(?mi)\bprogress_phase\s*[:：]\s*(mid|late|final)\b')
          if ($taskCount -ge 4 -and -not $hasMidOrLater) {
            Add-Warn "package '${pkgName}' looks like a long task (>=4 task items) but snapshot has no mid/late/final progress_phase checkpoint yet. Add at least one mid-phase checkpoint before final Review."
          }
        }

        if ($gitRoot) {
          $repoBody = Get-MarkdownSectionBody -text $textNoCode -headingRegex '###\s*Repo\s*状态.*'
          $repoBody = Strip-HtmlComments $repoBody
          $repoLines = $repoBody -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
          $repoStateLines = $repoLines | Where-Object { $_ -match '(?i)\brepo_state\s*[:：]\s*\S' }
          if ($repoStateLines.Count -eq 0) {
            Add-Error "package '${pkgName}' task.md missing repo_state checkpoint under '### Repo 状态' (${Mode} mode requires repo_state when git is available)"
          } else {
            $okRepoState = $false
            foreach ($line in $repoStateLines) {
              $looksPlaceholder = [regex]::IsMatch($line, '(?i)\b(?:branch|head|dirty|diffstat)\s*=\s*(?:\.{3}|…)\b')
              if ($looksPlaceholder) {
                continue
              }
              $hasHead = [regex]::IsMatch($line, '(?i)\bhead\s*=\s*\S+')
              $hasDirty = [regex]::IsMatch($line, '(?i)\bdirty\s*=\s*\S+')
              if ($hasHead -and $hasDirty) {
                $okRepoState = $true
                break
              }
            }
            if (-not $okRepoState) {
              Add-Error "package '${pkgName}' task.md repo_state looks like a template placeholder or missing head/dirty (${Mode} mode requires a concrete repo_state). Expected a line like: repo_state: branch=<name> head=<sha> dirty=<true/false> diffstat=<...>"
            }
          }
        }

        if ($Mode -eq "archive") {
          $reviewBody = Get-MarkdownSectionBody -text $textNoCode -headingRegex '##\s*Review\s*记录'
          $reviewBody = Strip-HtmlComments $reviewBody
          $reviewLines = $reviewBody -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
          $reviewLines = $reviewLines | Where-Object {
            -not ($_ -match '^（?仅在完成收尾时填写') -and
            -not ($_ -match '^小任务可只写') -and
            -not ($_ -match '^\(?仅在命中时填写')
          }
          if ($reviewLines.Count -eq 0) {
            Add-Error "package '${pkgName}' task.md archive mode requires a non-empty '## Review 记录'. Keep the package active until Review evidence and retest summary are recorded. signal: archive_gate_missing_evidence"
          } else {
            $hasReviewSummary = $false
            $hasReviewEvidence = $false
            foreach ($line in $reviewLines) {
              if ($line -match '(?i)\breview\b|结论|摘要|问题|修复') {
                $hasReviewSummary = $true
              }
              $looksLikeEvidence = ($line -match '(?i)复测|验证|build|test|lint|fmt|security|check|运行|命令')
              $hasPositiveResult = ($line -match '(?i)通过|成功|pass(?:ed)?|ok\b|exit\s*0|结果\s*[:：]\s*0\b|未触发|不适用')
              $isNegativeEvidence = ($line -match '(?i)未执行|未运行|未验证|未复测|not\s+run|skipp?ed')
              if ($looksLikeEvidence -and $hasPositiveResult -and -not $isNegativeEvidence) {
                $hasReviewEvidence = $true
              }
            }
            if (-not $hasReviewSummary) {
              Add-Error "package '${pkgName}' task.md archive mode requires Review 记录 to include a summary/decision line (e.g. Review/结论/摘要/问题/修复). signal: archive_gate_missing_evidence"
            }
            if (-not $hasReviewEvidence) {
              Add-Error "package '${pkgName}' task.md archive mode requires Review 记录 to include positive verification or retest evidence (e.g. 复测/验证/build/test/lint/fmt/security/check with 通过/pass/ok/exit 0). '未执行验证' is not evidence. signal: archive_gate_missing_evidence"
            }
          }
        }

        $designDebtBody = Get-MarkdownSectionBody -text $textNoCode -headingRegex '###\s*结构债务.*'
        $designDebtBody = Strip-HtmlComments $designDebtBody
        $designDebtLines = $designDebtBody -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $hasDesignDebt = ($designDebtLines | Where-Object { $_ -match 'design_debt\s*[:：]\s*\S' }).Count -gt 0
        if ($hasDesignDebt) {
          $hasWhyNow = ($designDebtLines | Where-Object { $_ -match 'why_now\s*[:：]\s*\S' }).Count -gt 0
          $hasRevisitTrigger = ($designDebtLines | Where-Object { $_ -match 'revisit_trigger\s*[:：]\s*\S' }).Count -gt 0
          if (-not ($hasWhyNow -and $hasRevisitTrigger)) {
            Add-Error "package '${pkgName}' task.md records design_debt but is missing why_now or revisit_trigger. Temporary paths must leave a concrete debt trail."
          }
        }

        # High-risk runtime signals: response.incomplete should hard-stop execution until a recovery checkpoint exists.
        # NOTE: Get-MarkdownSectionBody stops at the next heading of any level (##/###/...),
        # so it cannot be used to capture an H2 section that contains H3 subsections.
        # For snapshots we want the whole H2 block until the next H2.
        if (-not [string]::IsNullOrWhiteSpace($snapshotBody)) {
          $eventMatches = [regex]::Matches($snapshotBody, '(?im)^\s*-\s*\[SRC:TOOL\]\s*model_event\s*[:：]\s*(?<kind>\S+)(?:\s+#.*)?\s*$')
          if ($eventMatches.Count -gt 0) {
            $lastIncomplete = $null
            $lastRerouted = $null
            foreach ($m in $eventMatches) {
              $kind = $m.Groups["kind"].Value.Trim([char]0x60, '"', "'", ",", ";")
              if ($kind -match '(?i)^response[._]incomplete\b') {
                $lastIncomplete = $m
              }
              if ($kind -match '(?i)^model[._/]rerouted\b') {
                $lastRerouted = $m
              }
            }

            if ($lastIncomplete) {
              $after = ""
              try {
                $start = [Math]::Min($snapshotBody.Length, $lastIncomplete.Index + $lastIncomplete.Length)
                $after = $snapshotBody.Substring($start)
              } catch {
                $after = ""
              }

              $hasRepoAfter = ($after -match '(?im)\brepo_state\s*[:：]\s*\S')
              $hasNextAfter = ($after -match '(?im)下一步唯一动作\s*[:：]\s*\S')
              $hasContractAfter = ($after -match '(?im)\bcontract_checkpoint\s*[:：]\s*(ok|needs_realign)\b')
              if (-not ($hasRepoAfter -and $hasNextAfter)) {
                Add-Error "package '${pkgName}' task.md contains model_event: response_incomplete but has no recovery checkpoint after it. Add a new repo_state + next_unique_action AFTER the response_incomplete event before entering exec mode."
              }
              if (-not $hasContractAfter) {
                Add-Error "package '${pkgName}' task.md contains model_event: response_incomplete but has no contract_checkpoint after it. Add contract_checkpoint: ok|needs_realign AFTER the response_incomplete event before entering exec mode."
              }
            }

            if ($lastRerouted) {
              $after = ""
              try {
                $start = [Math]::Min($snapshotBody.Length, $lastRerouted.Index + $lastRerouted.Length)
                $after = $snapshotBody.Substring($start)
              } catch {
                $after = ""
              }

              $hasRepoAfter = ($after -match '(?im)\brepo_state\s*[:：]\s*\S')
              $hasNextAfter = ($after -match '(?im)下一步唯一动作\s*[:：]\s*\S')
              $hasContractAfter = ($after -match '(?im)\bcontract_checkpoint\s*[:：]\s*(ok|needs_realign)\b')
              if (-not ($hasRepoAfter -and $hasNextAfter)) {
                Add-Warn "package '${pkgName}' task.md contains model_event: model_rerouted but has no recovery checkpoint after it. Recommended: add a new repo_state + next_unique_action AFTER the model_rerouted event to reduce resume/compaction redo risk."
              }
              if (-not $hasContractAfter) {
                Add-Warn "package '${pkgName}' task.md contains model_event: model_rerouted but has no contract_checkpoint after it. Recommended: add contract_checkpoint: ok|needs_realign AFTER the model_rerouted event before entering exec mode."
              }
            }
          }

          $compactMatches = [regex]::Matches($snapshotBody, '(?im)^\s*-\s*\[SRC:TOOL\]\s*compact_event\s*[:：]\s*(?<kind>\S+)(?:\s+#.*)?\s*$')
          if ($compactMatches.Count -gt 0) {
            $lastPostCompact = $null
            foreach ($m in $compactMatches) {
              $kind = $m.Groups["kind"].Value.Trim([char]0x60, '"', "'", ",", ";")
              if ($kind -match '(?i)^post_compact\b') {
                $lastPostCompact = $m
              }
            }

            if ($lastPostCompact) {
              $after = ""
              try {
                $start = [Math]::Min($snapshotBody.Length, $lastPostCompact.Index + $lastPostCompact.Length)
                $after = $snapshotBody.Substring($start)
              } catch {
                $after = ""
              }

              $hasRepoAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?repo_state\s*[:：]\s*\S')
              $hasNextAfter = ($after -match '(?im)^\s*-\s*下一步唯一动作\s*[:：]\s*\S')
              $hasHydrationRequiredAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?resume_hydration_required\s*[:：]\s*yes\b')
              $hasHydratedFromPackageAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?hydrated_from_package\s*[:：]\s*\S')
              $hasHydrationSourceAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?hydration_source\s*[:：]\s*`?_current\.md\s*\+\s*task\.md\s*\+\s*repo_state`?\b')
              $hasRebootOkAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?reboot_check\s*[:：]\s*ok\b')
              $hasContractOkAfter = ($after -match '(?im)^\s*-\s*(?:\[[^\]]+\]\s*)?contract_checkpoint\s*[:：]\s*ok\b')

              if (-not ($hasRepoAfter -and $hasNextAfter)) {
                Add-Error "package '${pkgName}' task.md contains compact_event: post_compact but has no recovery checkpoint after it. Add repo_state + next_unique_action AFTER post_compact before entering exec mode."
              }
              if (-not ($hasHydrationRequiredAfter -and $hasHydratedFromPackageAfter -and $hasHydrationSourceAfter)) {
                Add-Error "package '${pkgName}' task.md contains compact_event: post_compact but is missing hydration metadata. Add resume_hydration_required: yes + hydrated_from_package + hydration_source AFTER post_compact."
              }
              if (-not $hasRebootOkAfter) {
                Add-Error "package '${pkgName}' task.md contains compact_event: post_compact but has no reboot_check: ok after it. Run Resume Hydration Gate before entering exec mode."
              }
              if (-not $hasContractOkAfter) {
                Add-Error "package '${pkgName}' task.md contains compact_event: post_compact but has no contract_checkpoint: ok after it. Confirm goal/success/non-goals/constraints before entering exec mode."
              }
            }
          }
        }

        $pendingBody = Get-MarkdownSectionBody -text $textNoCode -headingRegex '###\s*待用户输入（Pending）'
        $pendingBody = Strip-HtmlComments $pendingBody
        $pendingLines = $pendingBody -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        # Backward compatible: ignore template-like placeholder TODO lines that still contain ellipsis.
        $pendingLines = $pendingLines | Where-Object { -not (($_ -match '^\-\s*\[SRC:TODO\]') -and (($_ -match '…') -or ($_ -match '\.\.\.'))) }
        if ($pendingLines.Count -gt 0) {
          Add-Error "package '${pkgName}' task.md has unresolved Pending items (${Mode} mode requires Pending to be empty)"
        }
      }
    }
  }
}

if ($Json) {
  Emit-Json
  if (-not $report.ok) {
    exit 1
  }
  exit 0
}

if (-not $report.ok) {
  $summary = "Plan package validation failed:`n" + ($report.errors -join "`n")
  Write-Error $summary
  exit 1
}

Write-Output "OK: plan package validation passed ($($packages.Count) package(s))"
