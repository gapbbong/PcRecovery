# 학생 PC 에서 원격 실행: Freeze.ps1 을 SYSTEM 권한 예약 작업으로 실행하고 결과를 돌려준다
# (원격 관리자 토큰으로는 UWF 설정 변경이 "액세스가 거부되었습니다" 로 막히는 PC 가 있어서 사용)
# 호출 전에 $Action 과 $FreezeB64(Freeze.ps1 의 base64) 가 정의돼 있어야 한다.
$dir = Join-Path $env:ProgramData 'PcRecovery'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$script = Join-Path $dir 'Freeze.ps1'
$outf = Join-Path $dir 'freeze-out.txt'
[IO.File]::WriteAllBytes($script, [Text.Encoding]::UTF8.GetPreamble() + [Convert]::FromBase64String($FreezeB64))
Remove-Item $outf -Force -ErrorAction SilentlyContinue
$tn = 'PcRecovery-ProtectRun'
$cmd = "& '$script' '$Action' *>&1 | Out-File -FilePath '$outf' -Encoding UTF8; exit 0"
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -ExecutionPolicy Bypass -Command `"{0}`"" -f $cmd.Replace('"', '\"'))
$pri = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName $tn -Action $act -Principal $pri -Force | Out-Null
Start-ScheduledTask -TaskName $tn
$deadline = (Get-Date).AddSeconds(120)
do { Start-Sleep -Milliseconds 800 } while ((Get-ScheduledTask -TaskName $tn).State -eq 'Running' -and (Get-Date) -lt $deadline)
Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
$txt = if (Test-Path $outf) { [IO.File]::ReadAllText($outf, [Text.Encoding]::UTF8) } else { '' }
$txt -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch 'Copyright|구성 유틸리티' } | ForEach-Object { $_ }
if (-not $txt) { throw '보호 작업 결과를 읽지 못했습니다.' }
if ($txt -match '보호 (켜기|해제) 실패' -or $txt -match '\[실패\]' -or $txt -match '(?m)^\S*(Exception|오류)') { throw '보호 변경이 실패했습니다. 위 메시지를 확인하세요.' }