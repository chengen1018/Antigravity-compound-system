<#
.SYNOPSIS
    解析優先級報告，輸出第一優先任務的 JSON。

.DESCRIPTION
    讀取 reports/ 目錄中最新的 priority-report-*.md，
    解析第一優先任務的標題、描述、範圍和驗收標準。

.OUTPUTS
    JSON 格式的任務資訊，寫入 stdout。

.EXAMPLE
    .\analyze-report.ps1
    .\analyze-report.ps1 -ReportPath "reports\priority-report-2026-02-23.md"
#>

param(
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8

# 定位 repo 根目錄
$REPO_ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $REPO_ROOT) { $REPO_ROOT = Split-Path -Parent $PSScriptRoot }

# 找到最新的報告
$reportsDir = Join-Path $REPO_ROOT "reports"

if ($ReportPath) {
    $reportFile = $ReportPath
    if (-not [System.IO.Path]::IsPathRooted($reportFile)) {
        $reportFile = Join-Path $REPO_ROOT $reportFile
    }
}
else {
    $reports = Get-ChildItem -Path $reportsDir -Filter "priority-report-*.md" | Sort-Object Name -Descending
    if ($reports.Count -eq 0) {
        Write-Error "找不到任何 priority-report-*.md 在 $reportsDir"
        exit 1
    }
    $reportFile = $reports[0].FullName
}

if (-not (Test-Path $reportFile)) {
    Write-Error "報告不存在: $reportFile"
    exit 1
}

# 讀取報告內容
$content = Get-Content $reportFile -Raw -Encoding UTF8

# 解析第一優先任務（### 1. 開頭的區塊）
$pattern = '### 1\.\s*\[(\w+)\]\s*(.+?)(?:\r?\n)'
$match = [regex]::Match($content, $pattern)

if (-not $match.Success) {
    Write-Error "無法解析報告中的第一優先任務。請確認格式符合 reports/README.md 的規範。"
    exit 1
}

$priority = $match.Groups[1].Value
$title = $match.Groups[2].Value.Trim()

# 提取子欄位
function Get-Field {
    param([string]$Content, [string]$FieldName, [string]$NextSectionPattern = '###|\Z')

    # 限定搜尋範圍到第一個任務區塊
    $taskBlockMatch = [regex]::Match($Content, '### 1\..*?(?=### 2\.|\Z)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $taskBlockMatch.Success) { return "" }
    $taskBlock = $taskBlockMatch.Value

    $fieldPattern = "\*\*$FieldName\*\*:\s*(.+)"
    $fieldMatch = [regex]::Match($taskBlock, $fieldPattern)
    if ($fieldMatch.Success) {
        return $fieldMatch.Groups[1].Value.Trim()
    }
    return ""
}

$description = Get-Field -Content $content -FieldName "描述"
$scope = Get-Field -Content $content -FieldName "範圍"
$acceptanceCriteria = Get-Field -Content $content -FieldName "驗收標準"

# 產生 slug（用於 branch 名稱）
$slug = ($title -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
if ($slug.Length -gt 50) { $slug = $slug.Substring(0, 50) }

# 輸出 JSON
$result = @{
    report_file         = (Split-Path $reportFile -Leaf)
    report_date         = [regex]::Match((Split-Path $reportFile -Leaf), '\d{4}-\d{2}-\d{2}').Value
    priority            = $priority
    title               = $title
    description         = $description
    scope               = $scope
    acceptance_criteria = $acceptanceCriteria
    slug                = $slug
} | ConvertTo-Json -Depth 3

Write-Output $result
