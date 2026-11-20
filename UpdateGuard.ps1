#Requires -RunAsAdministrator
<#
  Windows Update 상시 감시(가드)
    (인자 없음)  차단 요소를 찾아 즉시 복구
    -Check       점검만 (변경 없음)
    -Install     C:\ProgramData\PcRecovery 로 복사 후 작업 스케줄러에 등록 (시작/로그온/1시간마다, SYSTEM)
    -Uninstall   작업 스케줄러 등록 해제
#>
param(
    [switch]$Check,
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Continue'
$Root      = Join-Path $env:ProgramData 'PcRecovery'
$LogDir    = Join-Path $Root 'logs'
$BackupDir = Join-Path $Root 'backup'
$TaskName  = 'PcRecovery-UpdateGuard'
$Self      = Join-Path $Root 'UpdateGuard.ps1'
foreach ($d in $Root, $LogDir, $BackupDir) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

$script:Apply = -not $Check
$script:Found = 0

function Log([string]$msg) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $msg
    if ($script:Apply) { try { Add-Content -Path (Join-Path $LogDir 'updateguard.log') -Value $line -Encoding UTF8 } catch {} }
    Write-Output $line
}

function Backup-Key([string]$regPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $file = Join-Path $BackupDir ("{0}-{1}.reg" -f ($regPath -replace '[\\:]', '_'), $stamp)
    & reg.exe export $regPath $file /y 2>&1 | Out-Null
}

# $bad = $null 이면 값이 존재하는 것 자체가 차단 요소
function Remove-Blocker([string]$path, [string]$name, $bad) {
    $p = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $p) { return }
    $val = $p.$name
    if ($null -ne $bad -and $val -ne $bad) { return }
    $script:Found++
    if ($script:Apply) {
        try { Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction Stop; Log "[복구] $path\$name ($val) 제거" }
        catch { Log "[실패] $path\$name 제거 불가: $_" }
    } else { Log "[발견] $path\$name = $val" }
}

