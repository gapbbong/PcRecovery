@echo off
rem Usage: 1_Student_SetupAll.bat [student account, default student] [freeze]
rem   Default: setup only (no freeze). Add 'freeze' as 2nd arg to also enable freeze automatically.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)
set FZ=
if /i "%~2"=="freeze" set FZ=-Freeze
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-All.ps1" %FZ%
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-All.ps1" -StudentUser %1 %FZ%
)
pause
