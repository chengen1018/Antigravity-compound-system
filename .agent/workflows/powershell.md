---
description: PowerShell version policy - always use PowerShell 7
---

## PowerShell 版本規範

// turbo-all

1. **永遠使用 `pwsh`（PowerShell 7）** 來執行所有 `.ps1` 腳本和 PowerShell 命令。
2. **不要使用 `powershell`（5.1）**，因為 PowerShell 5.1 不支援 UTF-8 without BOM，會導致中文亂碼。
3. 執行腳本的標準格式：
   ```
   pwsh -NoProfile -ExecutionPolicy Bypass -File <script.ps1>
   ```
4. 執行單行命令的標準格式：
   ```
   pwsh -NoProfile -Command "<command>"
   ```
5. 建立新的 `.ps1` 腳本時，不需要加 `#Requires -Version 7.0`，但可以放心使用 PowerShell 7 的功能。
6. 不需要特別處理 UTF-8 BOM 編碼問題（PowerShell 7 原生支援 UTF-8）。
