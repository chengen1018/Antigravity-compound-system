<#
.SYNOPSIS
    每日自動實作 — 從優先級報告中選出任務，自動產生 PRD、執行、開 Draft PR。

.DESCRIPTION
    此腳本在每日 23:00 由 Task Scheduler 自動執行，或可手動執行。
    流程：
      1. git fetch + reset to origin/main
      2. 解析最新報告選 #1 priority
      3. 建立 feature branch
      4. Gemini CLI 產生 PRD + 拆 tasks
      5. 呼叫 loop.ps1 執行任務
      6. push + gh pr create --draft

.NOTES
    手動執行：pwsh -NoProfile -File scripts\compound\auto-compound.ps1
    手動觸發排程：schtasks /run /tn "Antigravity-AutoCompound"
#>

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 定位 repo 根目錄
$REPO_ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $REPO_ROOT) { $REPO_ROOT = Split-Path -Parent $PSScriptRoot }
Set-Location $REPO_ROOT

# 載入環境變數
$envFile = Join-Path $REPO_ROOT ".env.local"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
        }
    }
}

# 設定
$LOG_DIR = Join-Path $REPO_ROOT "logs"
$LOG_FILE = Join-Path $LOG_DIR ("auto-compound-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))
$TASKS_DIR = Join-Path $REPO_ROOT "tasks"
$MAX_ITERATIONS = if ($env:MAX_LOOP_ITERATIONS) { [int]$env:MAX_LOOP_ITERATIONS } else { 5 }
$LOG_RETENTION_DAYS = if ($env:LOG_RETENTION_DAYS) { [int]$env:LOG_RETENTION_DAYS } else { 14 }

# 確保目錄存在
foreach ($dir in @($LOG_DIR, $TASKS_DIR)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# ====================
# 日誌函式
# ====================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] [auto-compound] $Message"
    Write-Host $logLine
    Add-Content -Path $LOG_FILE -Value $logLine -Encoding UTF8
}

# ====================
# Log Rotation
# ====================
function Invoke-LogRotation {
    $cutoff = (Get-Date).AddDays(-$LOG_RETENTION_DAYS)
    Get-ChildItem -Path $LOG_DIR -Filter "auto-compound-*.log" | Where-Object {
        $_.LastWriteTime -lt $cutoff
    } | ForEach-Object {
        Write-Log "刪除過期 log: $($_.Name)"
        Remove-Item $_.FullName -Force
    }
}

# ====================
# Preflight Checks
# ====================
function Test-Preflight {
    Write-Log "Preflight checks..."

    # 檢查 git
    try { git --version | Out-Null } catch {
        Write-Log "git 無法執行，請確認 PATH" "ERROR"; return $false
    }

    # 檢查 gemini
    try { gemini --version 2>&1 | Out-Null } catch {
        Write-Log "gemini CLI 無法執行，請確認已安裝並在 PATH 中" "ERROR"; return $false
    }

    # 檢查 gh（GitHub CLI）
    try { gh --version | Out-Null } catch {
        Write-Log "gh CLI 無法執行，Draft PR 功能將不可用" "WARN"
    }

    # 檢查是否已有未完成的 compound 分支
    $lockFile = Join-Path $REPO_ROOT ".compound-lock"
    if (Test-Path $lockFile) {
        $lockContent = Get-Content $lockFile -Raw
        Write-Log "偵測到 lock 檔（上次可能未正常結束）: $lockContent" "WARN"
        Remove-Item $lockFile -Force
    }

    return $true
}

# ====================
# 主流程
# ====================
function Main {
    Write-Log "===== Auto Compound 開始 ====="

    # Step 0: Preflight + Log rotation
    Invoke-LogRotation
    if (-not (Test-Preflight)) {
        Write-Log "Preflight 檢查失敗，退出。" "ERROR"
        exit 1
    }

    # 建立 lock 檔
    $lockFile = Join-Path $REPO_ROOT ".compound-lock"
    "started=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')" | Out-File $lockFile -Encoding UTF8

    try {
        # Step 1: 同步到最新 main
        Write-Log "Step 1: git fetch + reset to origin/main"
        git fetch origin 2>&1 | ForEach-Object { Write-Log "  $_" }
        git checkout main 2>&1 | ForEach-Object { Write-Log "  $_" }
        git reset --hard origin/main 2>&1 | ForEach-Object { Write-Log "  $_" }
        Write-Log "已同步到最新 origin/main"

        # Step 2: 解析報告
        Write-Log "Step 2: 解析優先級報告"
        $analyzeScript = Join-Path $PSScriptRoot "analyze-report.ps1"
        $taskJson = & $analyzeScript
        if (-not $taskJson) {
            Write-Log "無法解析報告或無可用任務" "ERROR"
            exit 1
        }
        $task = $taskJson | ConvertFrom-Json
        Write-Log "選出任務: [$($task.priority)] $($task.title)"
        Write-Log "  描述: $($task.description)"
        Write-Log "  範圍: $($task.scope)"

        # Step 3: 建立 feature branch
        $dateStr = Get-Date -Format "yyyy-MM-dd"
        $branchName = "compound/$dateStr-$($task.slug)"

        # 檢查分支是否已存在
        $existingBranch = git branch --list $branchName 2>&1
        if ($existingBranch) {
            $timestamp = Get-Date -Format "HHmm"
            $branchName = "$branchName-$timestamp"
            Write-Log "分支已存在，使用帶時間戳的名稱: $branchName" "WARN"
        }

        Write-Log "Step 3: 建立分支 $branchName"
        git checkout -b $branchName 2>&1 | ForEach-Object { Write-Log "  $_" }

        # Step 4: 產生 PRD
        Write-Log "Step 4: 呼叫 Gemini CLI 產生 PRD"
        $agentsContent = ""
        $agentsFile = Join-Path $REPO_ROOT "AGENTS.md"
        if (Test-Path $agentsFile) {
            $agentsContent = Get-Content $agentsFile -Raw -Encoding UTF8
        }

        $prdPrompt = @"
你是 Antigravity Compound System 的 PRD 產生助手。

## 任務資訊
- 標題: $($task.title)
- 描述: $($task.description)
- 範圍: $($task.scope)
- 驗收標準: $($task.acceptance_criteria)

## 專案知識（AGENTS.md）
$agentsContent

## 指示
請為此任務產生一份 PRD（Product Requirements Document），包含：
1. 目標與背景
2. 具體的技術任務清單（可機器執行的步驟）
3. 每個任務的完成條件
4. 驗收標準

使用 Markdown 格式輸出。每個任務用 `### Task N: 任務名稱` 的格式。
"@

        try {
            $promptFile = Join-Path $env:TEMP "compound-prd-prompt.txt"
            $prdPrompt | Out-File -FilePath $promptFile -Encoding UTF8

            $prdOutput = Get-Content $promptFile | gemini 2>&1
            $prdContent = $prdOutput -join "`n"

            Remove-Item $promptFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Gemini CLI PRD 產生失敗: $_" "ERROR"
            exit 1
        }

        # 儲存 PRD
        $prdFileName = "prd-$dateStr-$($task.slug).md"
        $prdFile = Join-Path $TASKS_DIR $prdFileName
        $prdContent | Out-File -FilePath $prdFile -Encoding UTF8
        Write-Log "PRD 已寫入: $prdFileName"

        # Commit PRD
        git add $prdFile
        git commit -m "compound-auto: add PRD for '$($task.title)'"

        # Step 5: 執行 loop
        Write-Log "Step 5: 執行任務迴圈（最多 $MAX_ITERATIONS 次迭代）"
        $loopScript = Join-Path $PSScriptRoot "loop.ps1"
        $loopResult = & $loopScript -PrdFile $prdFile -MaxIterations $MAX_ITERATIONS

        Write-Log "Loop 結束，狀態: $loopResult"

        # Step 6: Push + Draft PR
        Write-Log "Step 6: Push + 建立 Draft PR"
        try {
            git push origin $branchName 2>&1 | ForEach-Object { Write-Log "  $_" }
            Write-Log "Push 完成"
        }
        catch {
            Write-Log "Push 失敗: $_" "ERROR"
            exit 1
        }

        # 嘗試建立 Draft PR
        try {
            $prTitle = "[Compound] $($task.title)"
            $prBody = @"
## Auto-generated by Compound System

- **Priority**: $($task.priority)
- **Source Report**: $($task.report_file)
- **Loop Status**: $loopResult
- **Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm')

### Task Description
$($task.description)

### Acceptance Criteria
$($task.acceptance_criteria)
"@
            $prBodyFile = Join-Path $env:TEMP "compound-pr-body.txt"
            $prBody | Out-File -FilePath $prBodyFile -Encoding UTF8

            gh pr create --draft --title $prTitle --body-file $prBodyFile --base main 2>&1 | ForEach-Object { Write-Log "  $_" }
            Write-Log "Draft PR 已建立"

            Remove-Item $prBodyFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Draft PR 建立失敗（gh CLI 可能未設定）: $_" "WARN"
            Write-Log "請手動建立 PR: gh pr create --draft --title '$prTitle' --base main" "WARN"
        }

        Write-Log "===== Auto Compound 完成 (狀態: $loopResult) ====="
    }
    finally {
        # 清除 lock 檔
        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force
        }
    }
}

# 執行主流程
Main
