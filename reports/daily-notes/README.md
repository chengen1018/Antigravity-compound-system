# Daily Notes 格式說明

每天將你與 Antigravity 的重要對話要點手動記錄在此目錄。
`daily-compound-review.ps1` 會掃描此目錄中最近 24 小時的筆記，
讓 Gemini CLI 從中萃取 learnings 寫入 AGENTS.md。

## 檔名格式

```
YYYY-MM-DD.md
```

## 建議內容（自由格式，但建議包含以下資訊）

```markdown
# 2026-02-23 Daily Notes

## 今日重點對話

### 對話 1: <主題>
- 做了什麼：...
- 遇到的問題：...
- 解決方式：...
- 學到的經驗：...

### 對話 2: <主題>
- ...

## 值得記住的事
- ...
```

## 注意事項

- 不需要每個對話都記錄，只記錄有 learning value 的
- 如果某天沒有值得記錄的，可以不建立檔案（腳本會跳過）
- 敏感資訊（API key 等）不要寫入
