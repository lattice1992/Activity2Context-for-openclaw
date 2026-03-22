@echo off
setlocal

set "CTL=%USERPROFILE%\.activity2context\activity2context.cmd"
if not exist "%CTL%" (
  echo.
  echo [MISSING] Runtime is not installed yet.
  echo Please run easy-install-windows.bat first.
  echo.
  pause
  exit /b 1
)

echo.
echo [Activity2Context] Runtime status
echo.
call "%CTL%" status
echo.
echo Memory file:
echo %~dp0activity2context\memory.md
echo.
pause

