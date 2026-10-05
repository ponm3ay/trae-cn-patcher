#requires -Version 5
# Trae CN micro-patcher: apply | restore | status
# ASCII-only output on purpose (cmd parses this file's siblings as GBK; keep this file English/ASCII too).
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('apply', 'restore', 'status')]
  [string]$Action = 'status',
  [string]$InstallDir = '',
  [string]$ManifestPath = ''
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ManifestPath) { $ManifestPath = Join-Path (Split-Path -Parent $scriptDir) 'manifest.json' }
if (-not (Test-Path $ManifestPath)) { throw "manifest.json not found at: $ManifestPath" }
$manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Write-Log {
  param([string]$Msg, [string]$Color = 'Gray')
  Write-Host "[trae-patcher] $Msg" -ForegroundColor $Color
}
function Fail {
  param([string]$Msg)
  Write-Host "[trae-patcher][ERROR] $Msg" -ForegroundColor Red
  exit 1
}
function Get-FileHash-B64 {
  param([string]$Path)
  # Trae integrity algorithm: sha256 -> base64 -> strip trailing '='
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return [Convert]::ToBase64String($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path))).TrimEnd('=')
  } finally { $sha.Dispose() }
}
function Resolve-InstallDir {
  if ($InstallDir) {
    if (Test-Path (Join-Path $InstallDir 'resources\app\product.json')) { return $InstallDir }
    Fail "InstallDir '$InstallDir' does not look like a Trae install root (missing resources\app\product.json)."
  }
  foreach ($dir in $manifest.installDirs) {
    $expanded = [Environment]::ExpandEnvironmentVariables($dir)
    if (Test-Path (Join-Path $expanded 'resources\app\product.json')) { return $expanded }
  }
  Fail "Trae install dir not found. Pass -InstallDir explicitly, e.g. -InstallDir 'D:\Trae CN'."
}
function Sync-Checksum {
  param($Patch, [string]$AppRoot)
  $sync = $Patch.checksumSync
  if (-not $sync) { return }
  $productJsonPath = Join-Path $AppRoot $sync.productJson
  $targetPath = Join-Path $AppRoot $Patch.target
  $hash = Get-FileHash-B64 $targetPath
  $text = [System.IO.File]::ReadAllText($productJsonPath)
  $pattern = '("' + [regex]::Escape($sync.checksumKey) + '"\s*:\s*")[^"]*(")'
  $rx = [regex]::new($pattern)
  if ($rx.Matches($text).Count -eq 0) {
    Write-Log "  checksum sync: key '$($sync.checksumKey)' not found in $($sync.productJson) (IDE version changed?). Update manifest." 'Yellow'
    return
  }
  $newText = $rx.Replace($text, ('${1}' + $hash + '${2}'), 1)
  if ($newText -eq $text) {
    Write-Log "  checksum sync: '$($sync.checksumKey)' already in sync ($hash)" 'Green'
    return
  }
  [System.IO.File]::WriteAllText($productJsonPath, $newText, [System.Text.UTF8Encoding]::new($false))
  Write-Log "  checksum sync: '$($sync.checksumKey)' -> $hash" 'Green'
}
function Invoke-Apply {
  $root = Resolve-InstallDir
  $appRoot = Join-Path $root 'resources\app'
  Write-Log "install dir: $root" 'Cyan'
  foreach ($patch in $manifest.patches) {
    $targetPath = Join-Path $appRoot $patch.target
    if (-not (Test-Path $targetPath)) { Fail "target missing: $targetPath" }
    $text = [System.IO.File]::ReadAllText($targetPath)
    $rx = [regex]::new($patch.matchRegex)
    $count = $rx.Matches($text).Count
    if ($count -eq 0) {
      Write-Log "PATCH '$($patch.id)': pattern not found - already applied, or IDE version changed (check status)." 'Yellow'
      continue
    }
    if ($count -ne $patch.expectedOccurrences) {
      Fail "PATCH '$($patch.id)': found $count occurrence(s), expected $($patch.expectedOccurrences). Aborting for safety."
    }
    $bak = "$targetPath.bak"
    if (Test-Path $bak) {
      Write-Log "  backup already exists, keeping the original: $bak"
    } else {
      [System.IO.File]::Copy($targetPath, $bak)
      Write-Log "  backup created: $bak"
    }
    $patched = $rx.Replace($text, $patch.replace, [Math]::Max(1, $patch.expectedOccurrences))
    [System.IO.File]::WriteAllText($targetPath, $patched, [System.Text.UTF8Encoding]::new($false))
    Write-Log "PATCH '$($patch.id)': applied ($count occurrence(s) replaced)." 'Green'
  }
  foreach ($patch in $manifest.patches) { Sync-Checksum $patch $appRoot }
  Write-Log "Done. Restart Trae (or reload all windows) for changes to take effect."
}
function Invoke-Restore {
  $root = Resolve-InstallDir
  $appRoot = Join-Path $root 'resources\app'
  Write-Log "install dir: $root" 'Cyan'
  foreach ($patch in $manifest.patches) {
    $targetPath = Join-Path $appRoot $patch.target
    $bak = "$targetPath.bak"
    if (Test-Path $bak) {
      Copy-Item $bak $targetPath -Force
      Remove-Item $bak -Force
      Write-Log "RESTORE '$($patch.id)': restored from backup." 'Green'
    } else {
      Write-Log "RESTORE '$($patch.id)': no backup at $bak, skipping." 'Yellow'
    }
  }
  foreach ($patch in $manifest.patches) { Sync-Checksum $patch $appRoot }
  Write-Log "Done. Restart Trae for changes to take effect."
}
function Invoke-Status {
  $root = Resolve-InstallDir
  $appRoot = Join-Path $root 'resources\app'
  Write-Log "install dir: $root" 'Cyan'
  foreach ($patch in $manifest.patches) {
    Write-Log "PATCH '$($patch.id)' - $($patch.description)"
    $targetPath = Join-Path $appRoot $patch.target
    if (-not (Test-Path $targetPath)) { Write-Log "  target missing: $targetPath" 'Red'; continue }
    $text = [System.IO.File]::ReadAllText($targetPath)
    $count = ([regex]::new($patch.matchRegex)).Matches($text).Count
    if ($count -gt 0) {
      Write-Log "  state: UNPATCHED ($count occurrence(s))" 'Yellow'
    } elseif (Test-Path "$targetPath.bak") {
      Write-Log "  state: PATCHED (backup present)" 'Green'
    } else {
      Write-Log "  state: PATCHED? (pattern not found, no backup - IDE version may differ from manifest)" 'Yellow'
    }
    $sync = $patch.checksumSync
    if ($sync) {
      $productJsonPath = Join-Path $appRoot $sync.productJson
      $recorded = ((Get-Content $productJsonPath -Raw | ConvertFrom-Json).checksums.PSObject.Properties[$sync.checksumKey]).Value
      $actual = Get-FileHash-B64 $targetPath
      if ($null -eq $recorded) {
        Write-Log "  integrity: key '$($sync.checksumKey)' missing in $($sync.productJson)" 'Yellow'
      } elseif ($recorded -eq $actual) {
        Write-Log "  integrity: OK (checksum in sync)" 'Green'
      } else {
        Write-Log "  integrity: MISMATCH (run apply to re-sync)" 'Red'
      }
    }
  }
}

switch ($Action) {
  'apply'   { Invoke-Apply }
  'restore' { Invoke-Restore }
  'status'  { Invoke-Status }
}
