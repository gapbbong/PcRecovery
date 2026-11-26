@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Freeze.ps1" Disable
echo.
echo Protection OFF scheduled. It takes effect after reboot.
choice /c YN /t 15 /d Y /m "Reboot in 15s? (Y=now, N=later)"
if errorlevel 2 goto :eof
shutdown /r /t 5
