# AGENTS.md — Antigravity Compound System Memory

> 此檔案由 daily-compound-review 自動維護，也可手動編輯。
> 結構化規範請見 docs/runbook.md。

## Stable Rules

<!-- 長期有效規則，經多次驗證後從 Recent Learnings 升級至此 -->

- 所有自動化 PR 一律以 Draft 開啟，經人工審核後才可合併。
- 每次 commit 前必須確認 repo 處於乾淨狀態（無未追蹤的重要檔案）。

## Recent Learnings (Last 14 days)

<!-- 格式：
- **[YYYY-MM-DD]** [問題類型: build/test/review/ops]
  - 來源: <thread-id 或 daily-notes 檔名>
  - 問題: <簡述>
  - 修正策略: <可執行的步驟>
-->

- **[2026-02-24]** [ops]
  - 來源: 2026-02-24.md
  - 問題: PowerShell 5.1 不支援無 BOM 的 UTF-8 編碼，導致腳本中的中文字元出現亂碼。
  - 修正策略: 強制開發與執行環境使用 PowerShell 7 (pwsh)，或確保所有 .ps1 檔案儲存為 UTF-8 with BOM 編碼。

- **[2026-02-24]** [ops]
  - 來源: 2026-02-24.md
  - 問題: 需要在自動化任務執行時確保電腦處於喚醒狀態。
  - 修正策略: 在 Windows 工作排程器 (Task Scheduler) 的「條件」分頁中，勾選「喚醒電腦以執行此工作」。

- **[2026-02-24]** [ops]
  - 來源: 2026-02-24.md
  - 問題: Antigravity 對話紀錄 (.pb) 解析困難。
  - 修正策略: 優先從 `brain/<conv-id>/*.metadata.json` 讀取可讀的 metadata 摘要作為自動化分析的輔助來源。

## Known Pitfalls

<!-- 高頻錯誤與避免策略 -->

- PowerShell 預設編碼非 UTF-8，腳本開頭必須設定 `$OutputEncoding`。
- Windows Task Scheduler 的 PATH 與互動式 shell 不同，腳本內需明確指定工具路徑。
- Gemini CLI 在高峰時段可能遇到 429 rate limit，需要在腳本中妥善處理錯誤輸出。

## Verification Checklist

<!-- 每次自動交付前必做檢查 -->

- [ ] 所有修改的檔案都已 `git add`
- [ ] commit message 清楚描述變更內容
- [ ] 無敏感資訊（API key、token）出現在 commit 中
- [ ] branch 名稱符合 `compound/YYYY-MM-DD-<slug>` 格式
