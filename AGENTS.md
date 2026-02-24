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

這是一個非常好的問題。

## 為什麼會有 `Known Pitfalls`（已知陷阱）？

這個區段的目的是 **「防呆」與「節省時間」**。

當未來的 AI Agent（在 23:00 自動執行任務時）讀到這個檔案，它會知道：
> 「喔！前人已經踩過這些坑了，我不要再浪費時間去試錯，直接避開。」

這跟 `Stable Rules` 不一樣：
- **Stable Rules** 是「你要這樣做」（Do this）。
- **Known Pitfalls** 是「千萬別這樣做，因為會爆」（Don't do this, it will fail）。

## 為什麼你的檔案裡預設有這兩點？

雖然我幫你「重置」了 `AGENTS.md`，但我刻意保留了這兩條 **Windows 環境的血淚教訓**，因為它們是這個系統能運作的基石。如果刪掉，未來的 Agent 很可能會再次寫出壞掉的程式碼：

1.  **`PowerShell 預設編碼非 UTF-8`**
    *   **如果不寫這條**：Agent 可能會寫出一個腳本，結果你隔天打開 log 發現全是亂碼（@#%&），因為 PowerShell 5.1 預設不是 UTF-8。
    *   **有了這條**：Agent 寫腳本時就會乖乖加上 `$OutputEncoding = [System.Text.Encoding]::UTF8`。

2.  **`Windows Task Scheduler 的 PATH 與互動式 shell 不同`**
    *   **如果不寫這條**：Agent 寫的腳本在你手動執行時（互動式）是好的，但晚上自動跑（Task Scheduler）時卻報錯 `git command not found`。
    *   **有了這條**：Agent 就會知道要寫絕對路徑（例如用 `C:\Program Files\Git\bin\git.exe`）或先設定 PATH。

### 總結

這兩點是我們在建置過程中「學到」的最重要架構限制。把它們留在初始狀態，是為了確保你的自動化系統 **第一天晚上就能穩定運作**，不會因為這些基礎環境問題而失敗。


## Known Pitfalls

<!-- 高頻錯誤與避免策略 -->

- PowerShell 預設編碼非 UTF-8，腳本開頭必須設定 `$OutputEncoding`。
- Windows Task Scheduler 的 PATH 與互動式 shell 不同，腳本內需明確指定工具路徑。

## Verification Checklist

<!-- 每次自動交付前必做檢查 -->

- [ ] 所有修改的檔案都已 `git add`
- [ ] commit message 清楚描述變更內容
- [ ] 無敏感資訊（API key、token）出現在 commit 中
- [ ] branch 名稱符合 `compound/YYYY-MM-DD-<slug>` 格式
