@echo off
rem Usage: Setup-Student.bat <teacher PC IP>   e.g. Setup-Student.bat 192.168.0.100
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%1' -Verb RunAs"
    exit /b
)
if "%1"=="" (
    echo Usage: Setup-Student.bat TEACHER_IP
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Student.ps1" -TeacherIp %1
pause
