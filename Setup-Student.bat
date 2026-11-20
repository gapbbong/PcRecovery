@echo off
rem Usage: Setup-Student.bat [teacher PC IP]
rem   With no argument, remote access is allowed from the local subnet.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Student.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Student.ps1" -TeacherIp %1
)
pause
