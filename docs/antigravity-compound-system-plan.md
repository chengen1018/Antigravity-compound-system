# Antigravity Compound System — Windows 完整實作計畫

> 目標：在 Google Antigravity 專案中建立「夜間自我學習 + 自動實作」雙迴圈，讓 Gemini CLI 代理每天自動吸收經驗、更新記憶，並持續交付下一個高優先任務。

---

## 1. 成果定義（Definition of Done）

1. 每日 **22:30** 自動執行 `daily-compound-review`：
   - 掃描過去 24 小時代理互動紀錄。
   - 將缺漏的 learnings 回寫到專案中的 `AGENTS.md`。
2. 每日 **23:00** 自動執行 `auto-compound`：
   - 讀取最新優先級報告。
   - 選出第一優先任務。
   - 產生 PRD → 拆解 tasks → 執行 → 開 Draft PR。
3. 產出完整可追蹤日誌（review + implementation + error）。
4. 任何失敗都能在下次排程前被觀測（log/通知）。
5. 至少連續 3 晚成功跑完兩段流程。

---

## 2. 系統架構（Two-Part Loop）

```text
[Windows Task Scheduler]
   ├─ 22:30 daily-compound-review
   │    ├─ git pull main
   │    ├─ parse last-24h threads（來源 TBD）
   │    ├─ Gemini CLI 萃取 learnings
   │    └─ update AGENTS.md + commit/push
   │
   └─ 23:00 auto-compound
        ├─ git pull main（含最新 learnings）
        ├─ pick #1 priority from report
        ├─ Gemini CLI 建立 PRD
        ├─ PRD → tasks
        ├─ task execution loop
        └─ push branch + open draft PR
```

### 核心原則

- **先學習再實作**：22:30 的學習必須先完成，23:00 才吃到最新記憶。
- **可恢復**：任一步驟失敗，隔天可從最新 repo state 重跑。
- **最小權限**：token、repo 寫入、PR 權限分離。

---

## 3. Windows 落地策略

### 部署組合

| 元件 | 工具 |
|---|---|
| **排程** | Windows Task Scheduler（兩個排程工作） |
| **腳本** | PowerShell 7+ (`.ps1`) |
| **Agent** | Gemini CLI（`gemini` 命令列工具） |
| **版本控制** | `git` + `gh`（GitHub CLI） |
| **憑證管理** | `gh auth login` 管理 GitHub token；`.env.local` 存放 API key（不進 repo） |
| **防休眠** | Task Scheduler「喚醒電腦以執行此工作」+ 電源設定 |
| **日誌** | `logs/` 按日期命名，腳本自動清理 14 天前的 |

### Windows 專屬設計重點

1. **防休眠**：不需要 `caffeinate`。Task Scheduler 每個工作勾選「**Wake the computer to run this task**」即可。另外建議在電源設定中設定夜間不自動休眠：
   ```powershell
   # 插電時不自動睡眠
   powercfg /change standby-timeout-ac 0
   ```

2. **執行策略**：PowerShell 預設阻擋 `.ps1` 執行，需設定：
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **編碼**：腳本開頭統一設定 UTF-8，避免 AGENTS.md commit 時出現亂碼：
   ```powershell
   $OutputEncoding = [System.Text.Encoding]::UTF8
   [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
   ```

4. **PATH**：Task Scheduler 執行環境的 PATH 可能不包含 `git`、`gemini`、`gh`，需在腳本開頭明確設定或在排程工作中設定完整路徑。

5. **執行帳戶**：排程工作選「**不論使用者是否登入都執行**」（Run whether user is logged on or not），確保登出後仍然運作。

6. **手動重跑**：
   ```powershell
   schtasks /run /tn "Antigravity-DailyCompoundReview"
   schtasks /run /tn "Antigravity-AutoCompound"
   ```

### 何時升級到雲端

- 需要多 repo 或多團隊共享。
- 需要更強的審計、告警、SLA。
- 本機夜跑成功率連續兩週低於 90%。

---

## 4. Repository 結構

