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
$script:AppVersion = 12   # Teacher.ps1 을 고칠 때마다 1 씩 올린다
$form.Text = ('실습실 PC 제어 (교사용) v{0}' -f $script:AppVersion)
$form.Size = New-Object System.Drawing.Size(1500, 900)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)

# 학생 PC 인증: NTLM(교사용 PC 의 Credential Guard 등으로 거부됨) 대신 Basic 사용 - 같은 LAN 안에서만 쓰세요
try { Set-Item WSMan:\localhost\Client\AllowUnencrypted $true -Force -ErrorAction Stop } catch {}
$cInk    = [Drawing.Color]::FromArgb(31, 41, 55)
$cMuted  = [Drawing.Color]::FromArgb(107, 114, 128)
$cAccent = [Drawing.Color]::FromArgb(37, 99, 235)
$cSide   = [Drawing.Color]::FromArgb(243, 246, 250)
$cLine   = [Drawing.Color]::FromArgb(222, 226, 232)
$form.BackColor = [Drawing.Color]::White
$form.MinimumSize = New-Object System.Drawing.Size(1100, 650)

# ---- 오른쪽: PC 목록 (위) + 로그 (아래) ----
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.AllowUserToResizeRows = $false
$grid.RowHeadersVisible = $false; $grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'; $grid.BackgroundColor = [Drawing.Color]::White
$grid.BorderStyle = 'None'; $grid.CellBorderStyle = 'SingleHorizontal'; $grid.GridColor = $cLine
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersHeight = 36; $grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
$grid.ColumnHeadersBorderStyle = 'None'
$grid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(30, 41, 59)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [Drawing.Color]::White
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [Drawing.FontStyle]::Bold)
$grid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$grid.DefaultCellStyle.ForeColor = $cInk
$grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(219, 234, 254)
$grid.DefaultCellStyle.SelectionForeColor = $cInk
$grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$grid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(249, 250, 252)
$grid.RowTemplate.Height = 30
$colSel = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colSel.HeaderText = '선택'; $colSel.FillWeight = 6
[void]$grid.Columns.Add($colSel)
foreach ($c in @(@('자리', 5), @('이름', 9), @('주소', 13), @('상태', 20), @('MAC', 14), @('Windows', 22), @('보호', 11), @('CPU', 6), @('메모리', 7), @('디스크', 7))) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.HeaderText = $c[0]; $col.FillWeight = $c[1]; $col.ReadOnly = $true
    [void]$grid.Columns.Add($col)
}

$log = New-Object System.Windows.Forms.RichTextBox
$log.Dock = 'Fill'; $log.ReadOnly = $true; $log.BackColor = [Drawing.Color]::FromArgb(250, 251, 252)
$log.BorderStyle = 'None'; $log.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$log.ForeColor = $cInk

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'; $split.Orientation = 'Horizontal'; $split.SplitterWidth = 6
$split.BackColor = $cLine
$split.Panel1.Controls.Add($grid)
$split.Panel2.Controls.Add($log)
$form.Add_Shown({ try { $split.SplitterDistance = [int]($split.Height * 0.60) } catch {} })

# ---- 왼쪽: 번호 순서대로 버튼 ----
$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Left'; $panel.Width = 276
$panel.FlowDirection = 'TopDown'; $panel.WrapContents = $false; $panel.AutoScroll = $true
$panel.Padding = New-Object System.Windows.Forms.Padding(12, 6, 6, 10)
$panel.BackColor = $cSide

$status = New-Object System.Windows.Forms.StatusStrip
$status.BackColor = [Drawing.Color]::FromArgb(30, 41, 59); $status.SizingGrip = $false
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = '대기 중'; $statusLabel.ForeColor = [Drawing.Color]::White
[void]$status.Items.Add($statusLabel)
$hintLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$hintLabel.Text = '   |   학생 PC 관리자 계정: labadmin (Basic 인증)   비밀번호: 1211'
$hintLabel.ForeColor = [Drawing.Color]::FromArgb(147, 197, 253)
[void]$status.Items.Add($hintLabel)

$form.Controls.Add($split)
$form.Controls.Add($panel)
$form.Controls.Add($status)

function Write-Log([string]$text) {
    $log.AppendText($text + [Environment]::NewLine)
    $log.ScrollToCaret()
    try { Add-Content -Path $LogFile -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $text) -Encoding UTF8 } catch {}
}

