@echo off
setlocal
cd /d "%~dp0"
title ClaudeMeter - Create Portable

:: ── Config (change version here if needed) ───────────────────────────────────
set PY_VER=3.12.9
set PY_PTH=python312._pth
set PY_URL=https://www.python.org/ftp/python/%PY_VER%/python-%PY_VER%-embed-amd64.zip
set GETPIP_URL=https://bootstrap.pypa.io/get-pip.py

set OUT=%~dp0dist\claudemeter
set PYDIR=%OUT%\python
set LIBDIR=%OUT%\lib

echo === ClaudeMeter - Create Portable ===
echo.

:: ── Clean ─────────────────────────────────────────────────────────────────────
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%PYDIR%" "%LIBDIR%"

:: ── [1/5] Download Python embeddable ─────────────────────────────────────────
echo [1/5] Downloading Python %PY_VER% embeddable...
set "DL_ZIP=%TEMP%\python_embed_%RANDOM%.zip"
powershell -NoProfile -Command "(New-Object Net.WebClient).DownloadFile('%PY_URL%','%DL_ZIP%')"
if errorlevel 1 (
    echo [ERROR] Download failed. Check your internet connection.
    pause & exit /b 1
)

:: ── [2/5] Extract + patch .pth ────────────────────────────────────────────────
echo [2/5] Extracting Python...
powershell -NoProfile -Command "Expand-Archive -Path '%DL_ZIP%' -DestinationPath '%PYDIR%' -Force"
del /q "%DL_ZIP%"

:: The embeddable distro has 'import site' commented out by default.
:: Uncommenting it lets pip (and --target installs) work correctly.
powershell -NoProfile -Command ^
    "(Get-Content '%PYDIR%\%PY_PTH%') -replace '#import site','import site' | Set-Content '%PYDIR%\%PY_PTH%'"

:: ── [3/5] Bootstrap pip ───────────────────────────────────────────────────────
echo [3/5] Bootstrapping pip...
set "GETPIP=%TEMP%\get-pip_%RANDOM%.py"
powershell -NoProfile -Command "(New-Object Net.WebClient).DownloadFile('%GETPIP_URL%','%GETPIP%')"
if errorlevel 1 (
    echo [ERROR] Could not download get-pip.py.
    pause & exit /b 1
)
"%PYDIR%\python.exe" "%GETPIP%" --quiet
del /q "%GETPIP%"

:: ── [4/5] Install runtime dependencies into lib\ ────────────────────────────
echo [4/5] Installing Flask and requests into lib\...
"%PYDIR%\python.exe" -m pip install flask requests ^
    --target="%LIBDIR%" ^
    --quiet ^
    --no-warn-script-location
if errorlevel 1 (
    echo [ERROR] pip install failed.
    pause & exit /b 1
)

:: ── [5/5] Copy source files + create zip ─────────────────────────────────────
echo [5/5] Packaging...
copy /y "%~dp0server.py"          "%OUT%\" >nul
copy /y "%~dp0dashboard.html"     "%OUT%\" >nul
copy /y "%~dp0start_portable.bat" "%OUT%\start.bat" >nul
copy /y "%~dp0README.md"          "%OUT%\" >nul

if exist "%~dp0claudemeter-portable.zip" del /q "%~dp0claudemeter-portable.zip"
powershell -NoProfile -Command ^
    "Compress-Archive -Path '%OUT%\*' -DestinationPath '%~dp0claudemeter-portable.zip' -Force"

echo.
echo -------------------------------------------------------
echo  Done!
echo.
echo  Folder : dist\claudemeter\
echo  Zip    : claudemeter-portable.zip
echo.
echo  Share the .zip - no Python required on target machine.
echo -------------------------------------------------------
echo.
pause