```text
d:\chengen\Antigravity-compound-system\
│
├── scripts/
│   ├── daily-compound-review.ps1      # 每日學習回顧
│   └── compound/
│       ├── auto-compound.ps1          # 每日自動實作主流程
│       ├── analyze-report.ps1         # 解析優先級報告 → JSON
│       └── loop.ps1                   # 任務執行迴圈
│
├── config/
│   ├── compound.env.example           # 環境變數範本
│   └── scheduled-tasks/
│       ├── setup-tasks.ps1            # 一鍵註冊所有 Task Scheduler 排程
│       └── remove-tasks.ps1           # 一鍵移除所有排程
│
├── logs/                              # 日誌目錄（gitignore）
│   ├── compound-review-YYYY-MM-DD.log
│   └── auto-compound-YYYY-MM-DD.log
│
├── reports/                           # 優先級報告
│   └── *.md
│
├── tasks/                             # PRD 與任務定義
│   ├── prd-*.md
│   └── prd.json
│
├── docs/
│   ├── antigravity-compound-system-plan.md   # 本文件
│   ├── runbook.md                            # 操作手冊
│   └── failure-playbook.md                   # 故障排除手冊
│
├── AGENTS.md                          # Agent 記憶檔
├── .env.local                         # API keys（gitignore）
└── .gitignore
```

---

## 5. 關鍵腳本設計

### `scripts/daily-compound-review.ps1`

```
功能：
  1. git checkout main && git pull origin main
  2. 收集最近 24h thread metadata（來源 TBD）
  3. 判定哪些 thread 尚未 compound
  4. 呼叫 Gemini CLI 萃取 learnings 並更新 AGENTS.md
  5. git add AGENTS.md && git commit && git push

防呆：
  - 若無可更新 learnings → 不 commit，正常結束（exit 0）
  - 若 push 失敗 → 保留 commit，記錄 recovery 指令到 log
  - 若 Gemini CLI 回應異常 → 記錄原始回應到 log，不寫入 AGENTS.md
```

### `scripts/compound/auto-compound.ps1`

```
功能：
  1. git fetch && git reset --hard origin/main
  2. 呼叫 analyze-report.ps1 解析最新報告，選 #1 priority
  3. git checkout -b compound/YYYY-MM-DD-<task-slug>
  4. 呼叫 Gemini CLI 產生 PRD
  5. 呼叫 Gemini CLI 拆解 tasks
  6. 呼叫 loop.ps1 執行任務（設定 iteration 上限）
  7. git push + gh pr create --draft

防呆：
  - report 缺失 → 退出並告警（exit 1）
  - Gemini CLI 超時/失敗 → 記錄到 log，exit 1
  - loop 超過上限 → 產生「部分完成」PR，避免卡死
  - 分支已存在 → 加時間戳後綴
```

### `config/scheduled-tasks/setup-tasks.ps1`

```powershell
# 一鍵註冊排程（示意）
$repoRoot = "d:\chengen\Antigravity-compound-system"

# 22:30 Daily Compound Review
schtasks /create /tn "Antigravity-DailyCompoundReview" `
  /tr "pwsh.exe -NoProfile -File $repoRoot\scripts\daily-compound-review.ps1" `
  /sc daily /st 22:30 `
  /rl highest `
  /f

# 23:00 Auto Compound
schtasks /create /tn "Antigravity-AutoCompound" `
  /tr "pwsh.exe -NoProfile -File $repoRoot\scripts\compound\auto-compound.ps1" `
  /sc daily /st 23:00 `
  /rl highest `
  /f
```

---

## 6. Gemini CLI 整合方式

### 呼叫模式

所有自動化透過 Gemini CLI 的非互動模式執行：

```powershell
# 範例：讓 Gemini 萃取 learnings
$prompt = @"
請閱讀以下代理互動紀錄，萃取出可重用的 learnings，
並以指定格式追加到 AGENTS.md 的 [Recent Learnings] 區段。
每條 learning 須包含：來源、問題類型、可執行修正策略。
"@

gemini --prompt $prompt
```

### 預期用途