function Confirm-Action([string]$msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, '실습실 PC 제어', 'YesNo', 'Warning') -eq 'Yes'
}

function Ensure-TrustedHosts {
    # hosts.csv 의 이름/IP 가 TrustedHosts 에 없으면 추가 (Basic/NTLM 접속에 필요 - IP 가 바뀌어도 자동 반영)
    try {
        $cur = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
        $have = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
        foreach ($x in ($cur -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { [void]$have.Add($x) }
        $add = @()
        foreach ($r in $grid.Rows) {
            foreach ($v in @($r.Cells[2].Value, $r.Cells[3].Value)) {
                $v = "$v".Trim()
                if ($v -and $have.Add($v)) { $add += $v }
            }
        }
        if ($add.Count -gt 0) {
            $new = (($cur -split ',' | Where-Object { $_.Trim() }) + $add) -join ','
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value $new -Force -ErrorAction Stop
            Write-Log ("TrustedHosts 에 {0}개 항목을 추가했습니다." -f $add.Count)
        }
    } catch { Write-Log ("TrustedHosts 갱신 실패: {0}" -f $_.Exception.Message) }
}
function Load-Hosts {
    $grid.Rows.Clear()
    if (-not (Test-Path $HostsCsv)) { Write-Log "hosts.csv 가 없습니다: $HostsCsv"; return }
    foreach ($h in Import-Csv -Path $HostsCsv -Encoding UTF8) {
        $addr = if ($h.Address) { $h.Address } else { $h.Name }
        if (-not $addr) { continue }
        $i = $grid.Rows.Add($false, $h.Seat, $h.Name, $addr, '-', $h.Mac, '', '', '', '', '')
        $grid.Rows[$i].Tag = $h.Mac
    }
    Write-Log ("hosts.csv 에서 {0}대를 불러왔습니다." -f $grid.Rows.Count)
    Ensure-TrustedHosts
}

function Get-Cred {
    if (-not $script:cred) {
        # 입력창이 사용자 이름 형식 오류로 닫히지 않는 문제를 피하려고 고정 계정으로 바로 만든다 (다른 계정은 '자격 증명 다시 입력' 버튼)
        $script:cred = New-Object System.Management.Automation.PSCredential('labadmin', (ConvertTo-SecureString '1211' -AsPlainText -Force))
    }
    $script:cred
}

function Get-Selected { @($grid.Rows | Where-Object { $_.Cells[0].Value -eq $true }) }

function Set-Busy([bool]$busy) {
    foreach ($b in $script:buttons) { $b.Enabled = -not $busy }
    $grid.Enabled = -not $busy
}

function Save-Hosts {
    try {
        $rows = foreach ($r in $grid.Rows) {
            [pscustomobject]@{ Seat = $r.Cells[1].Value; Name = $r.Cells[2].Value; Address = $r.Cells[3].Value; Mac = $(if ($r.Cells[5].Value) { $r.Cells[5].Value } else { $r.Tag }) }
        }
        $rows | Export-Csv -Path $HostsCsv -NoTypeInformation -Encoding UTF8
    } catch { Write-Log ("hosts.csv 저장 실패: {0}" -f $_.Exception.Message) }
}
function Handle-Out($e, [string]$text) {
    if ($text.StartsWith('@@INFO@@')) {
        try {
            $o = $text.Substring(8) | ConvertFrom-Json
            $r = $e.Row
            if ($o.mac)  { $r.Cells[5].Value = $o.mac; $r.Tag = $o.mac }
            if ($o.ip -and $r.Cells[3].Value -ne $o.ip) { $r.Cells[3].Value = $o.ip; $script:hostsDirty = $true }
            $r.Cells[6].Value = $o.os
            $r.Cells[7].Value = $o.freeze
            $r.Cells[8].Value = '{0}%' -f $o.cpu
            $r.Cells[9].Value = '{0}%' -f $o.mem
            $r.Cells[10].Value = '{0}%' -f $o.disk
            if ($o.freeze -like '켜짐*') { $r.Cells[7].Style.ForeColor = 'Blue' } else { $r.Cells[7].Style.ForeColor = 'Black' }
        } catch { Write-Log ("{0} 정보 해석 실패: {1}" -f $e.Tag, $_.Exception.Message) }
        return
    }
    Write-Log ("{0} {1}" -f $e.Tag, $text)
}
function Start-Remote([string]$title, [string]$body, [object[]]$argList, [string]$confirmMsg = '') {
    if ($script:jobs.Count -gt 0) { return }
    $rows = Get-Selected
    if ($rows.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('대상 PC 를 선택하세요.'); return }
    if ($confirmMsg -and -not (Confirm-Action ("{0}`n`n대상: {1}대" -f $confirmMsg, $rows.Count))) { return }
    $script:quiet = ($title -like '정보*')
    $cred = Get-Cred
    if (-not $cred) { return }
    $sb = [scriptblock]::Create($common + "`n" + $body)
    $opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 7200000 -NoMachineProfile
    if (-not $script:quiet) { Write-Log '' }
    if (-not $script:quiet) { Write-Log ("=== {0} ({1}대, {2:HH:mm:ss}) ===" -f $title, $rows.Count, (Get-Date)) }
    $statusLabel.Text = "$title 실행 중..."
    Set-Busy $true
    foreach ($r in $rows) {
        $r.Cells[4].Value = '실행 중...'
        $j = Invoke-Command -ComputerName $r.Cells[3].Value -Credential $cred -Authentication Basic -SessionOption $opt -ScriptBlock $sb -ArgumentList $argList -AsJob
        [void]$script:jobs.Add(@{ Job = $j; Row = $r; Tag = "[{0}]" -f $(if ($r.Cells[1].Value) { $r.Cells[1].Value } else { $r.Cells[2].Value }) })
    }
    $timer.Start()
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
    foreach ($e in @($script:jobs)) {
        $j = $e.Job
        Receive-Job $j -ErrorAction SilentlyContinue | ForEach-Object { Handle-Out $e ("$_" -replace "`0", '') }
        if ($j.State -eq 'Running' -or $j.State -eq 'NotStarted') { continue }
        Receive-Job $j -ErrorAction SilentlyContinue | ForEach-Object { Handle-Out $e ("$_" -replace "`0", '') }
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
        if ($script:hostsDirty) { Save-Hosts; $script:hostsDirty = $false; Ensure-TrustedHosts }
        $statusLabel.Text = '완료'
        if (-not $script:quiet) { Write-Log '--- 모든 대상 종료 ---' }
    }
})

function Add-Header([string]$text) {
    $h = New-Object System.Windows.Forms.Label
    $h.Text = $text; $h.AutoSize = $false; $h.Width = 240; $h.Height = 26
    $h.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [Drawing.FontStyle]::Bold)
    $h.ForeColor = $cAccent; $h.TextAlign = 'BottomLeft'
    $h.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 3)
    $panel.Controls.Add($h)
}
function Add-Button([string]$text, [scriptblock]$onClick, [bool]$lockable = $true) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Size = New-Object System.Drawing.Size(240, 32)
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = $cLine; $b.FlatAppearance.BorderSize = 1
    $b.BackColor = [Drawing.Color]::White; $b.ForeColor = $cInk
    $b.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(235, 242, 255)
    $b.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(219, 234, 254)
    $b.TextAlign = 'MiddleLeft'; $b.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_Click($onClick)
    $panel.Controls.Add($b)
    if ($lockable) { $script:buttons += $b }
}

