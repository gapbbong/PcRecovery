# 보호(껐다 켜면 초기화) 설정 - Windows 쓰기 필터(UWF). Enterprise/Education/IoT 에디션 전용.
# 사용: Freeze.ps1 <Action>   Action = Status | Install | Enable | Disable
#   Install : UWF 기능 설치 (재부팅 1회 필요)
#   Enable  : C: 보호 켜기 (다음 재부팅부터 적용, 이후 재부팅마다 C: 변경 내용이 사라짐)
#   Disable : 보호 해제 (다음 재부팅부터 해제 - 업데이트/설정 변경은 이 상태에서)
# Teacher.ps1 의 원격 실행(스크립트 앞에 $Action='...' 를 붙임)에서도 그대로 동작합니다.
if (-not $Action) { $Action = $args[0] }
if (-not $Action) { $Action = 'Status' }
$ErrorActionPreference = 'Stop'
$Drive = 'C:'
$OverlayMB = 4096                       # 변경 내용을 임시로 담는 공간 (디스크). 부족하면 보호 중 느려지거나 재부팅됨
$ExcludeDirs = @("$env:ProgramData\PcRecovery", "$env:ProgramData\Microsoft\Windows Defender")   # 보호에서 제외 (로그/백신 정의)

$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw '관리자 권한으로 실행하세요.' }

function Get-Uwf {
    try {
        $f = Get-CimInstance -Namespace 'root\standardcimv2\embedded' -ClassName UWF_Filter -ErrorAction Stop
        [pscustomobject]@{ Installed = $true; Now = [bool]$f.CurrentEnabled; Next = [bool]$f.NextEnabled }
    } catch { [pscustomobject]@{ Installed = $false; Now = $false; Next = $false } }
}
try { [Console]::OutputEncoding = [Text.Encoding]::Unicode } catch {}
$script:UwfFail = @()
function Uwfmgr {
    $a = @($args)
    $out = & "$env:SystemRoot\System32\uwfmgr.exe" @a 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $out | Where-Object { $_.Trim() } | ForEach-Object { "       $_" }
    if ($code -ne 0) { $script:UwfFail += ("uwfmgr {0} -> 종료코드 {1}" -f ($a -join ' '), $code); "       [실패] uwfmgr $($a -join ' ') (종료코드 $code)" }
}
function Show-State {
    $s = Get-Uwf
    if (-not $s.Installed) { Write-Output "[$env:COMPUTERNAME] UWF 미설치 (Install 필요)"; return }
    Write-Output ("[{0}] 현재 보호: {1} / 다음 재부팅 후: {2}" -f $env:COMPUTERNAME, $(if ($s.Now) { '켜짐' } else { '꺼짐' }), $(if ($s.Next) { '켜짐' } else { '꺼짐' }))
}

$edition = (Get-CimInstance Win32_OperatingSystem).Caption
if ($Action -in 'Install', 'Enable' -and $edition -notmatch 'Enterprise|Education|IoT') { throw "UWF 는 이 에디션에서 지원되지 않습니다: $edition" }

