@echo off
setlocal EnableDelayedExpansion
title ClaudeMeter
cd /d "%~dp0"

:: ── Check if already running on port 7842 ─────────────────────────────────
netstat -an 2>nul | findstr /C:":7842 " >nul 2>&1
if not errorlevel 1 (
    echo ClaudeMeter is already running on port 7842.
    echo Opening dashboard...
    goto :open
)

:: ── Sanity check: verify packages are present ─────────────────────────────
"%~dp0python\python.exe" -c "import flask, requests" >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Required packages not found in lib\
    echo Please run build.bat again to reinstall.
    echo.
    pause & exit /b 1
)

:: ── Launch server in background (no console window) ───────────────────────
set "PYTHONPATH=%~dp0lib"
start "" /B "%~dp0python\pythonw.exe" "%~dp0server.py"

:: ── Wait up to 15s for server to accept connections ───────────────────────
set /a T=0
:wait
if !T! geq 15 (
    echo.
    echo [ERROR] Server did not start within 15 seconds.
    echo.
    echo Run this to see the error:
    echo   "%~dp0python\python.exe" "%~dp0server.py"
    echo.
    echo Common causes:
    echo   - Missing credentials: %%USERPROFILE%%\.claude\.credentials.json
    echo   - Port 7842 was just freed and is still in TIME_WAIT state
    echo.
    pause & exit /b 1
)
timeout /t 1 /nobreak >nul
powershell -NoProfile -Command ^
    "try{(New-Object Net.WebClient).DownloadString('http://localhost:7842/api/status')|Out-Null;exit 0}catch{exit 1}" >nul 2>&1
if not errorlevel 1 goto :open
set /a T+=1
goto :wait

:: ── Open dashboard ─────────────────────────────────────────────────────────
:open
start http://localhost:7842

endlocal
