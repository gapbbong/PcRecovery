#Requires -RunAsAdministrator
# 교사용 PC 1회 설정: collected\*.csv(학생 PC 수집 정보)로 hosts.csv 갱신 후 WinRM TrustedHosts 등록
$ErrorActionPreference = 'Stop'
$csv  = Join-Path $PSScriptRoot 'hosts.csv'
$coll = Join-Path $PSScriptRoot 'collected'

$rows = @{}
if (Test-Path $csv) {
    foreach ($h in Import-Csv -Path $csv -Encoding UTF8) { if ($h.Name) { $rows[$h.Name] = $h } }
}
$files = @()
if (Test-Path $coll) { $files = @(Get-ChildItem -Path $coll -Filter '*.csv') }
foreach ($f in $files) {
    foreach ($c in Import-Csv -Path $f.FullName -Encoding UTF8) {
        $seat = if ($c.Name -match '(\d+)$') { [int]$Matches[1] } else { '' }
        if (-not $rows.ContainsKey($c.Name)) { $rows[$c.Name] = [pscustomobject]@{ Seat = $seat; Name = $c.Name; Address = ''; Mac = '' } }
        if ($c.Address) { $rows[$c.Name].Address = $c.Address }
        if ($c.Mac)     { $rows[$c.Name].Mac = $c.Mac }
        if ($c.Admins)  { Write-Output ("{0}: 로컬 관리자 계정 = {1}" -f $c.Name, $c.Admins) }
    }
}
if ($files.Count -gt 0) {
    if (Test-Path $csv) { Copy-Item $csv "$csv.bak" -Force }
    $rows.Values | Sort-Object Name | Select-Object Seat, Name, Address, Mac | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-Output ("hosts.csv 갱신: 수집 정보 {0}대 반영 (이전 파일은 hosts.csv.bak)" -f $files.Count)
}

$all = Import-Csv -Path $csv -Encoding UTF8 | Where-Object { $_.Name }
$missing = @($all | Where-Object { -not $_.Address -or $_.Address -eq $_.Name })
if ($missing.Count -gt 0) { Write-Output ("참고: IP 정보가 없는 PC {0}대 (이름으로 접속 시도): {1}" -f $missing.Count, (($missing | ForEach-Object { $_.Name }) -join ', ')) }

$hosts = @($all | ForEach-Object { $_.Name; $_.Address } | Where-Object { $_ } | Select-Object -Unique)
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value ($hosts -join ',') -Force
Write-Output ("TrustedHosts 등록 완료 ({0}개 항목)." -f $hosts.Count)
