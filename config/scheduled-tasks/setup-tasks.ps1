<#
.SYNOPSIS
    一鍵註冊所有 Windows Task Scheduler 排程。

.DESCRIPTION
    建立兩個排程工作：
      - Antigravity-DailyCompoundReview（每日 22:30）
      - Antigravity-AutoCompound（每日 23:00）

    需要以管理員權限執行（或至少有建立排程的權限）。

.NOTES
    執行：pwsh -NoProfile -File config\scheduled-tasks\setup-tasks.ps1
    移除：pwsh -NoProfile -File config\scheduled-tasks\remove-tasks.ps1
#>

$ErrorActionPreference = "Stop"

# 定位 repo 根目錄
$REPO_ROOT = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $REPO_ROOT) { $REPO_ROOT = "d:\chengen\Antigravity-compound-system" }

Write-Host "======================================"
Write-Host "Antigravity Compound System — 排程設定"
Write-Host "======================================"
Write-Host "Repo 根目錄: $REPO_ROOT"
Write-Host ""

# 找到 pwsh 的完整路徑
$pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshPath) {
    $pwshPath = (Get-Command powershell -ErrorAction SilentlyContinue).Source
}
if (-not $pwshPath) {
    Write-Error "找不到 PowerShell 執行檔"
    exit 1
}
Write-Host "PowerShell 路徑: $pwshPath"

# ============================================
# 排程 1: Daily Compound Review（22:30）
# ============================================
$taskName1 = "Antigravity-DailyCompoundReview"
$script1 = Join-Path $REPO_ROOT "scripts\daily-compound-review.ps1"

Write-Host ""
Write-Host "建立排程: $taskName1（每日 22:30）"

# 先嘗試刪除舊的（如果存在）
schtasks /delete /tn $taskName1 /f 2>$null

$action1 = New-ScheduledTaskAction `
    -Execute $pwshPath `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script1`"" `
    -WorkingDirectory $REPO_ROOT

$trigger1 = New-ScheduledTaskTrigger -Daily -At "22:30"

$settings1 = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -WakeToRun `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 25)

Register-ScheduledTask `
    -TaskName $taskName1 `
    -Action $action1 `
    -Trigger $trigger1 `
    -Settings $settings1 `
    -Description "Antigravity Compound System - 每日學習回顧（22:30）" `
    -Force

Write-Host "  ✅ $taskName1 已建立"

# ============================================
# 排程 2: Auto Compound（23:00）
# ============================================
$taskName2 = "Antigravity-AutoCompound"
$script2 = Join-Path $REPO_ROOT "scripts\compound\auto-compound.ps1"

Write-Host ""
Write-Host "建立排程: $taskName2（每日 23:00）"

schtasks /delete /tn $taskName2 /f 2>$null

$action2 = New-ScheduledTaskAction `
    -Execute $pwshPath `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script2`"" `
    -WorkingDirectory $REPO_ROOT

$trigger2 = New-ScheduledTaskTrigger -Daily -At "23:00"

$settings2 = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -WakeToRun `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask `
    -TaskName $taskName2 `
    -Action $action2 `
    -Trigger $trigger2 `
    -Settings $settings2 `
    -Description "Antigravity Compound System - 每日自動實作（23:00）" `
    -Force

Write-Host "  ✅ $taskName2 已建立"

# ============================================
# 電源設定提醒
# ============================================
Write-Host ""
Write-Host "======================================"
Write-Host "排程設定完成！"
Write-Host "======================================"
Write-Host ""
Write-Host "📋 已建立的排程工作："
Write-Host "  1. $taskName1 — 每日 22:30"
Write-Host "  2. $taskName2 — 每日 23:00"
Write-Host ""
Write-Host "⚡ 電源建議（避免排程時系統休眠）："
Write-Host "  已勾選「喚醒電腦以執行此工作」，但建議額外執行："
Write-Host "  powercfg /change standby-timeout-ac 0"
Write-Host ""
Write-Host "🔧 手動觸發測試："
Write-Host "  schtasks /run /tn `"$taskName1`""
Write-Host "  schtasks /run /tn `"$taskName2`""
Write-Host ""
Write-Host "📜 查看排程狀態："
Write-Host "  schtasks /query /tn `"$taskName1`" /v"
Write-Host "  schtasks /query /tn `"$taskName2`" /v"