| 步驟 | Gemini CLI 任務 |
|---|---|
| 萃取 learnings | 讀取 thread 紀錄 → 輸出結構化 learnings |
| 產生 PRD | 讀取 priority item → 輸出 `tasks/prd-*.md` |
| 拆解 tasks | 讀取 PRD → 輸出 `tasks/prd.json` |
| 執行 loop | 逐一執行 task，每完成一個 checkpoint commit |

> **注意**：Gemini CLI 的具體參數（如 `--model`、`--context`）需待安裝後確認實際支援的 flag。

---

## 7. Thread Metadata 來源（TBD）

> [!IMPORTANT]
> 此部分尚未決定。以下列出可能方案，待 user 決定後補充。

| 方案 | 來源 | 備註 |
|---|---|---|
| A | Gemini CLI 本地對話歷史 | 需確認 Gemini CLI 是否在本機存放 conversation log |
| B | `.gemini/` 目錄下的檔案 | Antigravity 可能在專案目錄存放 context |
| C | 手動放入 `reports/` 目錄 | 最簡單，先用手動 → 再自動化 |
| D | 外部 API（Google AI Studio 等） | 需要 API key + 額外開發 |

**建議**：Week 1 先用方案 C（手動放入），確保其餘流程可跑通，再逐步自動化來源。

---

## 8. 資料與記憶治理（AGENTS.md 規範）

```markdown
## Stable Rules
長期有效規則，經多次驗證。

## Recent Learnings (Last 14 days)
近期經驗，超過 14 天自動歸檔或淘汰。
每條包含：
- 來源 thread ID
- 問題類型（build / test / review / ops）
- 可重現條件
- 可執行修正策略

## Known Pitfalls
高頻錯誤與避免策略。

## Verification Checklist
每次交付前必做檢查。
```

---

## 9. 分階段實作路線圖（4 週）

### Week 1：最小可跑通（MVP）

- [ ] 定義 `reports/*.md` 可機器解析格式
- [ ] 完成 `analyze-report.ps1`（輸出 JSON）
- [ ] 完成 `daily-compound-review.ps1`（先手動觸發）
- [ ] 完成 `auto-compound.ps1` 主流程（先不開 PR，只本地驗證）
- [ ] 建立 `AGENTS.md` 初始結構
- [ ] 建立最小 `runbook.md`
- [ ] **在 Windows 上手動執行 `.ps1` 腳本可完成全流程**

### Week 2：排程自動化（Task Scheduler）

- [ ] 完成 `setup-tasks.ps1`（一鍵註冊排程）
- [ ] 完成 `remove-tasks.ps1`（一鍵移除排程）
- [ ] 設定「喚醒電腦以執行」+ 電源計畫
- [ ] 建立 log 目錄 + 腳本內 log rotation（14 天）
- [ ] 加入失敗重試策略（腳本內最多 2 次，指數退避）
- [ ] 加入 review 完成檢查（auto-compound 啟動前確認 review 已完成）

**驗收**：每晚自動觸發兩段流程，且 logs 可完整追蹤。

### Week 3：穩定性與安全

- [ ] Preflight checks（repo 乾淨、token 可用、報告存在、磁碟空間）
- [ ] Postflight checks（commit 成功、PR 建立成功）
- [ ] GitHub token scope 最小化（`gh auth login` 管理）
- [ ] `.env.local` + `.gitignore` 確認
- [ ] 失敗通知（可選：Email / Slack / Windows Toast Notification）
- [ ] 建立 checkpoint 機制（`.compound-state.json`）

**驗收**：故障可在 10 分鐘內被發現並定位。

### Week 4：品質提升

- [ ] AGENTS.md 結構化模板（避免無序膨脹）
- [ ] 週報自動產生（本週交付數、失敗率、常見錯誤）
- [ ] PR 風險分級（小改 auto-merge，大改保留人工審核）

**驗收**：連續 7 天夜跑成功率 ≥ 90%。

---

## 10. 風險清單與對策

