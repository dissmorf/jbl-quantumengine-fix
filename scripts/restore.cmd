@echo off
rem Right-click -> "Run as administrator".
net session >nul 2>&1
if errorlevel 1 (
  echo Please right-click restore.cmd and choose "Run as administrator".
  echo Nazhmite pravoy knopkoy na restore.cmd i vyberite "Zapusk ot imeni administratora".
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore.ps1" %*
pause
