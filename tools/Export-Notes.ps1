Param(
  [string]$SourceRoot = (Join-Path $PSScriptRoot "..\..\noteBOOK"),
  [string]$DestRoot   = (Join-Path $PSScriptRoot "..\content"),
  [string[]]$EntryPatterns = @(),
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg)  { Write-Host "[Export] $msg" -ForegroundColor Cyan }
function Write-Warn($msg)  { Write-Host "[Export] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[Export] $msg" -ForegroundColor Red }

function Get-Frontmatter {
  param([string]$Path)
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue
  if ($null -eq $lines -or $lines.Count -lt 1) { return @{} }
  if ($lines[0] -ne '---') { return @{} }
  $fm = @{}
  for ($i=1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq '---') { break }
    $m = [regex]::Match($lines[$i], '^(?<k>[^:]+):\s*(?<v>.+)$')
    if ($m.Success) {
      $key = ($m.Groups['k'].Value).Trim()
      $val = ($m.Groups['v'].Value).Trim()
      $fm[$key] = $val
    }
  }
  return $fm
}

function Test-IsDraft {
  param([string]$Path)
  $fm = Get-Frontmatter -Path $Path
  if ($fm.ContainsKey('draft') -and $fm['draft'] -match '^(?i:true)$') { return $true }
  return $false
}

function Test-IsPublishEntry {
  param([string]$Path)
  $fm = Get-Frontmatter -Path $Path
  if ($fm.ContainsKey('publish') -and $fm['publish'] -match '^(?i:true)$') { return $true }
  if ($fm.ContainsKey('draft') -and $fm['draft'] -match '^(?i:true)$') { return $false }
  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
  if ($null -ne $text -and $text -match '(?im)(^|\s)#publish(\b|$)') { return $true }
  return $false
}

