@echo off
setlocal

set "MEM=%~dp0activity2context\memory.md"
if not exist "%MEM%" (
  echo.
  echo [MISSING] memory.md not found yet.
  echo Wait 1-2 minutes after install/start, then try again.
  echo Expected path:
  echo %MEM%
  echo.
  pause
  exit /b 1
)

echo.
echo [Activity2Context] Opening memory.md...
echo.
start "" notepad "%MEM%"

