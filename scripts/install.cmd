@echo off
rem Right-click -> "Run as administrator".
net session >nul 2>&1
if errorlevel 1 (
  echo Please right-click install.cmd and choose "Run as administrator".
  echo Nazhmite pravoy knopkoy na install.cmd i vyberite "Zapusk ot imeni administratora".
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
