#Requires -RunAsAdministrator
# 학생(실습실) PC 1회 설정 - 이 PC 에 다시 방문하지 않아도 되도록 필요한 것을 한 번에 구성
#   -TeacherIp 를 생략하면 같은 서브넷(LocalSubnet)에서의 접속을 허용합니다 (교사용 PC IP 가 바뀌어도 재방문 불필요).
param(
    [string]$TeacherIp = ''
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
