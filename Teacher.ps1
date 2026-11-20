#Requires -RunAsAdministrator
# 교사용 PC 제어 콘솔 - hosts.csv 의 실습실 PC 에 WinRM 으로 복구/업데이트 작업을 일괄 실행
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Ops.ps1')

$HostsCsv    = Join-Path $PSScriptRoot 'hosts.csv'
$LocalGuard  = Join-Path $PSScriptRoot 'UpdateGuard.ps1'
$RemoteGuard = 'C:\ProgramData\PcRecovery\UpdateGuard.ps1'
$LogDir      = Join-Path $env:ProgramData 'PcRecovery\logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile     = Join-Path $LogDir ("teacher-{0:yyyyMMdd}.log" -f (Get-Date))

$script:cred = $null
$script:jobs = New-Object System.Collections.ArrayList
$script:buttons = @()

$form = New-Object System.Windows.Forms.Form
$form.Text = '실습실 PC 제어 (교사용)'
$form.Size = New-Object System.Drawing.Size(1050, 720)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Top'; $grid.Height = 300
$grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false; $grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'; $grid.BackgroundColor = 'White'
$colSel = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colSel.HeaderText = '선택'; $colSel.FillWeight = 8
[void]$grid.Columns.Add($colSel)
foreach ($c in @(@('자리', 10), @('이름', 18), @('주소', 20), @('상태', 44))) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.HeaderText = $c[0]; $col.FillWeight = $c[1]; $col.ReadOnly = $true
    [void]$grid.Columns.Add($col)
}

$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Top'; $panel.Height = 120; $panel.Padding = New-Object System.Windows.Forms.Padding(6)

$log = New-Object System.Windows.Forms.RichTextBox
$log.Dock = 'Fill'; $log.ReadOnly = $true; $log.BackColor = 'White'
$log.Font = New-Object System.Drawing.Font('Consolas', 9)

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = '대기 중'
[void]$status.Items.Add($statusLabel)

$form.Controls.Add($log)
$form.Controls.Add($panel)
$form.Controls.Add($grid)
$form.Controls.Add($status)

function Write-Log([string]$text) {
    $log.AppendText($text + [Environment]::NewLine)
    $log.ScrollToCaret()
    try { Add-Content -Path $LogFile -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $text) -Encoding UTF8 } catch {}
}

function Confirm-Action([string]$msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, '실습실 PC 제어', 'YesNo', 'Warning') -eq 'Yes'
}

function Load-Hosts {
    $grid.Rows.Clear()
    if (-not (Test-Path $HostsCsv)) { Write-Log "hosts.csv 가 없습니다: $HostsCsv"; return }
    foreach ($h in Import-Csv -Path $HostsCsv -Encoding UTF8) {
        if (-not $h.Address) { continue }
        $i = $grid.Rows.Add($true, $h.Seat, $h.Name, $h.Address, '-')
        $grid.Rows[$i].Tag = $h.Mac
    }
    Write-Log ("hosts.csv 에서 {0}대를 불러왔습니다." -f $grid.Rows.Count)
}

function Get-Cred {
    if (-not $script:cred) {
        $script:cred = Get-Credential -UserName '.\Administrator' -Message '학생 PC 의 로컬 관리자 계정 (예: .\Administrator)'
    }
    $script:cred
}

function Get-Selected { @($grid.Rows | Where-Object { $_.Cells[0].Value -eq $true }) }

function Set-Busy([bool]$busy) {
    foreach ($b in $script:buttons) { $b.Enabled = -not $busy }
    $grid.Enabled = -not $busy
}

function Start-Remote([string]$title, [string]$body, [object[]]$argList, [string]$confirmMsg = '') {
    if ($script:jobs.Count -gt 0) { return }
    $rows = Get-Selected
    if ($rows.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('대상 PC 를 선택하세요.'); return }
    if ($confirmMsg -and -not (Confirm-Action ("{0}`n`n대상: {1}대" -f $confirmMsg, $rows.Count))) { return }
    $cred = Get-Cred
    if (-not $cred) { return }
    $sb = [scriptblock]::Create($common + "`n" + $body)
    $opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 7200000 -NoMachineProfile
    Write-Log ''
    Write-Log ("=== {0} ({1}대, {2:HH:mm:ss}) ===" -f $title, $rows.Count, (Get-Date))
    $statusLabel.Text = "$title 실행 중..."
    Set-Busy $true
    foreach ($r in $rows) {
        $r.Cells[4].Value = '실행 중...'
        $j = Invoke-Command -ComputerName $r.Cells[3].Value -Credential $cred -SessionOption $opt -ScriptBlock $sb -ArgumentList $argList -AsJob
        [void]$script:jobs.Add(@{ Job = $j; Row = $r; Tag = "[{0}]" -f $(if ($r.Cells[1].Value) { $r.Cells[1].Value } else { $r.Cells[2].Value }) })
    }
    $timer.Start()
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
    foreach ($e in @($script:jobs)) {
        $j = $e.Job
        Receive-Job $j -ErrorAction SilentlyContinue | ForEach-Object { Write-Log ("{0} {1}" -f $e.Tag, ("$_" -replace "`0", '')) }
        if ($j.State -eq 'Running' -or $j.State -eq 'NotStarted') { continue }
        Receive-Job $j -ErrorAction SilentlyContinue | ForEach-Object { Write-Log ("{0} {1}" -f $e.Tag, ("$_" -replace "`0", '')) }
        if ($j.State -eq 'Completed') {
            $e.Row.Cells[4].Value = '완료 ({0:HH:mm:ss})' -f (Get-Date)
        } else {
            $reason = ''
            try { $reason = $j.ChildJobs[0].JobStateInfo.Reason.Message } catch {}
            $e.Row.Cells[4].Value = "실패: $reason"
            Write-Log ("{0} 실패: {1}" -f $e.Tag, $reason)
        }
        Remove-Job $j -Force
        $script:jobs.Remove($e)
    }
    if ($script:jobs.Count -eq 0) {
        $timer.Stop(); Set-Busy $false
        $statusLabel.Text = '완료'
        Write-Log '--- 모든 대상 종료 ---'
    }
})

