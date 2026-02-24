# Priority Report 2026-02-23

## Priority Items

### 1. [HIGH] 建立 analyze-report.ps1 解析邏輯
- **描述**: 實作報告解析腳本，能從 priority report 中提取第一優先任務的標題、描述、範圍和驗收標準，輸出為 JSON 格式。
- **範圍**: scripts/compound/analyze-report.ps1
- **驗收標準**: 執行 `analyze-report.ps1` 後輸出有效 JSON，包含 title、description、scope、acceptance_criteria 欄位。

### 2. [MEDIUM] 補充 failure-playbook.md 故障排除文件
- **描述**: 建立常見故障排除手冊，涵蓋 git 衝突、Gemini CLI 超時、Task Scheduler 失敗等場景。
- **範圍**: docs/failure-playbook.md
- **驗收標準**: 文件包含至少 5 個常見故障場景及其解決步驟。

### 3. [LOW] 增加 log rotation 功能
- **描述**: 在腳本中加入自動清理超過 14 天的 log 檔案功能。
- **範圍**: scripts/daily-compound-review.ps1, scripts/compound/auto-compound.ps1
- **驗收標準**: logs/ 目錄中超過 14 天的 .log 檔案被自動刪除。