$guardArg = $RemoteGuard

Add-Header '선택'
Add-Button '1. 전체 선택'       { foreach ($r in $grid.Rows) { $r.Cells[0].Value = $true } }
Add-Button '2. 전체 해제'       { foreach ($r in $grid.Rows) { $r.Cells[0].Value = $false } }
Add-Button '3. 자리 범위 선택...' {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $in = [Microsoft.VisualBasic.Interaction]::InputBox("선택할 자리 번호를 입력하세요.`n예) 5-20   또는   1,3,5-8", '자리 범위 선택', '5-20')
    if (-not $in) { return }
    $want = New-Object System.Collections.Generic.HashSet[int]
    foreach ($part in ($in -split '[,\s]+' | Where-Object { $_ })) {
        if ($part -match '^(\d+)-(\d+)$') { foreach ($n in [int]$Matches[1]..[int]$Matches[2]) { [void]$want.Add($n) } }
        elseif ($part -match '^\d+$') { [void]$want.Add([int]$part) }
    }
    foreach ($r in $grid.Rows) { $r.Cells[0].Value = $want.Contains([int]("$($r.Cells[1].Value)" -replace '\D', '0')) }
    Write-Log ("자리 범위 선택: {0} (체크된 PC {1}대)" -f $in, (Get-Selected).Count)
}
Add-Button '4. hosts.csv 새로고침' { Load-Hosts }
Add-Header '진단 · 업데이트 복구'
Add-Button '5. 진단 (읽기 전용)' { Start-Remote '진단' $opDiag @($guardArg) }
Add-Button '6. 가드 배포/갱신 + 상시감시' {
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
Add-Button '7. 업데이트 지금 복구'   { Start-Remote '업데이트 지금 복구' $opGuardRun @($guardArg) }
Add-Button '8. 업데이트 검색 시작'   { Start-Remote '업데이트 검색' $opScan @($guardArg) }
Add-Header '연결 · 배포'
Add-Button '9. 연결 테스트' { Start-Remote '연결 테스트' '"연결 OK: $env:COMPUTERNAME / $((Get-CimInstance Win32_OperatingSystem).Caption)"' @() }
Add-Button '10. 스크립트 파일 원격 실행...' {
    # 새 기능을 추가해도 학생 PC 를 방문하지 않도록 임의의 .ps1 을 원격 실행 (param() 대신 $args 사용)
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'PowerShell (*.ps1)|*.ps1'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $body = [IO.File]::ReadAllText($dlg.FileName)
    Start-Remote ('스크립트: ' + [IO.Path]::GetFileName($dlg.FileName)) $body @() ("선택한 PC 에서 다음 스크립트를 실행합니다:`n" + $dlg.FileName)
}
$StudentProfileUser = 'student'   # 파일을 넣을 학생 계정 (자동 로그인 계정)
Add-Button '11. 파일 배포 (student 문서 폴더)...' {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = '선택한 PC 의 학생 문서 폴더로 보낼 파일'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $fi = Get-Item $dlg.FileName
    if ($fi.Length -gt 20MB) { [void][System.Windows.Forms.MessageBox]::Show('20MB 보다 큰 파일은 보낼 수 없습니다.'); return }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fi.FullName))
    $body = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Deploy.ps1'))
    Start-Remote ('파일 배포: ' + $fi.Name) $body @($b64, $fi.Name, $StudentProfileUser) ("다음 파일을 선택한 PC 의 {0} 계정 문서 폴더로 보냅니다.`n{1} ({2:N0} 바이트)`n같은 이름의 파일은 덮어씁니다." -f $StudentProfileUser, $fi.Name, $fi.Length)
}
Add-Header '복구 도구'
Add-Button '12. 복원 지점 + 백업'     { Start-Remote '복원 지점/백업' $opRestore @($guardArg) '선택한 PC 에 복원 지점을 만들고 레지스트리를 백업합니다.' }
Add-Button '13. 시스템 파일 복구'     { Start-Remote '시스템 파일 복구' $opRepair @($guardArg) '선택한 PC 에서 복원 지점 생성 후 DISM+SFC 를 실행합니다. PC당 수십 분 걸릴 수 있고 인터넷 연결이 필요합니다.' }
Add-Button '14. 디스크 검사 예약'     { Start-Remote '디스크 검사 예약' $opChkdsk @($guardArg) '선택한 PC 에서 다음 재부팅 때 chkdsk /f /r 를 실행하도록 예약합니다.' }
Add-Button '15. 상시 감시 해제'       { Start-Remote '상시 감시 해제' $opGuardUninstall @($guardArg) '선택한 PC 의 상시 감시를 해제합니다.' }
$LocalFreeze = Join-Path $PSScriptRoot 'Freeze.ps1'
function Get-SystemBody([string]$action) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($LocalFreeze, [Text.Encoding]::UTF8)))
    "`$Action = '$action'`n`$FreezeB64 = '$b64'`n" + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RunAsSystem.ps1'))
}function Add-FreezeButton([string]$text, [string]$action, [string]$confirm) {
    Add-Button $text ({
        if (-not (Test-Path $LocalFreeze)) { Write-Log "Freeze.ps1 없음: $LocalFreeze"; return }
        $body = "`$Action = '$action'`n" + [IO.File]::ReadAllText($LocalFreeze)
        Start-Remote ('보호: ' + $action) $body @() $confirm
    }.GetNewClosure())
}
Add-Header '보호 (쓰기 필터)'
Add-FreezeButton '16. 보호 상태 확인'       'Status'  ''
Add-FreezeButton '17. 보호 진단 (원인 확인)' 'Diag' ''
Add-FreezeButton '18. 보호 기능 설치 (재부팅)' 'Install' '선택한 PC 에 UWF 기능을 설치합니다. 설치 후 재부팅해야 합니다.'
Add-Button '19. 보호 켜기 (10초 후 재부팅)' {
    if (-not (Test-Path $LocalFreeze)) { Write-Log "Freeze.ps1 없음: $LocalFreeze"; return }
    $body = (Get-SystemBody 'Enable') + "`n& shutdown.exe /r /t 10 /c '실습실 관리: 보호 적용을 위해 10초 후 재부팅합니다.'; '10초 후 재부팅 예약됨'"
    Start-Remote '보호 켜기' $body @() '선택한 PC 의 C: 를 보호하고 10초 뒤 재부팅합니다. 보호 중에는 재부팅할 때마다 C: 의 변경 내용이 사라집니다. (자동 로그인과 업데이트 가드가 없으면 거부되고 재부팅하지 않습니다.)'
}
Add-Button '20. 보호 해제 (10초 후 재부팅)' {
    if (-not (Test-Path $LocalFreeze)) { Write-Log "Freeze.ps1 없음: $LocalFreeze"; return }
    $body = (Get-SystemBody 'Disable') + "`n& shutdown.exe /r /t 10 /c '실습실 관리: 보호 해제를 위해 10초 후 재부팅합니다.'; '10초 후 재부팅 예약됨'"
    Start-Remote '보호 해제' $body @() '선택한 PC 의 보호를 해제하고 10초 뒤 재부팅합니다. 재부팅 후에는 업데이트/설정 변경이 유지됩니다.'
}
# ---- 컴퓨터별 정보(Windows 버전, MAC, 보호 상태, CPU/메모리/디스크 사용량) ----
$InfoBody = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Info.ps1'))
$script:autoOn = $false
Add-Header '정보'
Add-Button '21. 정보 새로고침 (선택 PC)' {
    Start-Remote '정보 새로고침' $InfoBody @()
}
$autoTimer = New-Object System.Windows.Forms.Timer
$autoTimer.Interval = 30000
$autoTimer.Add_Tick({
    if ($script:jobs.Count -gt 0) { return }
    if ((Get-Selected).Count -eq 0) { return }
    Start-Remote '정보 새로고침' $InfoBody @()
})
Add-Button '22. 자동 새로고침 켜기/끄기 (30초)' {
    $script:autoOn = -not $script:autoOn
    if ($script:autoOn) { $autoTimer.Start(); Write-Log '자동 새로고침 켜짐 (30초마다 선택한 PC 의 정보 갱신)' } else { $autoTimer.Stop(); Write-Log '자동 새로고침 꺼짐' }
} $false
Add-Header '전원'
Add-Button '23. 재부팅 (10초 예고)' {
    Start-Remote '재부팅' '& shutdown.exe /r /t 10 /c "실습실 관리: 10초 후 재부팅됩니다."; "10초 후 재부팅 예약됨"' @() '선택한 PC 를 10초 후 재부팅합니다.'
}
Add-Button '24. 종료 (10초 예고)' {
    Start-Remote '종료' '& shutdown.exe /s /t 10 /c "실습실 관리: 10초 후 종료됩니다."; "10초 후 종료 예약됨"' @() '선택한 PC 를 10초 후 종료합니다.'
}
Add-Button '25. 재부팅/종료 예약 취소' { Start-Remote '예약 취소' '& shutdown.exe /a 2>&1 | ForEach-Object { "$_" }' @() }
Add-Button '26. 전원 켜기 (WoL)' {
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
Add-Header '도구'
Add-Button '27. 자격 증명 다시 입력' { $script:cred = Get-Credential -UserName '.\User' -Message '학생 PC 의 로컬 관리자 계정' } $false
Add-Button '28. 로그 폴더 열기' { Start-Process explorer.exe $LogDir } $false

$form.Add_FormClosing({
    if ($script:jobs.Count -gt 0) {
        if (-not (Confirm-Action '작업이 진행 중입니다. 창을 닫으면 결과를 받을 수 없습니다. 종료할까요?')) { $_.Cancel = $true }
        else { foreach ($e in $script:jobs) { Stop-Job $e.Job -ErrorAction SilentlyContinue } }
    }
})

Load-Hosts
Write-Log '교사용 제어 콘솔 시작. 학생 PC 에는 Setup-Student.bat 으로 WinRM 설정이 먼저 되어 있어야 합니다.'
[void]$form.ShowDialog()
