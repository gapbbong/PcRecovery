@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)
set OUT=%~dp0Check-Freeze-%COMPUTERNAME%.txt
(
 echo ===== SetupAll.log =====
 type C:\ProgramData\PcRecovery\SetupAll.log
 echo ===== UWF feature state =====
 powershell -NoProfile -Command "Get-WindowsOptionalFeature -Online -FeatureName Client-UnifiedWriteFilter | Format-List FeatureName,State"
 echo ===== Stage2 task =====
 schtasks /query /tn PcRecovery-SetupAll-Stage2
 echo ===== Freeze status =====
 powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\PcRecovery\Freeze.ps1 Status
) > "%OUT%" 2>&1
type "%OUT%"
echo.
echo Saved: %OUT%
pause
