@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "POWERSHELL_SCRIPT=%SCRIPT_DIR%SystemFilesCheck.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%POWERSHELL_EXE%" (
    set "POWERSHELL_EXE=powershell.exe"
)

if not exist "%POWERSHELL_SCRIPT%" (
    echo ERROR: Missing PowerShell implementation: "%POWERSHELL_SCRIPT%"
    exit /b 40
)

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%POWERSHELL_SCRIPT%" %*
set "RC=%ERRORLEVEL%"
exit /b %RC%