function Add-Button([string]$text, [scriptblock]$onClick, [bool]$lockable = $true) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Size = New-Object System.Drawing.Size(190, 30)
    $b.Margin = New-Object System.Windows.Forms.Padding(3)
    $b.Add_Click($onClick)
    $panel.Controls.Add($b)
    if ($lockable) { $script:buttons += $b }
}

$guardArg = $RemoteGuard

Add-Button '전체 선택'       { foreach ($r in $grid.Rows) { $r.Cells[0].Value = $true } }
Add-Button '전체 해제'       { foreach ($r in $grid.Rows) { $r.Cells[0].Value = $false } }
Add-Button 'hosts.csv 새로고침' { Load-Hosts }
Add-Button '1. 진단 (읽기 전용)' { Start-Remote '진단' $opDiag @($guardArg) }
Add-Button '2. 가드 배포/갱신 + 상시감시' {
    if (-not (Test-Path $LocalGuard)) { Write-Log "UpdateGuard.ps1 없음: $LocalGuard"; return }
    $text = [IO.File]::ReadAllText($LocalGuard)
    $body = @'
$text = $args[0]
$dir = Join-Path $env:ProgramData 'PcRecovery'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$p = Join-Path $dir 'UpdateGuard.ps1'
[IO.File]::WriteAllText($p, $text, (New-Object Text.UTF8Encoding $true))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -Install 2>&1 | ForEach-Object { "$_" }
'@
    Start-Remote '가드 배포/상시감시 설치' $body @($text) '선택한 PC 에 업데이트 가드를 배포하고 상시 감시(시작/로그온/1시간마다)를 등록합니다.'
}
Add-Button '3. 업데이트 지금 복구'   { Start-Remote '업데이트 지금 복구' $opGuardRun @($guardArg) }
Add-Button '4. 업데이트 검색 시작'   { Start-Remote '업데이트 검색' $opScan @($guardArg) }
Add-Button '5. 복원 지점 + 백업'     { Start-Remote '복원 지점/백업' $opRestore @($guardArg) '선택한 PC 에 복원 지점을 만들고 레지스트리를 백업합니다.' }
Add-Button '6. 시스템 파일 복구'     { Start-Remote '시스템 파일 복구' $opRepair @($guardArg) '선택한 PC 에서 복원 지점 생성 후 DISM+SFC 를 실행합니다. PC당 수십 분 걸릴 수 있고 인터넷 연결이 필요합니다.' }
Add-Button '7. 디스크 검사 예약'     { Start-Remote '디스크 검사 예약' $opChkdsk @($guardArg) '선택한 PC 에서 다음 재부팅 때 chkdsk /f /r 를 실행하도록 예약합니다.' }
Add-Button '8. 상시 감시 해제'       { Start-Remote '상시 감시 해제' $opGuardUninstall @($guardArg) '선택한 PC 의 상시 감시를 해제합니다.' }
Add-Button '재부팅 (60초 예고)' {
    Start-Remote '재부팅' '& shutdown.exe /r /t 60 /c "실습실 관리: 1분 후 재부팅됩니다. 작업을 저장하세요."; "60초 후 재부팅 예약됨"' @() '선택한 PC 를 60초 후 재부팅합니다.'
}
Add-Button '종료 (60초 예고)' {
    Start-Remote '종료' '& shutdown.exe /s /t 60 /c "실습실 관리: 1분 후 종료됩니다. 작업을 저장하세요."; "60초 후 종료 예약됨"' @() '선택한 PC 를 60초 후 종료합니다.'
}
Add-Button '재부팅/종료 예약 취소' { Start-Remote '예약 취소' '& shutdown.exe /a 2>&1 | ForEach-Object { "$_" }' @() }
Add-Button '전원 켜기 (WoL)' {
    $n = 0
    foreach ($r in Get-Selected) {
        $mac = "$($r.Tag)" -replace '[^0-9A-Fa-f]', ''
        if ($mac.Length -ne 12) { $r.Cells[4].Value = 'MAC 없음'; continue }
        $bytes = [byte[]](,0xFF * 6) + ([byte[]]($mac -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }) * 16)
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.EnableBroadcast = $true
        [void]$udp.Send($bytes, $bytes.Length, '255.255.255.255', 9)
        $udp.Close()
        $r.Cells[4].Value = 'WoL 전송'; $n++
    }
    Write-Log "WoL 패킷 전송: $n 대 (BIOS 에서 Wake-on-LAN 이 켜져 있어야 합니다)"
} $false
Add-Button '자격 증명 다시 입력' { $script:cred = $null; [void](Get-Cred) } $false
Add-Button '로그 폴더 열기' { Start-Process explorer.exe $LogDir } $false

$form.Add_FormClosing({
    if ($script:jobs.Count -gt 0) {
        if (-not (Confirm-Action '작업이 진행 중입니다. 창을 닫으면 결과를 받을 수 없습니다. 종료할까요?')) { $_.Cancel = $true }
        else { foreach ($e in $script:jobs) { Stop-Job $e.Job -ErrorAction SilentlyContinue } }
    }
})

Load-Hosts
Write-Log '교사용 제어 콘솔 시작. 학생 PC 에는 Setup-Student.bat 으로 WinRM 설정이 먼저 되어 있어야 합니다.'
[void]$form.ShowDialog()
