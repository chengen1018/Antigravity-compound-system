<#
.SYNOPSIS
    每日學習回顧 — 掃描 daily-notes，萃取 learnings，更新 AGENTS.md。

.DESCRIPTION
    此腳本在每日 22:30 由 Task Scheduler 自動執行，或可手動執行。
    流程：
      1. git pull main
      2. 掃描 reports/daily-notes/ 中最近 24h 的筆記
      3. 呼叫 Gemini CLI 萃取 learnings
      4. 更新 AGENTS.md
      5. commit + push

.NOTES
    手動執行：pwsh -NoProfile -File scripts\daily-compound-review.ps1
    手動觸發排程：schtasks /run /tn "Antigravity-DailyCompoundReview"
#>

# ====================
# 環境設定
# ====================
$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 定位 repo 根目錄（腳本位於 scripts/ 下）
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
$DAILY_NOTES_DIR = Join-Path $REPO_ROOT "reports\daily-notes"
$AGENTS_FILE = Join-Path $REPO_ROOT "AGENTS.md"
$LOG_DIR = Join-Path $REPO_ROOT "logs"
$LOG_FILE = Join-Path $LOG_DIR ("compound-review-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))
$LOG_RETENTION_DAYS = if ($env:LOG_RETENTION_DAYS) { [int]$env:LOG_RETENTION_DAYS } else { 14 }

# 確保 log 目錄存在
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

# ====================
# 日誌函式
# ====================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    Write-Host $logLine
    Add-Content -Path $LOG_FILE -Value $logLine -Encoding UTF8
}

# ====================
# Log Rotation（清理舊 log）
# ====================
function Invoke-LogRotation {
    $cutoff = (Get-Date).AddDays(-$LOG_RETENTION_DAYS)
    Get-ChildItem -Path $LOG_DIR -Filter "compound-review-*.log" | Where-Object {
        $_.LastWriteTime -lt $cutoff
    } | ForEach-Object {
        Write-Log "刪除過期 log: $($_.Name)"
        Remove-Item $_.FullName -Force
    }
}

