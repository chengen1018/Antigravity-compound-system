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

這是一個非常好的問題！

## `## Known Pitfalls` 是什麼？

這個區段就像是給 AI Agent 的**「路標警示牌」**或**「前車之鑑」**。

當未來的 `auto-compound` 腳本執行任務時，Gemini 會讀取這份 `AGENTS.md`。當它讀到 `Known Pitfalls` 時，它會知道：

> ⚠️ **「注意！這裡有坑，之前的任務在這裡失敗過，我必須避開。」**

## 為什麼會有這個區段？

它的存在是為了**打破「不斷踩同一個坑」的循環**。

如果沒有這個區段，AI 可能會發生以下情況：
1. 今天寫了一個 PowerShell 腳本，結果因為編碼問題（UTF-8 without BOM）導致中文亂碼。
2. 你修好了它，並在 `Recent Learnings` 記了一筆。
3. **兩週後**，這條 learning 過期被刪除了。
4. AI **忘記了這個教訓**，又寫出了一個會亂碼的腳本。💥

`Known Pitfalls` 就是用來存放那些**長期存在、必須時刻警惕的高風險問題**。

## 為什麼現在裡面已經有兩條內容？

```markdown
- PowerShell 預設編碼非 UTF-8，腳本開頭必須設定 `$OutputEncoding`。
- Windows Task Scheduler 的 PATH 與互動式 shell 不同，腳本內需明確指定工具路徑。
```

這是我在剛剛「重置」`AGENTS.md` 時，**特意幫你保留下來的「開局大禮包」**。🎁

因為我們剛剛在設定環境時，這兩個問題（PowerShell 編碼、找不到 `gh`/`pwsh`）導致了多次失敗。這兩個是 **Windows 環境下的「絕對地雷」**，如果不寫在這裡，Gemini 下次寫腳本時**有 99% 的機率會再犯錯**。

所以我把它們預先寫入，確保你的系統從第一天開始就是聰明的，不會再因為編碼或路徑問題而崩潰。

---

### 簡單總結

- **Stable Rules** = **該做什麼**（Best Practices）
- **Known Pitfalls** = **不該做什麼**（Anti-Patterns / 地雷）

這兩者共同構成了 Antigravity 系統的長期記憶。


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
