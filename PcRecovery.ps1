#Requires -RunAsAdministrator
# PC 복구 도구 - 시스템 파일 복구 / 복원 지점 / Windows Update 상시 감시
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Guard   = Join-Path $PSScriptRoot 'UpdateGuard.ps1'
$DataDir = Join-Path $env:ProgramData 'PcRecovery'
$LogDir  = Join-Path $DataDir 'logs'
foreach ($d in $DataDir, $LogDir, (Join-Path $DataDir 'backup')) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
$LogFile = Join-Path $LogDir ("recovery-{0:yyyyMMdd}.log" -f (Get-Date))

. (Join-Path $PSScriptRoot 'Ops.ps1')

# ---- UI ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'PC 복구 도구'
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)

$panel = New-Object System.Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Top'; $panel.Height = 150; $panel.Padding = New-Object System.Windows.Forms.Padding(8)
$panel.WrapContents = $true

$log = New-Object System.Windows.Forms.RichTextBox
$log.Dock = 'Fill'; $log.ReadOnly = $true; $log.BackColor = 'White'
$log.Font = New-Object System.Drawing.Font('Consolas', 9)

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = '대기 중'
[void]$status.Items.Add($statusLabel)

$form.Controls.Add($log)
$form.Controls.Add($panel)
$form.Controls.Add($status)

$script:buttons = @()
function Add-Button([string]$text, [scriptblock]$onClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Size = New-Object System.Drawing.Size(200, 32)
    $b.Margin = New-Object System.Windows.Forms.Padding(4)
    $b.Add_Click($onClick)
    $panel.Controls.Add($b)
    $script:buttons += $b
}

function Write-Log([string]$text) {
    $line = $text
    $log.AppendText($line + [Environment]::NewLine)
    $log.ScrollToCaret()
    try { Add-Content -Path $LogFile -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $line) -Encoding UTF8 } catch {}
}

function Confirm-Action([string]$msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, 'PC 복구 도구', 'YesNo', 'Warning') -eq 'Yes'
}

$script:job = $null
$script:afterJob = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if (-not $script:job) { return }
    Receive-Job $script:job -ErrorAction SilentlyContinue | ForEach-Object { Write-Log ("$_" -replace "`0", '') }
    if ($script:job.State -ne 'Running') {
        Receive-Job $script:job -ErrorAction SilentlyContinue | ForEach-Object { Write-Log ("$_" -replace "`0", '') }
        Remove-Job $script:job -Force
        $script:job = $null
        $timer.Stop()
        foreach ($b in $script:buttons) { $b.Enabled = $true }
        $statusLabel.Text = '완료'
        Write-Log '--- 작업 종료 ---'
        if ($script:afterJob) { $cb = $script:afterJob; $script:afterJob = $null; & $cb }
    }
})

function Start-Op([string]$title, [string]$body, [scriptblock]$after = $null) {
    if ($script:job) { return }
    Write-Log ''
    Write-Log "=== $title ($(Get-Date -Format 'HH:mm:ss')) ==="
    $statusLabel.Text = "$title 실행 중..."
    foreach ($b in $script:buttons) { $b.Enabled = $false }
    $script:afterJob = $after
    $sb = [scriptblock]::Create($common + "`n" + $body)
    $script:job = Start-Job -ScriptBlock $sb -ArgumentList $Guard
    $timer.Start()
}

function Ask-Reboot {
    if (Confirm-Action '지금 재부팅하시겠습니까?') { Restart-Computer -Force }
}

Add-Button '1. 진단 (읽기 전용)'            { Start-Op '진단' $opDiag }
Add-Button '2. 복원 지점 + 레지스트리 백업' {
    if (Confirm-Action '시스템 복원 지점을 만들고 업데이트 관련 레지스트리를 백업합니다.') { Start-Op '복원 지점/백업' $opRestore }
}
Add-Button '3. 시스템 파일 복구 (DISM+SFC)' {
    if (Confirm-Action "복원 지점을 만든 뒤 DISM /RestoreHealth 와 SFC /scannow 를 실행합니다.`n시간이 오래 걸리며 인터넷 연결이 필요할 수 있습니다. 진행할까요?") { Start-Op '시스템 파일 복구' $opRepair }
}
Add-Button '4. 디스크 검사 예약 (재부팅 필요)' {
    if (Confirm-Action "복원 지점을 만든 뒤 다음 재부팅 때 chkdsk /f /r 를 실행하도록 예약합니다.`n디스크 크기에 따라 부팅 시 검사가 오래 걸립니다. 진행할까요?") { Start-Op '디스크 검사 예약' $opChkdsk { Ask-Reboot } }
}
Add-Button '5. 업데이트 상시 감시 설치' {
    if (Confirm-Action "Windows Update 차단 요소(정책/서비스/예약 작업)를 지금 복구하고,`n시작·로그온·1시간마다 자동 점검하는 작업을 등록합니다. 진행할까요?") { Start-Op '업데이트 상시 감시 설치' $opGuardInstall }
}
Add-Button '6. 업데이트 지금 복구' {
    if (Confirm-Action '업데이트 차단 요소를 지금 한 번 복구합니다.') { Start-Op '업데이트 지금 복구' $opGuardRun }
}
Add-Button '7. 업데이트 검색 시작'           { Start-Op '업데이트 검색' $opScan }
Add-Button '8. 상시 감시 해제'               {
    if (Confirm-Action '상시 감시 작업을 해제합니다. (이후 차단 요소가 다시 생겨도 자동 복구되지 않습니다)') { Start-Op '상시 감시 해제' $opGuardUninstall }
}
Add-Button '로그 폴더 열기'                  { Start-Process explorer.exe $LogDir }

$form.Add_FormClosing({
    if ($script:job) {
        if (-not (Confirm-Action '작업이 진행 중입니다. 종료하면 중단됩니다. 종료할까요?')) { $_.Cancel = $true }
        else { Stop-Job $script:job -ErrorAction SilentlyContinue }
    }
})

if (-not (Test-Path $Guard)) {
    [System.Windows.Forms.MessageBox]::Show("UpdateGuard.ps1 을 찾을 수 없습니다.`n$Guard", 'PC 복구 도구', 'OK', 'Error') | Out-Null
    return
}
Write-Log 'PC 복구 도구 시작. 먼저 [1. 진단]으로 상태를 확인하세요.'
[void]$form.ShowDialog()