switch ($Action) {
    'Status' { Write-Output "에디션: $edition"; Show-State }
    'Install' {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName Client-UnifiedWriteFilter
        if ($feat.State -eq 'Enabled') { Write-Output 'UWF 기능은 이미 설치돼 있습니다.' }
        else {
            $r = Enable-WindowsOptionalFeature -Online -FeatureName Client-UnifiedWriteFilter -All -NoRestart
            Write-Output 'UWF 기능 설치 완료. 재부팅 후 Enable 을 실행하세요.'
            if ($r.RestartNeeded) { Write-Output '(재부팅 필요)' }
        }
    }
    'Enable' {
        if (-not (Get-Uwf).Installed) { throw 'UWF 가 아직 설치/활성화되지 않았습니다. Install 후 재부팅하고 다시 실행하세요.' }
        $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        if ($wl.AutoAdminLogon -ne '1') { throw '학생 계정 자동 로그인이 설정되지 않았습니다. Setup-Student 를 먼저 통과시키세요.' }
        if (Get-ScheduledTask -TaskName 'PcRecovery-UpdateGuard' -ErrorAction SilentlyContinue) { } else { throw '업데이트 가드가 설치되지 않았습니다. Setup-Student 를 먼저 통과시키세요.' }
        & powercfg.exe /h off | Out-Null
        Uwfmgr overlay set-type DISK
        Uwfmgr overlay set-size $OverlayMB
        Uwfmgr volume protect $Drive
        foreach ($d in $ExcludeDirs) { if (Test-Path $d) { Uwfmgr file add-exclusion $d } }
        Uwfmgr filter enable
        $s = Get-Uwf
        if (-not $s.Next) {
            # uwfmgr 가 실패했으면 CIM 으로 직접 시도
            try { Invoke-CimMethod -Namespace 'root\standardcimv2\embedded' -ClassName UWF_Filter -MethodName Enable -ErrorAction Stop | Out-Null } catch { Write-Output "       CIM Enable 실패: $($_.Exception.Message)" }
            $s = Get-Uwf
        }
        Show-State
        if (-not $s.Next) { throw ("보호 켜기 실패: 다음 재부팅 후에도 보호가 꺼져 있습니다. " + ($script:UwfFail -join '; ')) }
        Write-Output '보호 켜기 예약 완료. 재부팅하면 적용됩니다.'
    }
    'Disable' {
        if (-not (Get-Uwf).Installed) { Write-Output 'UWF 미설치: 보호 상태가 아닙니다.'; break }
        Uwfmgr filter disable
        if ((Get-Uwf).Next) { try { Invoke-CimMethod -Namespace 'root\standardcimv2\embedded' -ClassName UWF_Filter -MethodName Disable -ErrorAction Stop | Out-Null } catch {} }
        if ((Get-Uwf).Next) { throw ('보호 해제 실패: 다음 재부팅 후에도 보호가 켜져 있습니다. ' + ($script:UwfFail -join '; ')) }
        Write-Output '보호 해제 예약 완료. 재부팅하면 해제됩니다. 작업 후 Enable 하고 재부팅하세요.'
        Show-State
    }
    'Diag' {
        Write-Output "에디션: $edition   부팅시각: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
        $feat = Get-WindowsOptionalFeature -Online -FeatureName Client-UnifiedWriteFilter
        Write-Output "UWF 기능 상태: $($feat.State)"
        Show-State
        $pend = @()
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'CBS 재부팅 대기' }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'WindowsUpdate 재부팅 필요' }
        if (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) { $pend += '파일 이름 변경 대기' }
        Write-Output ("재부팅 대기 요인: " + $(if ($pend) { $pend -join ', ' } else { '없음' }))
        foreach ($cls in 'UWF_Filter', 'UWF_Overlay', 'UWF_OverlayConfig', 'UWF_Volume') {
            try { Get-CimInstance -Namespace 'root\standardcimv2\embedded' -ClassName $cls -ErrorAction Stop | ForEach-Object { Write-Output ("{0}: {1}" -f $cls, (($_.CimInstanceProperties | Where-Object { $_.Name -notmatch '^(Caption|Description|InstallDate|Name|Status)$' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')) } } catch { Write-Output "$cls 조회 실패: $($_.Exception.Message)" }
        }
        Write-Output '최근 10분 UWF/시스템 이벤트:'
        try {
            Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; StartTime = (Get-Date).AddMinutes(-15); Level = 1, 2, 3 } -MaxEvents 40 -ErrorAction Stop |
                Where-Object { $_.ProviderName -match 'uwf|UnifiedWrite|Servicing|wuauserv|Microsoft-Windows-Kernel' -or $_.Message -match 'uwf|Unified Write' } | Select-Object -First 8 |
                ForEach-Object { "{0:HH:mm:ss} [{1}] {2}" -f $_.TimeCreated, $_.ProviderName, (($_.Message -split "`n")[0]) }
        } catch { Write-Output ("이벤트 조회: " + $_.Exception.Message) }
        Write-Output ('Fast Startup(HiberbootEnabled)=' + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled + ' / 최대절전 파일=' + (Test-Path 'C:\hiberfil.sys'))
        try { Write-Output ('BitLocker: ' + ((Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop | ForEach-Object { "$($_.ProtectionStatus)/$($_.VolumeStatus)" }))) } catch { Write-Output 'BitLocker: 조회 불가' }
        Write-Output ('pagefile: ' + ((Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ',') + ' / 자동관리=' + (Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile)
        Write-Output 'uwfmgr get-config:'
        Uwfmgr get-config
        Write-Output ('UWF 서비스/드라이버: ' + ((Get-Service -Name 'uwf*' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ', '))
        Write-Output ('자동 로그인: ' + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon').AutoAdminLogon)
    }
    default { throw "알 수 없는 Action: $Action (Status | Install | Enable | Disable | Diag)" }
}