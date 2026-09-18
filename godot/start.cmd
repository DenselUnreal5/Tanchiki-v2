@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ================================================================
echo  Tanchiki -- local server
echo  Close this window to stop the server.
echo ================================================================
echo.

rem ============ Option 1: PowerShell (built into every Windows) ======
rem No Python or Node.js needed. The script starts the server,
rem picks a free port and opens the browser AFTER the server is up.
where powershell >nul 2>nul
if "!errorlevel!"=="0" (
  echo [1/1] Starting server with PowerShell...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-server.ps1"
  echo.
  echo Server stopped. Press any key to close this window.
  pause >nul
  goto :eof
)

rem ============ Option 2: py =========================================
where py >nul 2>nul
if "!errorlevel!"=="0" (
  call :run_python py
  goto :eof
)

rem ============ Option 3: python =====================================
where python >nul 2>nul
if "!errorlevel!"=="0" (
  call :run_python python
  goto :eof
)

rem ============ Option 4: npx (Node.js) ==============================
where npx >nul 2>nul
if "!errorlevel!"=="0" (
  echo [1/1] Starting server with 'npx serve' (may download on first run)...
  start "" "http://localhost:8000/"
  npx --yes serve -l 8000 .
  echo.
  echo Server stopped. Press any key to close this window.
  pause >nul
  goto :eof
)

rem ============================ Nothing found =========================
echo ERROR: PowerShell, Python and Node.js were not found on this PC.
echo PowerShell is a standard part of Windows and should be present.
pause
goto :eof

:run_python
  echo [1/1] Starting server with '%~1 -m http.server 8000' ...
  start "" "http://localhost:8000/"
  %~1 -m http.server 8000
  echo.
  echo Server stopped. Press any key to close this window.
  pause >nul
  goto :eof
