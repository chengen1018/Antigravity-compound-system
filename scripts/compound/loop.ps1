<#
.SYNOPSIS
    任務執行迴圈 — 逐一執行 tasks，每完成一個做 checkpoint commit。

.DESCRIPTION
    從 compound.config.json 讀取設定，使用 prompt.md 模板，
    迭代執行任務。每完成一個 task 做 checkpoint commit，
    更新 progress.txt。設有 iteration 上限。

.PARAMETER PrdFile
    PRD 檔案路徑（Markdown 或 JSON）。

.PARAMETER MaxIterations
    最大迭代次數（覆蓋 config 設定）。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PrdFile,

    [int]$MaxIterations = 0  # 0 = 使用 config 的值
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 定位 repo 根目錄
$REPO_ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $REPO_ROOT) { $REPO_ROOT = Split-Path -Parent $PSScriptRoot }
Set-Location $REPO_ROOT

# 讀取 config
$CONFIG_FILE = Join-Path $REPO_ROOT "compound.config.json"
$config = @{ maxIterations = 5; outputDir = "./scripts/compound" }
if (Test-Path $CONFIG_FILE) {
    $config = Get-Content $CONFIG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($MaxIterations -eq 0) {
    $MaxIterations = if ($config.maxIterations) { [int]$config.maxIterations } else { 5 }
}

$OUTPUT_DIR = Join-Path $REPO_ROOT ($config.outputDir -replace '^\.\/', '')
$LOG_DIR = Join-Path $REPO_ROOT "logs"
$LOG_FILE = Join-Path $LOG_DIR ("auto-compound-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))
$PROGRESS_FILE = Join-Path $OUTPUT_DIR "progress.txt"
$PROMPT_TEMPLATE_FILE = Join-Path $PSScriptRoot "prompt.md"

# 確保目錄存在
foreach ($dir in @($LOG_DIR, $OUTPUT_DIR)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] [loop] $Message"
    Write-Host $logLine
    Add-Content -Path $LOG_FILE -Value $logLine -Encoding UTF8
}

# ==================== 
# 初始化 progress.txt
# ====================
if (-not (Test-Path $PROGRESS_FILE)) {
    @"
# Compound System Progress Log

## Codebase Patterns
<!-- 跨迭代共享的 reusable patterns，由 agent 自動更新 -->

---

Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@ | Out-File -FilePath $PROGRESS_FILE -Encoding UTF8
    Write-Log "初始化 progress.txt"
}

# 讀取 progress.txt 的 Codebase Patterns 段落
function Get-CodebasePatterns {
    if (-not (Test-Path $PROGRESS_FILE)) { return "(尚無)" }
    $content = Get-Content $PROGRESS_FILE -Raw -Encoding UTF8
    if ($content -match '(?s)## Codebase Patterns\s*\n(.*?)(?=\n---|\n## )') {
        $patterns = $Matches[1].Trim()
        if ($patterns -and $patterns -notmatch '^<!--') { return $patterns }
    }
    return "(尚無)"
}

# 讀取 PRD
if (-not (Test-Path $PrdFile)) {
    Write-Log "PRD 檔案不存在: $PrdFile" "ERROR"
    exit 1
}

$prd = Get-Content $PrdFile -Raw -Encoding UTF8

# 載入 prompt 模板
$promptTemplate = ""
if (Test-Path $PROMPT_TEMPLATE_FILE) {
    $promptTemplate = Get-Content $PROMPT_TEMPLATE_FILE -Raw -Encoding UTF8
    Write-Log "已載入 prompt 模板: prompt.md"
} else {
    Write-Log "prompt.md 不存在，使用內建 prompt" "WARN"
    $promptTemplate = @"
你是 Antigravity Compound System 的自動實作助手。

## 目前狀態
- 迭代次數: {{ITERATION}} / {{MAX_ITERATIONS}}
- 已完成的任務: {{COMPLETED_TASKS}}

## PRD 內容
{{PRD_CONTENT}}

## 指示
1. 查看 PRD，找出下一個尚未完成的 task。
2. 如果所有 task 都已完成，回覆：ALL_TASKS_COMPLETE
3. 如果還有 task，請執行它，修改相關檔案。
4. 完成後回報：TASK_COMPLETED: <task 名稱>
   CHANGES: <簡述>
   LEARNINGS: <學到的 patterns>
5. 無法完成時回覆：TASK_BLOCKED: <task 名稱>
   REASON: <原因>
"@
}

Write-Log "===== Task Execution Loop 開始 ====="
Write-Log "PRD 檔案: $PrdFile"
Write-Log "最大迭代次數: $MaxIterations"

# 狀態追蹤
$stateFile = Join-Path $REPO_ROOT ".compound-state.json"
$state = @{
    started_at      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    prd_file        = $PrdFile
    iterations      = 0
    completed_tasks = @()
    status          = "running"
}

$iteration = 0
$loopComplete = $false

while ($iteration -lt $MaxIterations -and -not $loopComplete) {
    $iteration++
    Write-Log "--- Iteration $iteration / $MaxIterations ---"

    # 更新狀態
    $state.iterations = $iteration
    $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $stateFile -Encoding UTF8

    # 組合 prompt（從模板注入動態變數）
    $patterns = Get-CodebasePatterns
    $prompt = $promptTemplate `
        -replace '{{ITERATION}}', $iteration `
        -replace '{{MAX_ITERATIONS}}', $MaxIterations `
        -replace '{{COMPLETED_TASKS}}', ($state.completed_tasks -join ', ') `
        -replace '{{PROGRESS_PATTERNS}}', $patterns `
        -replace '{{PRD_CONTENT}}', $prd

    # 呼叫 Gemini CLI
    try {
        $promptFile = Join-Path $env:TEMP "compound-loop-prompt.txt"
        $stderrFile = Join-Path $env:TEMP "compound-loop-stderr.txt"
        $prompt | Out-File -FilePath $promptFile -Encoding UTF8

        $geminiOutput = Get-Content $promptFile | gemini 2>$stderrFile
        $geminiExitCode = $LASTEXITCODE
        $geminiResult = ($geminiOutput | Out-String).Trim()

        # 記錄 stderr
        if (Test-Path $stderrFile) {
            $stderrContent = (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)
            if ($stderrContent) {
                Write-Log "Gemini CLI stderr: $($stderrContent.Substring(0, [Math]::Min(500, $stderrContent.Length)))" "WARN"
            }
            Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue

        # 檢查 exit code
        if ($geminiExitCode -ne 0) {
            Write-Log "Gemini CLI 回傳非零結束碼: $geminiExitCode" "ERROR"
            $state.status = "error"
            $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $stateFile -Encoding UTF8
            exit 1
        }

        # 驗證輸出不包含錯誤訊息
        if ($geminiResult -match 'GaxiosError|status:\s*429|rateLimitExceeded|ECONNREFUSED|ETIMEDOUT') {
            Write-Log "Gemini CLI 輸出包含錯誤訊息，跳過此迭代" "ERROR"
            continue
        }

        if ([string]::IsNullOrWhiteSpace($geminiResult)) {
            Write-Log "Gemini CLI 回應為空，跳過此迭代" "WARN"
            continue
        }

        Write-Log "Gemini 回應長度: $($geminiResult.Length) 字元"
    }
    catch {
        Write-Log "Gemini CLI 呼叫失敗: $_" "ERROR"
        $state.status = "error"
        $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $stateFile -Encoding UTF8
        exit 1
    }

    # 解析結果
    if ($geminiResult -match "ALL_TASKS_COMPLETE") {
        Write-Log "所有任務已完成！"
        $loopComplete = $true
        $state.status = "completed"
    }
    elseif ($geminiResult -match "TASK_COMPLETED:\s*(.+)") {
        $taskName = $Matches[1].Trim()
        Write-Log "Task 完成: $taskName"
        $state.completed_tasks += $taskName

        # 提取 learnings
        $learnings = ""
        if ($geminiResult -match "LEARNINGS:\s*(.+)") {
            $learnings = $Matches[1].Trim()
        }

        # 更新 progress.txt
        $progressEntry = @"

## [$(Get-Date -Format "yyyy-MM-dd HH:mm")] - $taskName (Iteration $iteration)
- 狀態: 完成
$(if ($learnings) { "- **Learnings:** $learnings" } else { "" })
---
"@
        Add-Content -Path $PROGRESS_FILE -Value $progressEntry -Encoding UTF8
        Write-Log "已更新 progress.txt"

        # Checkpoint commit
        Write-Log "Checkpoint commit..."
        try {
            git add -A
            $commitMsg = "compound-auto: complete task '$taskName' (iteration $iteration)"
            git commit -m $commitMsg --allow-empty
            Write-Log "Checkpoint commit 完成"
        }
        catch {
            Write-Log "Checkpoint commit 失敗: $_" "WARN"
        }
    }
    elseif ($geminiResult -match "TASK_BLOCKED:\s*(.+)") {
        $blockedTask = $Matches[1].Trim()
        Write-Log "Task 受阻: $blockedTask" "WARN"
        $reason = ""
        if ($geminiResult -match "REASON:\s*(.+)") {
            $reason = $Matches[1].Trim()
            Write-Log "原因: $reason" "WARN"
        }

        # 記錄到 progress.txt
        $progressEntry = @"

## [$(Get-Date -Format "yyyy-MM-dd HH:mm")] - $blockedTask (Iteration $iteration)
- 狀態: 受阻
$(if ($reason) { "- 原因: $reason" } else { "" })
---
"@
        Add-Content -Path $PROGRESS_FILE -Value $progressEntry -Encoding UTF8
    }
    else {
        Write-Log "無法解析 Gemini 回應，記錄原始回應..." "WARN"
        $rawOutputFile = Join-Path $LOG_DIR ("gemini-raw-{0}-iter{1}.txt" -f (Get-Date -Format "yyyy-MM-dd"), $iteration)
        $geminiResult | Out-File -FilePath $rawOutputFile -Encoding UTF8
        Write-Log "原始回應已寫入: $rawOutputFile"
    }

    # 儲存狀態
    $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $stateFile -Encoding UTF8
}

if (-not $loopComplete) {
    Write-Log "達到迭代上限 ($MaxIterations)，部分完成。" "WARN"
    $state.status = "partial"
}

$state.ended_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
$state | ConvertTo-Json -Depth 5 | Out-File -FilePath $stateFile -Encoding UTF8

Write-Log "===== Task Execution Loop 結束 (狀態: $($state.status)) ====="

# 輸出最終狀態
Write-Output $state.status
