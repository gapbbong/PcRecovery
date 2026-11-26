#Requires -RunAsAdministrator
# 학생 PC 한방 설정: 학생 계정 준비 -> Setup-Student -> 보호(UWF) 설치 -> (자동 재부팅) -> 보호 켜기 -> (자동 재부팅)
# 사용: 1_Student_SetupAll.bat [학생계정명]   (기본 student). 이름 변경(Rename-Computer)은 미리 끝내 두세요.
param(
    [string]$StudentUser = 'student',
    [int]$Stage = 1,
    [switch]$Freeze          # 지정하면 설치 후 보호까지 자동 진행 (기본: 보호 안 함)
)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:ProgramData 'PcRecovery'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$log = Join-Path $dir 'SetupAll.log'
function Say([string]$m) { $l = "{0:HH:mm:ss} {1}" -f (Get-Date), $m; Write-Output $l; Add-Content -Path $log -Value $l -Encoding UTF8 }
$task = 'PcRecovery-SetupAll-Stage2'

function Stage2 {
    Say "== 2단계: 보호 켜기 ($env:COMPUTERNAME) =="
    $ErrorActionPreference = 'Continue'
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'Freeze.ps1') Enable 2>&1 | ForEach-Object { "$_" }
    $out | ForEach-Object { Say "  $_" }
    if ($out -match '예약 완료') {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
        Say '보호 켜기 완료. 재부팅하면 보호가 적용됩니다.'
        & shutdown.exe /r /t 20 /c 'PcRecovery: 보호 적용을 위해 재부팅합니다.'
    } else {
        Say '[실패] 보호 켜기 실패. 위 메시지를 확인하세요. (재부팅 때 2단계를 다시 시도합니다)'
    }
}

if ($Stage -eq 2) { Stage2; return }

Say "== 1단계: 설정 시작 ($env:COMPUTERNAME) =="

# 1) 학생 계정 (일반 계정, 비밀번호 없음)
$admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object { ($_.Name -split '\\')[-1] })
if ($admins -contains $StudentUser) { throw "$StudentUser 은(는) 관리자 계정입니다. 일반 계정 이름을 지정하세요." }
$u = Get-LocalUser -Name $StudentUser -ErrorAction SilentlyContinue
if (-not $u) {
    New-LocalUser -Name $StudentUser -NoPassword -AccountNeverExpires -Description 'PcRecovery student' | Out-Null
    Say "학생 계정 생성: $StudentUser"
} elseif ($u.PasswordRequired) {
    Set-LocalUser -Name $StudentUser -Password ([securestring]::new())
    Say "학생 계정 비밀번호 제거: $StudentUser"
}
if (-not (Get-LocalGroupMember -SID 'S-1-5-32-545' -ErrorAction SilentlyContinue | Where-Object { ($_.Name -split '\\')[-1] -eq $StudentUser })) {
    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $StudentUser
}
Enable-LocalUser -Name $StudentUser -ErrorAction SilentlyContinue

# 2) Setup-Student
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Setup-Student.ps1') -StudentUser $StudentUser 2>&1 | ForEach-Object { "$_" }
$out | ForEach-Object { Say "  $_" }
if (-not ($out -match '모든 점검 통과')) { throw 'Setup-Student 에 실패 항목이 있습니다. 위 메시지를 확인하고 해결 후 다시 실행하세요. (보호는 진행하지 않았습니다)' }

# 2-1) 로그인 때마다 뜨는 첫 로그인 안내(개인정보 선택: 위치/진단 등)와 환영 화면 끄기 - 보호 PC 에서는 매 부팅 반복되므로 필수
$null = New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name DisablePrivacyExperience -Value 1 -Type DWord
$null = New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures -Value 1 -Type DWord
$null = New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableFirstLogonAnimation -Value 0 -Type DWord
Say '첫 로그인 안내 화면 끄기 설정 완료'

# 2-2) 교사용 콘솔 접속 준비 (관리자 계정 labadmin, 네트워크 개인, WinRM Basic) - 별도로 2번 파일을 돌릴 필요 없게 함
try {
    if (-not (Get-LocalUser -Name 'labadmin' -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name 'labadmin' -Password (ConvertTo-SecureString '1211' -AsPlainText -Force) -PasswordNeverExpires -Description 'PcRecovery teacher console' | Out-Null
    } else { Set-LocalUser -Name 'labadmin' -Password (ConvertTo-SecureString '1211' -AsPlainText -Force) -PasswordNeverExpires $true }
    Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'labadmin' -ErrorAction SilentlyContinue
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
    Set-Item WSMan:\localhost\Service\AllowUnencrypted $true -ErrorAction Stop
    Set-Item WSMan:\localhost\Service\Auth\Basic $true -ErrorAction Stop
    Say '교사용 접속 준비 완료 (labadmin / Basic)'
} catch { Say "[주의] 교사용 접속 준비 실패: $($_.Exception.Message)  -> 2_Student_FixRemote.bat 을 실행하세요." }

# 3) 보호 스크립트를 PC 안에 복사 (USB 를 뽑아도 2단계 가능)
Copy-Item (Join-Path $PSScriptRoot 'Freeze.ps1') (Join-Path $dir 'Freeze.ps1') -Force
Copy-Item $PSCommandPath (Join-Path $dir 'Setup-All.ps1') -Force

# 4) 보호 기능 설치
$sf = Join-Path $dir 'Freeze.ps1'
$feat = Get-WindowsOptionalFeature -Online -FeatureName Client-UnifiedWriteFilter
$needReboot = $false
if ($feat.State -ne 'Enabled') {
    $ErrorActionPreference = 'Continue'
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sf Install 2>&1 | ForEach-Object { "$_" }
    $out | ForEach-Object { Say "  $_" }
    $needReboot = $true
}

# 5) 마무리: 보호는 기본으로 켜지 않는다 (학생 계정으로 첫 로그인을 마친 뒤 교사용 콘솔에서 켠다)
if ($needReboot -and $Freeze) {
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dir 'Setup-All.ps1')`" -Stage 2 -StudentUser $StudentUser"
    $trg = New-ScheduledTaskTrigger -AtStartup
    $pri = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    Register-ScheduledTask -TaskName $task -Action $act -Trigger $trg -Principal $pri -Force | Out-Null
    Say '보호 기능 설치됨. 20초 뒤 재부팅합니다. 재부팅 후 자동으로 보호를 켜고 한 번 더 재부팅합니다. (-Freeze)'
    & shutdown.exe /r /t 20 /c 'PcRecovery: 보호 기능 적용을 위해 재부팅합니다.'
} elseif ($Freeze) {
    Stage2
} elseif ($needReboot) {
    Say '1단계 완료. 보호 기능이 설치되어 재부팅합니다. 재부팅 후 학생 계정으로 한 번 로그인해 첫 화면 질문을 끝낸 뒤, 교사용 콘솔의 "18. 보호 켜기"를 쓰세요.'
    & shutdown.exe /r /t 10 /c 'PcRecovery: 설정 적용을 위해 재부팅합니다.'
} else {
    Say '1단계 완료. 이제 교사용 콘솔에서 "18. 보호 켜기"를 쓰면 됩니다 (학생 계정 첫 로그인을 이미 끝낸 경우).'
}