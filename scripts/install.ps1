<#
.SYNOPSIS
  Applies the QuantumENGINE "greyed out settings" fix to QuantumServer.dll.

.DESCRIPTION
  1. Checks that QuantumServer.dll is the original (unpatched) file.
  2. Builds a patched copy with QEWirelessFix.exe.
  3. Stops the QuantumService, saves the original as QuantumServer.dll.orig,
     puts the patched file in place and starts the service again.
  Undo with restore.cmd / restore.ps1.

.PARAMETER InstallDir
  QuantumENGINE folder. Default: C:\Program Files\JBL\QuantumENGINE

.PARAMETER Force
  Patch even if this QuantumServer.dll version was not tested.

.PARAMETER NoService
  Do not stop/start the Windows service and skip the admin check (for testing on a copy).
#>
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles 'JBL\QuantumENGINE'),
    [switch]$Force,
    [switch]$NoService
)
$ErrorActionPreference = 'Stop'
$ServiceName = 'QuantumService'

function Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Done($text) { Write-Host $text -ForegroundColor Green }
function Stop-QuantumService {
    if ($NoService) { return }
    Step "Stopping $ServiceName"
    Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
    Get-Process QuantumServer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}
function Start-QuantumService {
    if ($NoService) { return }
    Step "Starting $ServiceName"
    Start-Service $ServiceName
}

if (-not $NoService) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'Run this script as Administrator (right-click install.cmd -> Run as administrator).' }
}

$patcher = Join-Path $PSScriptRoot 'QEWirelessFix.exe'
$dll     = Join-Path $InstallDir 'QuantumServer.dll'
$backup  = "$dll.orig"
if (-not (Test-Path $patcher)) { throw "QEWirelessFix.exe not found next to this script: $patcher" }
if (-not (Test-Path $dll))     { throw "QuantumServer.dll not found in '$InstallDir'. Is QuantumENGINE installed? Use -InstallDir to set the folder." }

Step 'Checking QuantumServer.dll'
& $patcher check $dll
switch ($LASTEXITCODE) {
    0 { }
    2 { Done 'Already patched. Nothing to do.'; exit 0 }
    default { throw "QuantumServer.dll could not be checked (code $LASTEXITCODE)." }
}

Step 'Creating patched copy'
$temp = Join-Path $env:TEMP "QuantumServer.patched.$PID.dll"
$patchArgs = @('patch', $dll, $temp)
if ($Force) { $patchArgs += '--force' }
& $patcher @patchArgs
if ($LASTEXITCODE -ne 0) {
    if ($LASTEXITCODE -eq 3) { Write-Host 'This QuantumENGINE version was not tested. If you understand the risk, run: install.cmd -Force' -ForegroundColor Yellow }
    throw "Patching failed (code $LASTEXITCODE). Nothing was changed."
}

Stop-QuantumService
try {
    Step "Saving original as $(Split-Path $backup -Leaf)"
    Copy-Item $dll $backup -Force
    Step 'Installing patched QuantumServer.dll'
    Copy-Item $temp $dll -Force
}
catch {
    Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
    if ((Test-Path $backup) -and ((Get-FileHash $backup).Hash -ne (Get-FileHash $dll).Hash)) {
        Write-Host 'Putting the original file back.' -ForegroundColor Yellow
        Copy-Item $backup $dll -Force
    }
    throw
}
finally {
    Remove-Item $temp -ErrorAction SilentlyContinue
    Start-QuantumService
}

& $patcher check $dll | Out-Null
if ($LASTEXITCODE -ne 2) { throw 'Verification failed: QuantumServer.dll is not patched after install.' }

Done ''
Done 'Patch installed.'
Write-Host 'Next steps:'
Write-Host '  1. Turn the headset on and open QuantumENGINE. Settings should now be active.'
Write-Host '  2. Update the firmware from QuantumENGINE (repeat until it says the firmware is up to date).'
Write-Host '  3. Run restore.cmd as Administrator to put the original file back.'
