#Requires -RunAsAdministrator
# 교사용 PC 1회 설정: hosts.csv 의 학생 PC 를 WinRM TrustedHosts 에 등록
$ErrorActionPreference = 'Stop'
$csv = Join-Path $PSScriptRoot 'hosts.csv'
$addrs = @(Import-Csv -Path $csv -Encoding UTF8 | Where-Object { $_.Address } | ForEach-Object { $_.Address })
if ($addrs.Count -eq 0) { throw "hosts.csv 에 Address 가 없습니다: $csv" }

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value ($addrs -join ',') -Force
Write-Output ("TrustedHosts 에 {0}대 등록 완료." -f $addrs.Count)