| 風險 | 對策 |
|---|---|
| Agent 幻覺導致錯誤 commit | 執行 loop 前後都跑測試；PR 一律 draft |
| Thread source 權限或 API 不穩 | 加 fallback（略過當日 review、發告警） |
| 夜間長任務超時 | 拆小任務 + iteration cap + checkpoint commit |
| 記憶污染（低品質 learnings） | 加入 quality gate，低信心 learning 不寫入 Stable Rules |
| Windows 自動更新 / 重開機 | 設定 Active Hours 避開 22:00–02:00；或暫停自動更新 |
| 電源設定恢復預設 | `setup-tasks.ps1` 同時設定電源計畫 |
| log 檔無限增長 | 腳本內自動清理 14 天前的 log |

---

## 11. KPI

| 指標 | 說明 |
|---|---|
| 每週自動建立 PR 數 | 衡量產出量 |
| 夜跑成功率 | `成功次數 / 排程觸發次數` |
| 平均 lead time | 報告出現 → PR 建立的時間差 |
| 因 AGENTS.md learning 避免的重複錯誤次數 | 衡量 compound effect |
| 人工介入比率 | 越低越好，但不可犧牲品質 |

---

## Proposed Changes

### 新建檔案清單

#### [NEW] [daily-compound-review.ps1](file:///d:/chengen/Antigravity-compound-system/scripts/daily-compound-review.ps1)
每日學習回顧腳本（PowerShell）。git pull → 萃取 learnings → 更新 AGENTS.md → commit/push。

#### [NEW] [auto-compound.ps1](file:///d:/chengen/Antigravity-compound-system/scripts/compound/auto-compound.ps1)
每日自動實作主流程（PowerShell）。解析報告 → 建立分支 → Gemini CLI 產生 PRD → 執行 → 開 Draft PR。

#### [NEW] [analyze-report.ps1](file:///d:/chengen/Antigravity-compound-system/scripts/compound/analyze-report.ps1)
解析 `reports/*.md` 輸出 JSON。

#### [NEW] [loop.ps1](file:///d:/chengen/Antigravity-compound-system/scripts/compound/loop.ps1)
任務執行迴圈，每完成一個 task 做 checkpoint commit。

#### [NEW] [setup-tasks.ps1](file:///d:/chengen/Antigravity-compound-system/config/scheduled-tasks/setup-tasks.ps1)
一鍵註冊 Windows Task Scheduler 排程。

#### [NEW] [remove-tasks.ps1](file:///d:/chengen/Antigravity-compound-system/config/scheduled-tasks/remove-tasks.ps1)
一鍵移除所有排程。

#### [NEW] [compound.env.example](file:///d:/chengen/Antigravity-compound-system/config/compound.env.example)
環境變數範本。

#### [NEW] [AGENTS.md](file:///d:/chengen/Antigravity-compound-system/AGENTS.md)
Agent 記憶檔，含結構化區段。

#### [NEW] [.gitignore](file:///d:/chengen/Antigravity-compound-system/.gitignore)
排除 `.env.local`、`logs/`、暫存檔等。

#### [NEW] [runbook.md](file:///d:/chengen/Antigravity-compound-system/docs/runbook.md)
操作手冊：如何手動重跑、查看 log、故障排除。

---

## Verification Plan

### 手動驗證（Week 1）

1. **手動執行 `daily-compound-review.ps1`**：
   - 在 PowerShell 中執行 `.\scripts\daily-compound-review.ps1`
   - 確認 `AGENTS.md` 被正確更新（或無更新時正常結束）
   - 確認 log 檔正確產生於 `logs/` 目錄

2. **手動執行 `auto-compound.ps1`**：
   - 先在 `reports/` 放入一個測試報告
   - 執行 `.\scripts\compound\auto-compound.ps1`
   - 確認分支建立、PRD 產生、任務執行
   - 確認 log 檔正確產生

3. **手動測試排程註冊**：
   - 執行 `.\config\scheduled-tasks\setup-tasks.ps1`
   - 在 Task Scheduler GUI 中確認兩個工作已建立
   - 用 `schtasks /run /tn "Antigravity-DailyCompoundReview"` 手動觸發
   - 確認 log 正常輸出
