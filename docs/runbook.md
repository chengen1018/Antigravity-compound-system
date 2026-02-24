# Antigravity Compound System — Runbook（操作手冊）

## 目錄

1. [系統概覽](#系統概覽)
2. [首次設定](#首次設定)
3. [日常操作](#日常操作)
4. [手動執行](#手動執行)
5. [查看日誌](#查看日誌)
6. [故障排除](#故障排除)

---

## 系統概覽

每晚自動執行兩階段流程：

| 時間 | 排程 | 腳本 | 作用 |
|---|---|---|---|
| 22:30 | Antigravity-DailyCompoundReview | `scripts/daily-compound-review.ps1` | 從 daily-notes 萃取 learnings → 更新 AGENTS.md |
| 23:00 | Antigravity-AutoCompound | `scripts/compound/auto-compound.ps1` | 讀取報告 → 產生 PRD → 執行 → 開 Draft PR |

---

## 首次設定

### 前置需求

```powershell
# 1. PowerShell 7+
winget install Microsoft.Powershell

# 2. Git
winget install Git.Git

# 3. GitHub CLI
winget install GitHub.cli
gh auth login

# 4. Gemini CLI（依官方安裝指引）
# https://github.com/google-gemini/gemini-cli

# 5. 設定 PowerShell 執行策略
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 環境設定

```powershell
# 複製環境變數範本
Copy-Item config\compound.env.example .env.local

# 編輯 .env.local，填入實際值
notepad .env.local
```

### 註冊排程

```powershell
# 以管理員權限執行
pwsh -NoProfile -File config\scheduled-tasks\setup-tasks.ps1
```

### 電源設定（避免排程時休眠）

```powershell
# 插電時不自動睡眠
powercfg /change standby-timeout-ac 0
```

### 避開 Windows 自動更新

在 Windows 設定中設定「使用時間」(Active Hours) 為 22:00–02:00，避免更新重啟打斷夜間流程。

---

## 日常操作

### 每日必做

1. **寫 daily notes**（如果有值得記錄的互動）：
   - 在 `reports/daily-notes/` 建立 `YYYY-MM-DD.md`
   - 格式說明見 `reports/daily-notes/README.md`

2. **放入優先級報告**（如果有新任務）：
   - 在 `reports/` 建立 `priority-report-YYYY-MM-DD.md`
   - 格式說明見 `reports/README.md`

### 每週檢查

- [ ] 檢查 `logs/` 目錄大小
- [ ] 檢查 AGENTS.md 是否無序膨脹
- [ ] 確認本週 Draft PR 品質
- [ ] 更新優先級報告

---

## 手動執行

```powershell
# 手動跑 daily review
pwsh -NoProfile -File scripts\daily-compound-review.ps1

# 手動跑 auto-compound
pwsh -NoProfile -File scripts\compound\auto-compound.ps1

# 只跑報告解析
pwsh -NoProfile -File scripts\compound\analyze-report.ps1

# 透過 Task Scheduler 手動觸發
schtasks /run /tn "Antigravity-DailyCompoundReview"
schtasks /run /tn "Antigravity-AutoCompound"
```

---

## 查看日誌

```powershell
# 查看今日 review log
Get-Content logs\compound-review-$(Get-Date -Format 'yyyy-MM-dd').log

# 查看今日 auto-compound log
Get-Content logs\auto-compound-$(Get-Date -Format 'yyyy-MM-dd').log

# 即時追蹤 log（類似 tail -f）
Get-Content logs\auto-compound-$(Get-Date -Format 'yyyy-MM-dd').log -Wait

# 查看排程狀態
schtasks /query /tn "Antigravity-DailyCompoundReview" /v
schtasks /query /tn "Antigravity-AutoCompound" /v

# 查看 compound 狀態檔
Get-Content .compound-state.json | ConvertFrom-Json
```

---

## 故障排除

### 問題：排程沒有執行

```powershell
# 確認排程存在
schtasks /query /tn "Antigravity-DailyCompoundReview"

# 確認上次執行結果
Get-ScheduledTaskInfo -TaskName "Antigravity-DailyCompoundReview"

# 常見原因：
# - 電腦處於休眠 → 確認「喚醒電腦以執行」已勾選
# - 使用者未登入 → 改為「不論使用者是否登入都執行」
# - PowerShell 執行策略 → 確認 setup-tasks.ps1 使用了 -ExecutionPolicy Bypass
```

### 問題：Gemini CLI 呼叫失敗

```powershell
# 確認 gemini 可用
gemini --version

# 確認 API key
echo $env:GEMINI_API_KEY

# 查看原始回應
Get-ChildItem logs\gemini-raw-*.txt | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

### 問題：git push 失敗

```powershell
# 確認遠端設定
git remote -v

# 確認認證
gh auth status

# 手動推送
git push origin main
```

### 問題：AGENTS.md 衝突

```powershell
# 手動解決衝突
git checkout main
git pull origin main
# 手動編輯 AGENTS.md
git add AGENTS.md
git commit -m "resolve AGENTS.md conflict"
git push origin main
```

### 移除所有排程

```powershell
pwsh -NoProfile -File config\scheduled-tasks\remove-tasks.ps1
```
