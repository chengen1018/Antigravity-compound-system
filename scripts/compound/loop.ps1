<#
.SYNOPSIS
    任務執行迴圈 — 逐一執行 tasks，每完成一個做 checkpoint commit。

.DESCRIPTION
    接收 PRD JSON，迭代執行任務。
    每完成一個 task 做 checkpoint commit，避免超時後遺失進度。
    設有 iteration 上限，超過時退出並回報部分完成。

.PARAMETER PrdFile
    PRD JSON 檔案路徑。

.PARAMETER MaxIterations
    最大迭代次數（預設 5）。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PrdFile,

    [int]$MaxIterations = 5
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 定位 repo 根目錄
$REPO_ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $REPO_ROOT) { $REPO_ROOT = Split-Path -Parent $PSScriptRoot }
Set-Location $REPO_ROOT

$LOG_DIR = Join-Path $REPO_ROOT "logs"
$LOG_FILE = Join-Path $LOG_DIR ("auto-compound-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] [loop] $Message"
    Write-Host $logLine
    Add-Content -Path $LOG_FILE -Value $logLine -Encoding UTF8
}

# 讀取 PRD
if (-not (Test-Path $PrdFile)) {
    Write-Log "PRD 檔案不存在: $PrdFile" "ERROR"
    exit 1
}

$prd = Get-Content $PrdFile -Raw -Encoding UTF8

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

    # 呼叫 Gemini CLI 執行下一個任務
    $prompt = @"
你是 Antigravity Compound System 的自動實作助手。

## 目前狀態
- 迭代次數: $iteration / $MaxIterations
- 已完成的任務: $($state.completed_tasks -join ', ')

## PRD 內容
$prd

## 指示
1. 查看 PRD，找出下一個尚未完成的 task。
2. 如果所有 task 都已完成，回覆：ALL_TASKS_COMPLETE
3. 如果還有 task，請執行它，修改相關檔案。
4. 完成後，用以下格式回報：
   TASK_COMPLETED: <task 名稱>
   CHANGES: <簡述變更內容>
5. 如果 task 無法完成，回覆：
   TASK_BLOCKED: <task 名稱>
   REASON: <原因>
"@

    try {
        $promptFile = Join-Path $env:TEMP "compound-loop-prompt.txt"
        $prompt | Out-File -FilePath $promptFile -Encoding UTF8

        $geminiOutput = Get-Content $promptFile | gemini 2>&1
        $geminiResult = $geminiOutput -join "`n"

        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue

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
        if ($geminiResult -match "REASON:\s*(.+)") {
            Write-Log "原因: $($Matches[1].Trim())" "WARN"
        }
        # 繼續嘗試下一個 task
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