# ====================
# 主流程
# ====================
function Main {
    Write-Log "===== Daily Compound Review 開始 ====="

    # Step 0: Log rotation
    Invoke-LogRotation

    # Step 1: git pull
    Write-Log "Step 1: git pull origin main"
    try {
        $gitOutput = git pull origin main 2>&1
        Write-Log "git pull 完成: $gitOutput"
    }
    catch {
        Write-Log "git pull 失敗: $_" "ERROR"
        exit 1
    }

    # Step 2: 掃描最近 24h 的 daily notes
    Write-Log "Step 2: 掃描 daily-notes（最近 24h）"
    if (-not (Test-Path $DAILY_NOTES_DIR)) {
        Write-Log "daily-notes 目錄不存在，建立中..."
        New-Item -ItemType Directory -Path $DAILY_NOTES_DIR -Force | Out-Null
    }

    $cutoffTime = (Get-Date).AddHours(-24)
    $recentNotes = Get-ChildItem -Path $DAILY_NOTES_DIR -Filter "*.md" | Where-Object {
        $_.Name -ne "README.md" -and $_.LastWriteTime -gt $cutoffTime
    } | Sort-Object Name -Descending

    if ($recentNotes.Count -eq 0) {
        Write-Log "沒有最近 24h 的 daily notes，跳過本次 review。"
        Write-Log "===== Daily Compound Review 完成（無更新）====="
        exit 0
    }

    Write-Log "找到 $($recentNotes.Count) 個 daily note(s): $($recentNotes.Name -join ', ')"

    # Step 3: 讀取所有 notes 內容
    $notesContent = ""
    foreach ($note in $recentNotes) {
        $content = Get-Content $note.FullName -Raw -Encoding UTF8
        $notesContent += "`n`n--- FILE: $($note.Name) ---`n$content"
    }

    # Step 4: 讀取目前的 AGENTS.md
    $currentAgents = ""
    if (Test-Path $AGENTS_FILE) {
        $currentAgents = Get-Content $AGENTS_FILE -Raw -Encoding UTF8
    }

    # Step 5: 呼叫 Gemini CLI 萃取 learnings
    Write-Log "Step 3: 呼叫 Gemini CLI 萃取 learnings"

    $prompt = @"
你是 Antigravity Compound System 的學習萃取助手。

## 任務
請從以下「今日筆記」中萃取有價值的 learnings，並以指定格式輸出。

## 今日筆記
$notesContent

## 目前的 AGENTS.md 內容
$currentAgents

## 輸出規則
1. 只輸出需要**新增**到 AGENTS.md 的內容（不要重複已有的）。
2. 如果筆記中沒有新的 learning，請只輸出：NO_NEW_LEARNINGS
3. 每條 learning 使用以下格式：

- **[$(Get-Date -Format 'yyyy-MM-dd')]** [問題類型: build/test/review/ops]
  - 來源: <daily-notes 檔名>
  - 問題: <簡述>
  - 修正策略: <可執行的步驟>

4. 如果有內容適合升級到 Stable Rules 或 Known Pitfalls，請額外說明。
5. 只輸出 learning 條目，不要輸出其他解釋文字。
"@

    try {
        # 將 prompt 寫入暫存檔，避免命令列長度限制
        $promptFile = Join-Path $env:TEMP "compound-review-prompt.txt"
        $prompt | Out-File -FilePath $promptFile -Encoding UTF8

        # 呼叫 Gemini CLI（非互動模式）
        $geminiOutput = Get-Content $promptFile | gemini 2>&1
        $geminiResult = $geminiOutput -join "`n"

        Remove-Item $promptFile -Force -ErrorAction SilentlyContinue

        Write-Log "Gemini CLI 回應長度: $($geminiResult.Length) 字元"
    }
    catch {
        Write-Log "Gemini CLI 呼叫失敗: $_" "ERROR"
        Write-Log "原始錯誤: $($_.Exception.Message)" "ERROR"
        exit 1
    }

    # Step 6: 檢查是否有新 learnings
    if ($geminiResult -match "NO_NEW_LEARNINGS") {
        Write-Log "Gemini 判定無新 learnings，跳過更新。"
        Write-Log "===== Daily Compound Review 完成（無更新）====="
        exit 0
    }

    # Step 7: 更新 AGENTS.md
    Write-Log "Step 4: 更新 AGENTS.md"
    try {
        # 在 "## Recent Learnings" 區段後面插入新 learnings
        $marker = "## Recent Learnings (Last 14 days)"
        if ($currentAgents -match [regex]::Escape($marker)) {
            $insertPoint = $currentAgents.IndexOf($marker) + $marker.Length
            # 找到 marker 後第一個換行之後的位置
            $nextNewline = $currentAgents.IndexOf("`n", $insertPoint)
            if ($nextNewline -ge 0) {
                # 跳過緊接的註解行（<!-- ... -->）
                $insertContent = $currentAgents.Substring($nextNewline)
                $commentEnd = $insertContent.IndexOf("-->")
                if ($commentEnd -ge 0) {
                    $actualInsertPoint = $nextNewline + $commentEnd + 3
                    # 在註解結束後插入新 learnings
                    $newContent = $currentAgents.Substring(0, $actualInsertPoint) + "`n`n" + $geminiResult.Trim() + "`n" + $currentAgents.Substring($actualInsertPoint)
                }
                else {
                    $newContent = $currentAgents.Substring(0, $nextNewline) + "`n`n" + $geminiResult.Trim() + "`n" + $currentAgents.Substring($nextNewline)
                }
            }
            else {
                $newContent = $currentAgents + "`n`n" + $geminiResult.Trim() + "`n"
            }
        }
        else {
            # 如果找不到 marker，直接附加到末尾
            $newContent = $currentAgents + "`n`n## Recent Learnings (Last 14 days)`n`n" + $geminiResult.Trim() + "`n"
        }

        $newContent | Out-File -FilePath $AGENTS_FILE -Encoding UTF8 -NoNewline
        Write-Log "AGENTS.md 已更新"
    }
    catch {
        Write-Log "更新 AGENTS.md 失敗: $_" "ERROR"
        exit 1
    }

    # Step 8: commit + push
    Write-Log "Step 5: git commit + push"
    try {
        git add $AGENTS_FILE
        $commitMsg = "compound-review: update learnings from $(Get-Date -Format 'yyyy-MM-dd')"
        git commit -m $commitMsg
        Write-Log "commit 完成: $commitMsg"

        $pushOutput = git push origin main 2>&1
        Write-Log "push 完成: $pushOutput"
    }
    catch {
        Write-Log "git commit/push 失敗: $_" "ERROR"
        Write-Log "Recovery: commit 已保留在本地，請手動執行 'git push origin main'" "WARN"
        exit 1
    }

    Write-Log "===== Daily Compound Review 完成 ====="
}

# 執行主流程
Main
