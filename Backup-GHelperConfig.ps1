<#Requires -Version 5.1>
<#
.SYNOPSIS
  Backup G-Helper configs with date+time in filename.

.DESCRIPTION
  G-Helper (AppConfig.cs) stores config in 3 possible locations:
    1. Portable:  <GHelper.exe dir>\config.json  (if exists, takes priority)
    2. Primary:   %APPDATA%\GHelper\config.json  -> C:\Users\<you>\AppData\Roaming\GHelper\config.json
    3. Fallback:  %PROGRAMDATA%\GHelper\config.json -> C:\ProgramData\GHelper\config.json (SYSTEM / service)
  On atomic save it also creates:
    - config.json.bak (previous version via File.Replace)
    - config.json.tmp (transient)

  This script backs up any existing config.json + .bak (+ fallback/portable) to:
    %APPDATA%\GHelper\Backups\config_yyyy-MM-dd_HH-mm-ss.json
  Use -BackupDir to override. Use -Keep 30 to auto-prune old backups.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File Backup-GHelperConfig.ps1
  powershell -ExecutionPolicy Bypass -File Backup-GHelperConfig.ps1 -BackupDir C:\Backups\GHelper -Keep 30

.NOTES
  Works without admin. Run as SYSTEM/admin to also capture ProgramData fallback if needed.
#>

[CmdletBinding()]
param(
  [string]$BackupDir = "",
  [int]$Keep = 0,  # 0 = keep all, else keep N newest
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-GHelperPaths {
  $appData  = [Environment]::GetFolderPath("ApplicationData")       # Roaming
  $common   = [Environment]::GetFolderPath("CommonApplicationData") # ProgramData
  $paths = @()

  # 1. Portable: exe dir (detect running or common install locations)
  $exePaths = @()
  try {
    $ghelper = Get-Process GHelper -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
    if ($ghelper) { $exePaths += Split-Path $ghelper -Parent }
  } catch {}
  $exePaths += @(
    "$env:ProgramFiles\GHelper",
    "${env:ProgramFiles(x86)}\GHelper",
    (Join-Path $PSScriptRoot "."),
    (Get-Location).Path
  ) | Select-Object -Unique

  foreach ($dir in $exePaths) {
    if (-not $dir) { continue }
    $p = Join-Path $dir "config.json"
    if (Test-Path $p) { $paths += [PSCustomObject]@{ Role="Portable (exe dir)"; Path=$p; Dir=$dir } }
  }

  # 2. Primary
  $primary = Join-Path (Join-Path $appData "GHelper") "config.json"
  $paths += [PSCustomObject]@{ Role="Primary (APPDATA)"; Path=$primary; Dir=(Split-Path $primary -Parent) }

  # 3. Fallback SYSTEM
  $fallback = Join-Path (Join-Path $common "GHelper") "config.json"
  $paths += [PSCustomObject]@{ Role="Fallback (PROGRAMDATA)"; Path=$fallback; Dir=(Split-Path $fallback -Parent) }

  return $paths
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
if (-not $BackupDir -or $BackupDir.Trim() -eq "") {
  $BackupDir = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "GHelper\Backups"
}
$BackupDir = [Environment]::ExpandEnvironmentVariables($BackupDir)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

Write-Host "G-Helper config backup @ $timestamp" -ForegroundColor Cyan
Write-Host "Backup dir: $BackupDir" -ForegroundColor DarkGray

$paths = Resolve-GHelperPaths
$backedUp = @()

foreach ($entry in $paths) {
  $src = $entry.Path
  $role = $entry.Role

  # collect src + .bak + .tmp if they exist
  $candidates = @(
    $src
    "$src.bak"
  )

  foreach ($cand in $candidates) {
    if (-not (Test-Path $cand)) { continue }

    $leaf = Split-Path $cand -Leaf  # config.json or config.json.bak
    $isBak = $leaf.EndsWith(".bak")
    # config_2025-09-09_21-15-00.json  / config_2025-09-09_21-15-00.bak.json
    $suffix = if ($isBak) { ".bak.json" } else { ".json" }
    $baseName = "config_${timestamp}"
    # disambiguate by role if multiple sources: add suffix
    $roleSuffix = ""
    if ($role -like "Portable*") { $roleSuffix = "_portable" }
    elseif ($role -like "Fallback*") { $roleSuffix = "_fallback" }

    $destName = "${baseName}${roleSuffix}${suffix}"
    # ensure unique if collision (same second, multiple runs)
    $dest = Join-Path $BackupDir $destName
    $n = 1
    while (Test-Path $dest) {
      $destName = "${baseName}${roleSuffix}_${n}${suffix}"
      $dest = Join-Path $BackupDir $destName
      $n++
    }

    try {
      Copy-Item -LiteralPath $cand -Destination $dest -Force
      $size = (Get-Item $dest).Length
      Write-Host "  [$role] $leaf -> $destName ($size bytes)" -ForegroundColor Green
      $backedUp += [PSCustomObject]@{ Source=$cand; Dest=$dest; Role=$role; Size=$size }
    } catch {
      Write-Warning "  [$role] FAILED $cand : $_"
    }
  }

  if (-not (Test-Path $src) -and -not (Test-Path "$src.bak")) {
    Write-Host "  [$role] not found: $src" -ForegroundColor DarkYellow
  }
}

# prune
if ($Keep -gt 0) {
  $all = Get-ChildItem -Path $BackupDir -Filter "config_*.json" -File | Sort-Object LastWriteTime -Descending
  if ($all.Count -gt $Keep) {
    $toDelete = $all | Select-Object -Skip $Keep
    foreach ($f in $toDelete) {
      Remove-Item $f.FullName -Force
      Write-Host "  pruned old: $($f.Name)" -ForegroundColor DarkGray
    }
  }
}

Write-Host ""
if ($backedUp.Count -eq 0) {
  Write-Warning "No G-Helper configs found. Checked:"
  $paths | ForEach-Object { Write-Host "  $($_.Role): $($_.Path)" }
  Write-Host "Tip: G-Helper creates config on first run. Run GHelper.exe once, then retry."
} else {
  Write-Host "Backed up $($backedUp.Count) file(s) to $BackupDir" -ForegroundColor Cyan
  Get-ChildItem $BackupDir -Filter "config_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | Format-Table Name, Length, LastWriteTime -AutoSize | Out-String | Write-Host
}

if ($PassThru) { return $backedUp }

# also show current config for debugging (first 20 lines)
$primary = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "GHelper\config.json"
if (Test-Path $primary) {
  Write-Host "Primary config preview ($primary):" -ForegroundColor DarkGray
  Get-Content $primary -TotalCount 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}
