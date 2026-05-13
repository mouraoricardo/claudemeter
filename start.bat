@echo off
setlocal EnableDelayedExpansion
title ClaudeMeter
cd /d "%~dp0"

:: ── 1. Python check ───────────────────────────────────────────────────────────
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found.
    echo Download from: https://www.python.org/downloads/
    pause & exit /b 1
)
python -c "import sys;exit(0 if sys.version_info>=(3,8) else 1)" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python 3.8 or higher is required.
    pause & exit /b 1
)

:: ── 2. Install dependencies if missing ───────────────────────────────────────
python -c "import flask,requests" >nul 2>&1
if errorlevel 1 (
    echo Installing dependencies...
    python -m pip install -r requirements.txt --quiet
    if errorlevel 1 (
        echo [ERROR] pip install failed. Check your internet connection.
        pause & exit /b 1
    )
    echo Done.
)

:: ── 3. Skip launch if server already running on port 7842 ────────────────────
netstat -an 2>nul | findstr /C:":7842 " >nul 2>&1
if not errorlevel 1 (
    echo ClaudeMeter is already running on port 7842.
    echo Opening dashboard...
    goto :open
)

:: ── 4. Launch server in a hidden window ──────────────────────────────────────
::    Try pythonw.exe first (no console, default Python for Windows install).
::    Fall back to VBScript shell trick for custom/conda environments.
where pythonw >nul 2>&1
if not errorlevel 1 (
    start "" /B pythonw "%~dp0server.py"
    goto :wait
)

set "VBS=%TEMP%\cm%RANDOM%.vbs"
echo Set sh = CreateObject("WScript.Shell")    > "!VBS!"
echo sh.Run "python ""%~dp0server.py""", 0, False >> "!VBS!"
cscript //nologo "!VBS!"
del /q "!VBS!" 2>nul

:: ── 5. Wait up to 15 s for server to accept connections ──────────────────────
:wait
set /a T=0
:wait_loop
if !T! geq 15 (
    echo [ERROR] Server did not start within 15 seconds.
    echo Check Task Manager for a Python process, or run server.py manually.
    pause & exit /b 1
)
timeout /t 1 /nobreak >nul
powershell -NoProfile -Command ^
  "try{(New-Object Net.WebClient).DownloadString('http://localhost:7842/api/status')|Out-Null;exit 0}catch{exit 1}" >nul 2>&1
if not errorlevel 1 goto :open
set /a T+=1
goto :wait_loop

:: ── 6. Open dashboard in default browser ─────────────────────────────────────
:open
start http://localhost:7842

:: ── 7. System tray balloon notification (best-effort, silent on failure) ──────
set "PS1=%TEMP%\cm_notify_%RANDOM%.ps1"
echo Add-Type -AssemblyName System.Windows.Forms                                       > "%PS1%"
echo $n = New-Object System.Windows.Forms.NotifyIcon                                  >> "%PS1%"
echo $n.Icon = [System.Drawing.SystemIcons]::Application                              >> "%PS1%"
echo $n.Visible = $true                                                                >> "%PS1%"
echo $n.ShowBalloonTip(3000,'ClaudeMeter','Claude Usage Monitor started',[System.Windows.Forms.ToolTipIcon]::Info) >> "%PS1%"
echo Start-Sleep -Milliseconds 4500                                                    >> "%PS1%"
echo $n.Dispose()                                                                      >> "%PS1%"
start "" /B powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%"

endlocal
