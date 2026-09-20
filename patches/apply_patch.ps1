# apply_patch.ps1 - Lineage sprite delta patcher (generic, v2026-09-20)
# Derived from the 2026-06-15 rune patcher; parameterised so ONE script can apply ANY patch.
# Appends changed images from <PatchName>.dat into the player's Sprite paks, then redirects
# the matching idx entries. Append-only; backs up idx files for rollback.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File apply_patch.ps1 -GameDir "C:\Lineage" -PatchName "bagicon_20260629"
# Exit codes: 0 = applied (or nothing to do), 1 = error (caller should keep the old files)
param(
    [string]$GameDir   = $PSScriptRoot,
    [string]$PatchDir  = $PSScriptRoot,
    [string]$PatchName = "",
    [string]$LogFile   = ""
)
$ErrorActionPreference = 'Stop'

function Log($msg) {
    Write-Host $msg
    if ($LogFile -ne "") {
        try { Add-Content -LiteralPath $LogFile -Value $msg -Encoding Default } catch {}
    }
}

if ($PatchName -eq "") { Log '[ERROR] -PatchName is required.'; exit 1 }

$manPath = Join-Path $PatchDir ($PatchName + '.manifest')
$datPath = Join-Path $PatchDir ($PatchName + '.dat')
if (-not (Test-Path $manPath) -or -not (Test-Path $datPath)) {
    Log "[ERROR] $PatchName .manifest/.dat missing in $PatchDir"; exit 1
}

Log "[apply] patch    = $PatchName"
Log "[apply] gameDir  = $GameDir"

$dat      = [System.IO.File]::ReadAllBytes($datPath)
$manifest = Get-Content $manPath

# ---- 0) Gate: all target paks must be unlocked (game fully closed) ----
function Test-PakState($path) {
    if (-not (Test-Path $path)) { return 'free' }
    try {
        $s = [System.IO.File]::Open($path, [System.IO.FileMode]::Open,
                                    [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $s.Close(); return 'free'
    } catch [System.UnauthorizedAccessException] { return 'denied'
    } catch { return 'locked' }
}

$guard = @('Sprite00.pak', 'Text.pak')
$waited = 0
while ($true) {
    $states = @{}
    foreach ($g in $guard) { $states[$g] = Test-PakState (Join-Path $GameDir $g) }
    if ($states.Values -contains 'denied') {
        Log '[ERROR] Permission denied (game may be under Program Files). Run as administrator.'
        exit 1
    }
    $busy = @($guard | Where-Object { $states[$_] -eq 'locked' })
    if ($busy.Count -eq 0) { break }
    if ($waited -ge 60) { Log ('[ERROR] Game still running (locked: ' + ($busy -join ', ') + ').'); exit 1 }
    Write-Host ('[WAIT] Game is open. Close it; auto-continue...')
    Start-Sleep -Seconds 3
    $waited += 3
}

# ---- 1) Index every Sprite idx: name -> (pak number, record index) ----
# idx layout: [0:4]=count, then 28 bytes each = offset(u32) + name(20B ascii) + size(u32)
$idxBytes = @{}
$nameMap  = @{}
for ($n = 0; $n -le 15; $n++) {
    $idxPath = Join-Path $GameDir ("Sprite{0:D2}.idx" -f $n)
    if (-not (Test-Path $idxPath)) { continue }
    $b = [System.IO.File]::ReadAllBytes($idxPath)
    $idxBytes[$n] = $b
    $cnt = [BitConverter]::ToUInt32($b, 0)
    for ($i = 0; $i -lt $cnt; $i++) {
        $p  = 4 + $i * 28
        $nm = [System.Text.Encoding]::ASCII.GetString($b, $p + 4, 20).TrimEnd([char]0)
        if (-not $nameMap.ContainsKey($nm)) { $nameMap[$nm] = @($n, $i) }
    }
}
if ($idxBytes.Count -eq 0) { Log '[ERROR] No Sprite*.idx found - wrong folder?'; exit 1 }

# ---- 2) Back up idx once per patch (small, enables rollback) ----
foreach ($n in $idxBytes.Keys) {
    $idxPath = Join-Path $GameDir ("Sprite{0:D2}.idx" -f $n)
    $bak = $idxPath + '.bak_' + $PatchName
    if (-not (Test-Path $bak)) { Copy-Item $idxPath $bak }
}

# ---- 3) Append data to pak, repoint idx entry ----
$applied = 0; $missing = 0; $touched = @{}
foreach ($line in $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split "`t"
    if ($parts.Count -lt 3) { continue }
    $nm = $parts[0]; $off = [int]$parts[1]; $sz = [int]$parts[2]
    if (-not $nameMap.ContainsKey($nm)) { $missing++; continue }
    $pair = $nameMap[$nm]; $n = $pair[0]; $i = $pair[1]
    $pakPath = Join-Path $GameDir ("Sprite{0:D2}.pak" -f $n)
    if (-not (Test-Path $pakPath)) { $missing++; continue }
    $newOff = (Get-Item $pakPath).Length
    $chunk  = New-Object byte[] $sz
    [Array]::Copy($dat, $off, $chunk, 0, $sz)
    $fs = [System.IO.File]::Open($pakPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
    $fs.Write($chunk, 0, $sz); $fs.Close()
    $b = $idxBytes[$n]; $p = 4 + $i * 28
    [BitConverter]::GetBytes([uint32]$newOff).CopyTo($b, $p)
    [BitConverter]::GetBytes([uint32]$sz).CopyTo($b, $p + 24)
    $touched[$n] = $true
    $applied++
}

# ---- 4) Write idx back ----
foreach ($n in $touched.Keys) {
    $idxPath = Join-Path $GameDir ("Sprite{0:D2}.idx" -f $n)
    [System.IO.File]::WriteAllBytes($idxPath, $idxBytes[$n])
}

Log ("[OK] patch=" + $PatchName + " applied=" + $applied + " missing=" + $missing)
if ($applied -eq 0 -and $missing -gt 0) {
    Log '[WARN] Nothing applied - your client may be a different version.'
    exit 1
}
exit 0
