#Requires -RunAsAdministrator
# 학생(실습실) PC 1회 설정 - 이 PC 에 다시 방문하지 않아도 되도록 필요한 것을 한 번에 구성
#   -TeacherIp 를 생략하면 같은 서브넷(LocalSubnet)에서의 접속을 허용합니다 (교사용 PC IP 가 바뀌어도 재방문 불필요).
param(
    [string]$TeacherIp = '',
    [string]$StudentUser = ''   # 자동 로그인할 학생 계정 (생략 시 관리자가 아닌 활성 계정이 1개일 때 자동 선택)
)
$ErrorActionPreference = 'Continue'
$results = [ordered]@{}
function Step([string]$name, [scriptblock]$body) {
    try { & $body; $results[$name] = $true; Write-Output "[OK]   $name" }
    catch { $results[$name] = $false; Write-Output "[실패] $name : $($_.Exception.Message)" }
}

Write-Output "== $env:COMPUTERNAME 설정 시작 =="

Step 'WinRM 원격 제어 활성화' {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
    Set-Service -Name WinRM -StartupType Automatic
    & reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f | Out-Null
}

Step '방화벽 접속 범위 제한' {
    $scope = if ($TeacherIp) { $TeacherIp } else { 'LocalSubnet' }
    $rules = Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction Stop
    foreach ($r in $rules) { Set-NetFirewallRule -Name $r.Name -RemoteAddress $scope -Enabled True -Profile Any }
    Write-Output "       허용 대상: $scope"
}

Step '원격 Wake-on-LAN/빠른 시작 해제' {
    # 빠른 시작이 켜져 있으면 종료 상태에서 WoL 이 안 되고 업데이트 적용도 불완전
    & reg.exe add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
        Set-NetAdapterPowerManagement -Name $_.Name -WakeOnMagicPacket Enabled -ErrorAction SilentlyContinue
    }
}

Step '시스템 보호 켜기 + 설치 시점 복원 지점' {
    Enable-ComputerRestore -Drive "$env:SystemDrive\"
    Checkpoint-Computer -Description 'PcRecovery 설치 시점' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
}

Step '학생 계정 자동 로그인 (바탕화면까지 바로 진입)' {
    $adminNames = @(Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object { ($_.Name -split '\\')[-1] })
    if ($StudentUser) { $u = Get-LocalUser -Name $StudentUser -ErrorAction Stop }
    else {
        $cands = @(Get-LocalUser | Where-Object { $_.Enabled -and $adminNames -notcontains $_.Name -and $_.Name -notin 'DefaultAccount', 'Guest', 'WDAGUtilityAccount' })
        if ($cands.Count -ne 1) { throw "학생 계정을 하나로 정할 수 없습니다 (후보 $($cands.Count)개). -StudentUser 로 지정하세요." }
        $u = $cands[0]
    }
    if ($adminNames -contains $u.Name) { throw "$($u.Name) 은(는) 관리자 권한 계정입니다. 학생 계정은 일반 계정이어야 합니다." }
    if ($u.PasswordRequired) { throw "$($u.Name) 은(는) 비밀번호가 설정되어 있습니다. 자동 로그인에는 비밀번호가 레지스트리에 평문 저장되므로 비밀번호 없는 학생 계정만 지원합니다." }
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty -Path $wl -Name AutoAdminLogon -Value '1' -Type String
    Set-ItemProperty -Path $wl -Name DefaultUserName -Value $u.Name -Type String
    Set-ItemProperty -Path $wl -Name DefaultDomainName -Value $env:COMPUTERNAME -Type String
    Remove-ItemProperty -Path $wl -Name DefaultPassword, AutoLogonCount -ErrorAction SilentlyContinue
    $pl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
    if (Test-Path $pl) { Set-ItemProperty -Path $pl -Name DevicePasswordLessBuildVersion -Value 0 -Type DWord }
    Write-Output "       자동 로그인 계정: $($u.Name)"
}

Step '업데이트 가드 설치 + 상시 감시' {
    $guard = Join-Path $PSScriptRoot 'UpdateGuard.ps1'
    if (-not (Test-Path $guard)) { throw 'UpdateGuard.ps1 이 같은 폴더에 없습니다.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $guard -Install | ForEach-Object { "       $_" }
    if (-not (Get-ScheduledTask -TaskName 'PcRecovery-UpdateGuard' -ErrorAction SilentlyContinue)) { throw '감시 작업이 등록되지 않았습니다.' }
}

Step '자가 점검 (WinRM 응답/방화벽)' {
    Test-WSMan -ComputerName localhost -ErrorAction Stop | Out-Null
    $off = @(Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' | Where-Object { $_.Enabled -ne 'True' })
    if ($off.Count -gt 0) { throw '방화벽 규칙이 꺼져 있습니다.' }
}

# 교사용 PC 의 hosts.csv 생성에 쓰는 정보 수집 (이름/IP/MAC/로컬 관리자 계정)
$info = 'collected'
try {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1
    $ip  = (Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 | Select-Object -First 1).IPAddress
    $mac = (Get-NetAdapter -InterfaceIndex $route.InterfaceIndex).MacAddress
    $admins = (Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.ObjectClass -eq 'User' } |
               ForEach-Object { $u = Get-LocalUser -SID $_.SID -ErrorAction SilentlyContinue; if ($u -and $u.Enabled) { $u.Name } }) -join ';'
    $row = [pscustomobject]@{ Name = $env:COMPUTERNAME; Address = $ip; Mac = $mac; Admins = $admins }
    $dir = Join-Path $PSScriptRoot $info
    try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    catch { $dir = Join-Path $env:ProgramData 'PcRecovery' }
    $row | Export-Csv -Path (Join-Path $dir "$env:COMPUTERNAME.csv") -NoTypeInformation -Encoding UTF8
    Write-Output ("수집 정보: {0} / IP {1} / MAC {2} / 관리자 계정 {3}  -> {4}" -f $row.Name, $ip, $mac, $admins, $dir)
} catch { Write-Output "수집 정보 저장 실패: $($_.Exception.Message)" }

$failed = @($results.GetEnumerator() | Where-Object { -not $_.Value })
Write-Output ''
if ($failed.Count -eq 0) {
    Write-Output '*** 모든 점검 통과: 이 PC 는 다시 방문할 필요가 없습니다. ***'
    Write-Output '(참고) BIOS 의 Wake-on-LAN 은 소프트웨어로 켤 수 없으니, 전원 켜기를 쓰려면 지금 확인하세요.'
} else {
    Write-Output ('*** 실패 항목 있음: ' + (($failed | ForEach-Object { $_.Key }) -join ', ') + ' -> 지금 해결하고 다시 실행하세요. ***')
}
