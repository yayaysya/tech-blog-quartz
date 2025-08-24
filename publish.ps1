Param(
  [switch]$Serve,
  [switch]$NoClean
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

# 可选：清理 content（默认清理，保留首页 index.md；使用 -NoClean 可跳过）
if (-not $NoClean) {
  try {
    $contentDir = Join-Path $PSScriptRoot 'content'
    if (-not (Test-Path -LiteralPath $contentDir)) { New-Item -ItemType Directory -Force -Path $contentDir | Out-Null }
    Write-Host "[Quartz] 清理 content/ ..." -ForegroundColor Yellow
    Get-ChildItem -LiteralPath $contentDir -Force | Where-Object { $_.Name -ne 'index.md' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  } catch {
    Write-Warning "[Quartz] 清理 content 失败: $_"
  }
}

# 导出（入口：publish:true / #publish；或通过额外参数指定通配：npm run publish -- "1 卡片箱\\*.md"）
Write-Host "[Quartz] 导出入口笔记及依赖..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'tools/Export-Notes.ps1') -SourceRoot (Join-Path $PSScriptRoot '..\noteBOOK') -DestRoot (Join-Path $PSScriptRoot 'content') -EntryPatterns $args

# 自动提交导出结果
try {
  Write-Host "[Quartz] Git add -A content/ ..." -ForegroundColor Yellow
  git add -A content | Out-Null
  $pending = git status -s
  if ($pending) {
    Write-Host "[Quartz] Git commit 导出内容..." -ForegroundColor Yellow
    git commit -m "chore(content): refresh export (auto)" | Out-Null
  } else {
    Write-Host "[Quartz] 无需提交（工作区无变化）" -ForegroundColor Yellow
  }
  # 无论是否有改动都尝试推送一次，确保远端最新
  $branch = (git rev-parse --abbrev-ref HEAD).Trim()
  if (-not [string]::IsNullOrWhiteSpace($branch)) {
    Write-Host "[Quartz] Git push -u origin $branch ..." -ForegroundColor Yellow
    git push -u origin $branch | Out-Null
  }
} catch {
  Write-Warning "[Quartz] 自动提交失败: $_"
}

# 构建 & 同步
Write-Host "[Quartz] 构建站点..." -ForegroundColor Yellow
npx quartz build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[Quartz] 推送同步..." -ForegroundColor Yellow
npx quartz sync
exit $LASTEXITCODE