function Invoke-Guard {
    $domain = $false
    try { $domain = [bool](Get-CimInstance Win32_ComputerSystem).PartOfDomain } catch {}
    Log ("업데이트 가드 시작 (모드: {0}, 도메인 가입: {1})" -f $(if ($script:Apply) { '복구' } else { '점검' }), $domain)

    # 1) 서비스: 비활성화(Disabled)된 것만 기본 시작 유형으로 되돌리고 필요한 것은 시작
    $services = @(
        @{ Name = 'wuauserv';        Mode = 'Manual';    Run = $true  },
        @{ Name = 'UsoSvc';          Mode = 'Automatic'; Run = $true  },
        @{ Name = 'BITS';            Mode = 'Manual';    Run = $false },
        @{ Name = 'cryptsvc';        Mode = 'Automatic'; Run = $true  },
        @{ Name = 'TrustedInstaller'; Mode = 'Manual';   Run = $false }
    )
    foreach ($s in $services) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$($s.Name)'" -ErrorAction SilentlyContinue
        if (-not $svc) { Log "[경고] 서비스 없음: $($s.Name)"; continue }
        if ($svc.StartMode -eq 'Disabled') {
            $script:Found++
            if ($script:Apply) {
                try { Set-Service -Name $s.Name -StartupType $s.Mode -ErrorAction Stop; Log "[복구] 서비스 $($s.Name) 비활성화 해제 -> $($s.Mode)" }
                catch { Log "[실패] 서비스 $($s.Name): $_" }
            } else { Log "[발견] 서비스 $($s.Name) 비활성화됨" }
        }
        if ($script:Apply -and $s.Run -and $svc.State -ne 'Running') {
            try { Start-Service -Name $s.Name -ErrorAction Stop; Log "[복구] 서비스 $($s.Name) 시작" } catch { Log "[참고] 서비스 $($s.Name) 시작 안 됨: $($_.Exception.Message)" }
        }
    }
    $medic = Get-CimInstance Win32_Service -Filter "Name='WaaSMedicSvc'" -ErrorAction SilentlyContinue
    if ($medic -and $medic.StartMode -eq 'Disabled') { Log '[경고] WaaSMedicSvc 가 비활성화됨 (보호된 서비스라 자동 복구 불가, DISM/SFC 복구 권장)' }

    # 2) 정책/레지스트리 차단 요소 (도메인 환경에서는 조직 정책이므로 건드리지 않음)
    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $au = "$wu\AU"
    $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    if ($domain) {
        Log '[참고] 도메인 가입 PC: 조직 그룹 정책(WSUS/지연/차단)은 변경하지 않습니다.'
    } else {
        if ($script:Apply -and (Test-Path $wu)) { Backup-Key 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' }
        if (Test-Path $wu) {
            Remove-Blocker $wu 'DisableWindowsUpdateAccess' 1
            Remove-Blocker $wu 'DoNotConnectToWindowsUpdateInternetLocations' 1
            foreach ($n in 'DeferFeatureUpdates', 'DeferQualityUpdates', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime') { Remove-Blocker $wu $n $null }
            foreach ($n in 'WUServer', 'WUStatusServer') { Remove-Blocker $wu $n $null }
        }
        if (Test-Path $au) {
            Remove-Blocker $au 'NoAutoUpdate' 1
            Remove-Blocker $au 'AUOptions' 1
            Remove-Blocker $au 'UseWUServer' 1
        }
        if (Test-Path $ux) {
            foreach ($n in 'PauseUpdatesExpiryTime', 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime') { Remove-Blocker $ux $n $null }
        }
    }

    # 3) 업데이트 오케스트레이터 예약 작업
    $taskNames = 'Schedule Scan', 'Schedule Scan Static Task', 'USO_UxBroker', 'UpdateModelTask', 'Schedule Work'
    foreach ($t in Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\' -ErrorAction SilentlyContinue) {
        if ($t.State -eq 'Disabled' -and $taskNames -contains $t.TaskName) {
            $script:Found++
            if ($script:Apply) {
                try { Enable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null; Log "[복구] 예약 작업 활성화: $($t.TaskName)" }
                catch { Log "[실패] 예약 작업 $($t.TaskName): $($_.Exception.Message)" }
            } else { Log "[발견] 예약 작업 비활성화됨: $($t.TaskName)" }
        }
    }

    # 4) hosts 파일로 업데이트 서버를 막아둔 경우 (자동 수정하지 않고 알림만)
    $hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $blocked = Select-String -Path $hosts -Pattern '^\s*[^#\s]+\s+.*(windowsupdate|update\.microsoft|delivery\.mp\.microsoft)' -ErrorAction SilentlyContinue
    foreach ($b in $blocked) { Log "[경고] hosts 파일에서 업데이트 서버 항목 발견: $($b.Line.Trim()) (직접 확인 필요)" }

    Log ("완료: 차단 요소 {0}건 {1}" -f $script:Found, $(if ($script:Apply) { '처리' } else { '발견' }))
}

function Install-Guard {
    if ($PSCommandPath -and ($PSCommandPath -ne $Self)) { Copy-Item -Path $PSCommandPath -Destination $Self -Force }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`""
    $triggers = @(
        (New-ScheduledTaskTrigger -AtStartup),
        (New-ScheduledTaskTrigger -AtLogOn),
        (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650))
    )
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
    Log "상시 감시 등록 완료 (작업: $TaskName, 시작/로그온/1시간마다)"
    Invoke-Guard
}

function Uninstall-Guard {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Log '상시 감시 등록 해제 완료'
    } else { Log '등록된 상시 감시가 없습니다.' }
}

if ($Install)        { Install-Guard }
elseif ($Uninstall)  { Uninstall-Guard }
else                 { Invoke-Guard }
