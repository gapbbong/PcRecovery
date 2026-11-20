#Requires -RunAsAdministrator
# 학생(실습실) PC 1회 설정: 교사용 PC 의 원격 제어만 허용하도록 WinRM 구성
param(
    [Parameter(Mandatory)][string]$TeacherIp
)
$ErrorActionPreference = 'Stop'

Write-Output 'WinRM 활성화...'
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
Set-Service -Name WinRM -StartupType Automatic

# 워크그룹의 로컬 관리자 계정으로 원격 관리가 가능하도록 UAC 원격 토큰 필터 해제
& reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f | Out-Null

# WinRM(5985) 인바운드를 교사용 PC IP 로만 제한
$rules = Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue
foreach ($r in $rules) { Set-NetFirewallRule -Name $r.Name -RemoteAddress $TeacherIp -Enabled True -Profile Any }
Write-Output ("방화벽 규칙 {0}개를 {1} 로 제한했습니다." -f @($rules).Count, $TeacherIp)

# 같은 폴더에 UpdateGuard.ps1 이 있으면 상시 감시도 바로 설치
$guard = Join-Path $PSScriptRoot 'UpdateGuard.ps1'
if (Test-Path $guard) {
    Write-Output '업데이트 상시 감시 설치...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $guard -Install
}
Write-Output '설정 완료.'
