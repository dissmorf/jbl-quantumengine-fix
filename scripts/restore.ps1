<#
.SYNOPSIS
  Puts the original QuantumServer.dll back (undoes install.ps1).

.PARAMETER InstallDir
  QuantumENGINE folder. Default: C:\Program Files\JBL\QuantumENGINE

.PARAMETER NoService
  Do not stop/start the Windows service and skip the admin check (for testing on a copy).
#>
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'JBL\QuantumENGINE'),
    [switch]$NoService
)
$ErrorActionPreference = 'Stop'
$ServiceName = 'QuantumService'

function Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Done($text) { Write-Host $text -ForegroundColor Green }

if (-not $NoService) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Run this script as Administrator (right-click restore.cmd -> Run as administrator).' }
}

$patcher = Join-Path $PSScriptRoot 'QEWirelessFix.exe'
$dll     = Join-Path $InstallDir 'QuantumServer.dll'
$backup  = "$dll.orig"

if (-not (Test-Path $backup)) {
    if ((Test-Path $patcher) -and (Test-Path $dll)) {
        & $patcher check $dll | Out-Null
        if ($LASTEXITCODE -eq 0) { Done 'QuantumServer.dll is already the original. Nothing to restore.'; exit 0 }
    }
    throw "Backup '$backup' not found. Reinstall QuantumENGINE to get the original file back."
}

if (-not $NoService) {
    Step "Stopping $ServiceName"
    Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
    Get-Process QuantumServer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}
try {
    Step 'Restoring original QuantumServer.dll'
    Copy-Item $backup $dll -Force
    Remove-Item $backup
}
finally {
    if (-not $NoService) { Step "Starting $ServiceName"; Start-Service $ServiceName }
}

if (Test-Path $patcher) {
    & $patcher check $dll | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Verification failed: QuantumServer.dll is still patched.' }
}
Done 'Original QuantumServer.dll restored.'
