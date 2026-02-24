<#
.SYNOPSIS
    一鍵移除所有 Antigravity Compound System 的排程工作。

.NOTES
    執行：pwsh -NoProfile -File config\scheduled-tasks\remove-tasks.ps1
#>

$ErrorActionPreference = "SilentlyContinue"

$tasks = @(
    "Antigravity-DailyCompoundReview",
    "Antigravity-AutoCompound"
)

Write-Host "======================================"
Write-Host "Antigravity Compound System — 移除排程"
Write-Host "======================================"
Write-Host ""

foreach ($taskName in $tasks) {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "  ✅ 已移除: $taskName"
    }
    else {
        Write-Host "  ⏭️  不存在: $taskName（跳過）"
    }
}

Write-Host ""
Write-Host "排程已全部移除。"