function Get-RelativePath {
  param([string]$BasePath, [string]$FullPath)
  $base = [System.IO.Path]::GetFullPath($BasePath)
  $full = [System.IO.Path]::GetFullPath($FullPath)
  if (-not $full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
  $rel = $full.Substring($base.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  return $rel
}

function Ensure-CopyFile {
  param([string]$Src, [string]$Dst)
  if ($DryRun) { Write-Info "DRYRUN copy: $Src -> $Dst"; return }
  $dstDir = Split-Path -LiteralPath $Dst -Parent
  if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
  Copy-Item -LiteralPath $Src -Destination $Dst -Force
}

function Resolve-LinkPath {
  param([string]$Link, [string]$CurrentDir)
  # Strip anchors or block refs
  $clean = ($Link -replace '(#|\^).*$', '').Trim()
  if ($clean -match '^(?i)([a-z]+)://') { return $null }
  if ([string]::IsNullOrWhiteSpace($clean)) { return $null }

  $hasDirSep = $clean.Contains('/') -or $clean.Contains('\\')
  $candidate = $null
  if ($hasDirSep) {
    $p = $clean -replace '/', '\\'
    $abs = Join-Path $CurrentDir $p
    if (Test-Path -LiteralPath $abs) { $candidate = (Resolve-Path -LiteralPath $abs).Path }
    else {
      $abs2 = Join-Path $SourceRoot $p
      if (Test-Path -LiteralPath $abs2) { $candidate = (Resolve-Path -LiteralPath $abs2).Path }
    }
  } else {
    $name = $clean
    $items = Get-ChildItem -Path $SourceRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
      $_.BaseName -eq $name
    }
    if ($items) {
      $candidate = ($items | Sort-Object { $_.FullName.Length } | Select-Object -First 1).FullName
    }
  }
  return $candidate
}

function Parse-Links {
  param([string]$Path)
  $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
  if ($null -eq $text) { return @() }
  $links = New-Object System.Collections.Generic.List[string]
  # Wiki links: [[...]] and ![[...]]
  foreach ($m in [regex]::Matches($text, '!?\[\[(?<t>[^\]|]+)(?:\|[^\]]+)?\]\]')) { $links.Add($m.Groups['t'].Value) }
  # Markdown links: [text](path) and images ![alt](path)
  foreach ($m in [regex]::Matches($text, '!?(?:\[[^\]]*\])\((?<t>[^)]+)\)')) { $links.Add($m.Groups['t'].Value) }
  return $links
}

function Export-Closure {
  param([string[]]$Entries)
  $queue   = New-Object System.Collections.Queue
  $visited = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($e in $Entries) {
    if (-not (Test-Path -LiteralPath $e)) { Write-Warn "入口不存在: $e"; continue }
    if ($visited.Contains($e)) { continue }
    $visited.Add($e) | Out-Null
    $queue.Enqueue($e)
  }

  $imageExts = @('.png','.jpg','.jpeg','.gif','.svg','.webp')

  while ($queue.Count -gt 0) {
    $file = [string]$queue.Dequeue()
    $rel  = Get-RelativePath -BasePath $SourceRoot -FullPath $file
    if ($null -eq $rel) { Write-Warn "跳过非源内文件: $file"; continue }
    $dst  = Join-Path $DestRoot $rel

    if ($file.ToLower().EndsWith('.md')) {
      if (Test-IsDraft -Path $file) {
        Write-Warn "草稿跳过(仅引用，不拷贝): $rel"
      } else {
        Write-Info "拷贝笔记: $rel"
        Ensure-CopyFile -Src $file -Dst $dst
      }

      $curDir = Split-Path -LiteralPath $file -Parent
      $links  = Parse-Links -Path $file
      foreach ($ln in $links) {
        $resolved = Resolve-LinkPath -Link $ln -CurrentDir $curDir
        if ($null -eq $resolved) { continue }
        if ($resolved.ToLower().EndsWith('.md')) {
          if (-not (Test-IsDraft -Path $resolved)) {
            if (-not $visited.Contains($resolved)) { $visited.Add($resolved) | Out-Null; $queue.Enqueue($resolved) }
          } else {
            Write-Warn "引用到草稿(不导出): $(Get-RelativePath $SourceRoot $resolved)"
          }
        } else {
          $relAsset = Get-RelativePath -BasePath $SourceRoot -FullPath $resolved
          if ($null -ne $relAsset -and ($imageExts -contains ([IO.Path]::GetExtension($resolved).ToLower()))) {
            $dstAsset = Join-Path $DestRoot $relAsset
            Write-Info "拷贝资源: $relAsset"
            Ensure-CopyFile -Src $resolved -Dst $dstAsset
          }
        }
      }
    } else {
      # 资源文件
      if ($imageExts -contains ([IO.Path]::GetExtension($file).ToLower())) {
        Write-Info "拷贝资源: $rel"
        Ensure-CopyFile -Src $file -Dst $dst
      }
    }
  }
}

if (-not (Test-Path -LiteralPath $SourceRoot)) { Write-Err "SourceRoot 不存在: $SourceRoot"; exit 1 }
if (-not (Test-Path -LiteralPath $DestRoot))   { New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null }

# 选取入口笔记
$entries = @()
if ($EntryPatterns -and $EntryPatterns.Count -gt 0) {
  foreach ($pat in $EntryPatterns) {
    $entries += Get-ChildItem -Path $SourceRoot -Recurse -File -Include $pat -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.md' } | Select-Object -ExpandProperty FullName
  }
} else {
  $entries = Get-ChildItem -Path $SourceRoot -Recurse -File -Filter *.md | Where-Object { Test-IsPublishEntry -Path $_.FullName } | Select-Object -ExpandProperty FullName
}

Write-Info "入口笔记数量: $($entries.Count)"
if ($entries.Count -eq 0) { Write-Warn "未找到入口笔记（可在 frontmatter 设置 publish:true 或加 #publish 标签）"; exit 0 }

Export-Closure -Entries $entries

Write-Info "导出完成"


