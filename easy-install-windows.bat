@echo off
setlocal
cd /d "%~dp0"

echo.
echo [Activity2Context] Installing and starting runtime...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File ".\install\windows\install.ps1" -Workspace "%~dp0"
if errorlevel 1 (
  echo.
  echo [FAILED] Install failed. Please screenshot this window and send it to the workshop host.
  pause
  exit /b 1
)

echo.
echo [OK] Installed and started.
echo Memory file:
echo %~dp0activity2context\memory.md
echo.
echo Next:
echo 1) Open OpenClaw
echo 2) Ensure hook path includes activity2context/memory.md
echo 3) Send a test message and verify context injection
echo.
pause

