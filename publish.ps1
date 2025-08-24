Param(
  [switch]$Serve,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$EntryPatterns
)

Write-Host "[Quartz] 开始一键发布流程..." -ForegroundColor Cyan

# 使用本地 Node/npm 环境
if (!(Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error "未检测到 Node.js，请先安装 Node.js"
  exit 1
}

# 可选：开发预览
if ($Serve) {
  Write-Host "[Quartz] 本地预览启动中..." -ForegroundColor Yellow
  npx quartz build --serve
  exit $LASTEXITCODE
}

# 导出（入口：publish:true / #publish；或通过 -EntryPatterns 指定）
Write-Host "[Quartz] 导出入口笔记及依赖..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'tools/Export-Notes.ps1') -SourceRoot (Join-Path $PSScriptRoot '..\noteBOOK') -DestRoot (Join-Path $PSScriptRoot 'content') -EntryPatterns $EntryPatterns
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 构建 & 同步
Write-Host "[Quartz] 构建站点..." -ForegroundColor Yellow
npx quartz build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[Quartz] 推送同步..." -ForegroundColor Yellow
npx quartz sync
exit $LASTEXITCODE


