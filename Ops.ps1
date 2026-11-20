# 로컬/원격 공통 작업 정의 (PcRecovery.ps1, Teacher.ps1 에서 dot-source)
# ---- 백그라운드 작업에서 공통으로 쓰는 함수 ----
$common = @'
$ErrorActionPreference = 'Continue'
$global:rpOk = $false
function New-RP([string]$desc) {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $name = 'SystemRestorePointCreationFrequency'
    $old = (Get-ItemProperty $k -Name $name -ErrorAction SilentlyContinue).$name
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Set-ItemProperty -Path $k -Name $name -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        "복원 지점 생성 완료: $desc"
        $global:rpOk = $true
    } catch {
        "복원 지점 생성 실패: $($_.Exception.Message)"
    } finally {
        if ($null -eq $old) { Remove-ItemProperty -Path $k -Name $name -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $k -Name $name -Value $old -Type DWord -ErrorAction SilentlyContinue }
    }
}
function Backup-Registry {
    $dir = Join-Path $env:ProgramData 'PcRecovery\backup'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($k in 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'HKLM\SOFTWARE\Microsoft\WindowsUpdate', 'HKLM\SYSTEM\CurrentControlSet\Services\wuauserv') {
        $f = Join-Path $dir ("{0}-{1}.reg" -f ($k -replace '[\\:]', '_'), $stamp)
        & reg.exe export $k $f /y 2>&1 | Out-Null
        if (Test-Path $f) { "레지스트리 백업: $f" }
    }
}
function Run-Native([string]$exe, [string]$arguments) {
    & $exe ($arguments -split ' ') 2>&1 | ForEach-Object { "$_" -replace "`0", '' } | Where-Object { $_.Trim() }
    "(종료 코드: $LASTEXITCODE)"
}
'@

# ---- 작업 본문 ----
$opDiag = @'
"[1] Windows Update 차단 요소 점검"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $args[0] -Check 2>&1 | ForEach-Object { "$_" }
""
"[2] 재부팅 대기 상태"
$pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
           (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($pending) { "재부팅 대기 중입니다." } else { "재부팅 대기 없음" }
""
"[3] 디스크 여유 공간"
Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Free } | ForEach-Object { "{0}: 여유 {1:N1} GB / 전체 {2:N1} GB" -f $_.Name, ($_.Free / 1GB), (($_.Free + $_.Used) / 1GB) }
""
"[4] 구성 요소 저장소 빠른 검사 (DISM /CheckHealth)"
Run-Native 'dism.exe' '/Online /Cleanup-Image /CheckHealth'
'@

$opRestore = @'
New-RP "PcRecovery 수동 복원 지점"
Backup-Registry
'@

$opRepair = @'
New-RP "PcRecovery 시스템 복구 전"
if (-not $global:rpOk) { "복원 지점이 없어 안전을 위해 중단합니다."; return }
Backup-Registry
""
"DISM /RestoreHealth 실행 중... (수 분~수십 분 걸릴 수 있습니다)"
Run-Native 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
""
"SFC /scannow 실행 중..."
Run-Native 'sfc.exe' '/scannow'
""
"완료. 상세 로그: $env:windir\Logs\CBS\CBS.log"
'@

$opChkdsk = @'
New-RP "PcRecovery 디스크 검사 예약 전"
if (-not $global:rpOk) { "복원 지점이 없어 안전을 위해 중단합니다."; return }
"다음 재부팅 시 $env:SystemDrive 디스크 검사(chkdsk /f /r)를 예약합니다."
cmd.exe /c "echo Y| chkdsk $env:SystemDrive /f /r" 2>&1 | ForEach-Object { "$_" -replace "`0", '' } | Where-Object { $_.Trim() }
"예약 완료. 재부팅하면 검사가 시작됩니다."
'@

$opGuardInstall   = '& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $args[0] -Install 2>&1 | ForEach-Object { "$_" }'
$opGuardRun       = '& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $args[0] 2>&1 | ForEach-Object { "$_" }'
$opGuardUninstall = '& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $args[0] -Uninstall 2>&1 | ForEach-Object { "$_" }'
$opScan = @'
"Windows Update 검색을 요청합니다."
Start-Service UsoSvc -ErrorAction SilentlyContinue
Run-Native 'UsoClient.exe' 'StartScan'
"백그라운드에서 검색됩니다. 설정 > Windows 업데이트에서 결과를 확인하세요."
'@

