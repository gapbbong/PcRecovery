@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)
echo === Fix remote access for teacher console (account labadmin / password 1211) ===
net accounts /minpwlen:0 >nul 2>&1
net user User 1211
net user User /active:yes >nul 2>&1
net user labadmin 1211 /add /y >nul 2>&1
net user labadmin 1211 >nul 2>&1
net user labadmin /active:yes >nul 2>&1
net localgroup Administrators labadmin /add >nul 2>&1
wmic useraccount where name='labadmin' set PasswordExpires=false >nul 2>&1
net localgroup Administrators User /add >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f >nul
powershell -NoProfile -Command "Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null; Set-Service WinRM -StartupType Automatic; Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' | Set-NetFirewallRule -Enabled True -Profile Any -RemoteAddress LocalSubnet"
echo.
echo --- Result ---
echo [Administrators group]
net localgroup Administrators | findstr /i "User Administrator"
echo [LocalAccountTokenFilterPolicy]
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy | findstr /i Token
echo [WinRM]
powershell -NoProfile -Command "(Get-Service WinRM).Status"
echo [Set: network profile Private + WinRM Basic/unencrypted for lab LAN]
powershell -NoProfile -Command "Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private; Set-Item WSMan:\localhost\Service\AllowUnencrypted $true; Set-Item WSMan:\localhost\Service\Auth\Basic $true; Get-NetConnectionProfile | Select Name,NetworkCategory; (Get-Item WSMan:\localhost\Service\AllowUnencrypted).Value; (Get-Item WSMan:\localhost\Service\Auth\Basic).Value"
echo [Check: is password 1211 valid for User on this PC?]
powershell -NoProfile -Command "Add-Type -AssemblyName System.DirectoryServices.AccountManagement; $p=New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Machine'); 'ValidateCredentials User/1211 = ' + $p.ValidateCredentials('User','1211')"
echo [Check: account lockout / status]
powershell -NoProfile -Command "$u=([ADSI]'WinNT://./User,user'); 'IsAccountLocked=' + $u.IsAccountLocked + '  AccountDisabled=' + $u.AccountDisabled"
net user User | findstr /i "Account active Password last"
echo [Check: SeDenyNetworkLogonRight]
powershell -NoProfile -Command "secedit /export /cfg $env:TEMP\sec.inf /areas USER_RIGHTS | Out-Null; (Select-String $env:TEMP\sec.inf -Pattern 'SeDenyNetworkLogonRight','SeNetworkLogonRight').Line"
echo [Check: NTLM incoming restriction (blank/0 = allowed)]
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" /v RestrictReceivingNTLMTraffic 2>nul | findstr /i Restrict
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LmCompatibilityLevel 2>nul | findstr /i Lm
echo [Check: last failed logons (Security 4625) - reason codes]
powershell -NoProfile -Command "try{Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -MaxEvents 3 -ErrorAction Stop | ForEach-Object { $x=[xml]$_.ToXml(); $d=@{}; $x.Event.EventData.Data | ForEach-Object { $d[$_.Name]=$_.'#text' }; '{0} user={1} ip={2} status={3} sub={4} type={5} auth={6}' -f $_.TimeCreated.ToString('HH:mm:ss'),$d.TargetUserName,$d.IpAddress,$d.Status,$d.SubStatus,$d.LogonType,$d.AuthenticationPackageName }}catch{'no 4625 events: '+$_.Exception.Message}"
echo [Check: loopback WinRM with User/1211]
powershell -NoProfile -Command "$c=New-Object PSCredential('.\User',(ConvertTo-SecureString '1211' -AsPlainText -Force)); try{Invoke-Command -ComputerName localhost -Credential $c -ScriptBlock {whoami} -ErrorAction Stop}catch{'loopback ERR: '+$_.Exception.Message}"
echo [Protection state - if ON, these fixes are lost at reboot. Run 3_Student_ProtectOff.bat first]
if exist "%~dp0Freeze.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Freeze.ps1" Status
echo.
echo Done. Now test on the teacher PC.
pause