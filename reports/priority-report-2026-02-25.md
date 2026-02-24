# Priority Report 2026-02-25

## Priority Items

### 1. [HIGH] 補充 failure-playbook.md 故障排除文件
- **描述**: 建立常見故障排除手冊，涵蓋 Gemini CLI 429 rate limit、Task Scheduler 執行失敗、git 衝突、encoding 問題等場景。包含每個場景的症狀、診斷步驟、解決方式。
- **範圍**: docs/failure-playbook.md
- **驗收標準**: 文件包含至少 5 個常見故障場景及其解決步驟。

### 2. [MEDIUM] 新增 daily-note 範例模板
- **描述**: 在 reports/daily-notes/ 中建立一份範例模板，說明 daily note 的撰寫格式和最佳實踐，幫助使用者快速上手。
- **範圍**: reports/daily-notes/TEMPLATE.md
- **驗收標準**: 模板包含完整的區段結構（今日重點、遇到的問題、學到的經驗、值得記住的事）。

### 3. [LOW] 增加 Gemini CLI 重試機制
- **描述**: 當 Gemini CLI 遇到 429 rate limit 時，自動等待後重試（最多 3 次），而非直接退出。
- **範圍**: scripts/daily-compound-review.ps1, scripts/compound/loop.ps1
- **驗收標準**: 遇到 429 時腳本自動等待 30 秒後重試，log 中記錄重試次數。
