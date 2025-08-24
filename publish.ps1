Param(
  [switch]$Serve
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

# 导出（入口：publish:true / #publish；或通过额外参数指定通配：npm run publish -- "1 卡片箱\\*.md"）
Write-Host "[Quartz] 导出入口笔记及依赖..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'tools/Export-Notes.ps1') -SourceRoot (Join-Path $PSScriptRoot '..\noteBOOK') -DestRoot (Join-Path $PSScriptRoot 'content') -EntryPatterns $args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 自动提交导出结果
try {
  Write-Host "[Quartz] Git add content/ ..." -ForegroundColor Yellow
  git add content | Out-Null
  $pending = git status -s
  if ($pending) {
    Write-Host "[Quartz] Git commit 导出内容..." -ForegroundColor Yellow
    git commit -m "chore(content): auto export & stage content for publish" | Out-Null

    # 立即推送到当前分支
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    if (-not [string]::IsNullOrWhiteSpace($branch)) {
      Write-Host "[Quartz] Git push origin $branch ..." -ForegroundColor Yellow
      git push origin $branch | Out-Null
    }
  } else {
    Write-Host "[Quartz] 无需提交（工作区无变化）" -ForegroundColor Yellow
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


