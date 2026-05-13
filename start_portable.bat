@echo off
setlocal EnableDelayedExpansion
title ClaudeMeter
cd /d "%~dp0"

:: ── Skip if server already running on port 7842 ───────────────────────────────
netstat -an 2>nul | findstr /C:":7842 " >nul 2>&1
if not errorlevel 1 goto :open

:: ── Launch server using the bundled Python (no console window) ───────────────
set "PYTHONPATH=%~dp0lib"
start "" /B "%~dp0python\pythonw.exe" "%~dp0server.py"

:: ── Wait up to 15 s for the server to accept connections ─────────────────────
set /a T=0
:wait
if !T! geq 15 (
    echo [ERROR] Server did not start within 15 seconds.
    pause & exit /b 1
)
timeout /t 1 /nobreak >nul
powershell -NoProfile -Command ^
    "try{(New-Object Net.WebClient).DownloadString('http://localhost:7842/api/status')|Out-Null;exit 0}catch{exit 1}" >nul 2>&1
if not errorlevel 1 goto :open
set /a T+=1
goto :wait

:: ── Open dashboard in default browser ────────────────────────────────────────
:open
start http://localhost:7842

:: ── System tray balloon notification (best-effort, silent on failure) ─────────
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
