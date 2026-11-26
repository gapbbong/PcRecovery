# 학생 PC 에서 원격 실행: Teacher.ps1 이 base64 로 보낸 파일을 학생 계정 문서 폴더에 저장한다
$b64 = $args[0]; $name = $args[1]; $user = $args[2]
$prof = "C:\Users\$user"
if (-not (Test-Path $prof)) { "건너뜀: $user 프로필이 없습니다 (학생 계정으로 한 번도 로그인하지 않음)"; return }
$dir = Join-Path $prof 'Documents'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$dest = Join-Path $dir $name
[IO.File]::WriteAllBytes($dest, [Convert]::FromBase64String($b64))
"배포 완료: $dest"
try {
    if ((Get-CimInstance -Namespace 'root\standardcimv2\embedded' -ClassName UWF_Filter -ErrorAction Stop).CurrentEnabled) { "주의: 보호가 켜져 있어 재부팅하면 이 파일이 사라집니다." }
} catch {}