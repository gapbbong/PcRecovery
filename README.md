# PcRecovery

Windows 복구 + Windows Update 상시 감시 도구. 단일 PC용 GUI와, 실습실(24대) 교사용 원격 제어 콘솔로 구성됩니다.

## 단일 PC
`Recovery.bat` 실행 (관리자 권한 자동 요청) → 진단 / 복원 지점 / DISM+SFC / 디스크 검사 예약 / 업데이트 가드.

## 실습실 (워크그룹, WinRM)
1. `hosts.csv` 에 학생 PC 이름·IP(·MAC) 입력
2. 각 학생 PC에서 관리자 권한으로 `Setup-Student.bat <교사용PC IP>` (1회) — WinRM 활성화, 방화벽을 교사용 IP로 제한, 가드 설치
3. 교사용 PC에서 `Setup-Teacher.bat` (1회) — TrustedHosts 등록
4. 교사용 PC에서 `Teacher.bat` 실행 → 로컬 관리자 계정 입력 → PC 선택 후 작업 실행

학생은 관리자 권한이 없는 계정을 쓰는 것을 전제로 합니다.

## 파일
| 파일 | 역할 |
|---|---|
| `UpdateGuard.ps1` | 업데이트 차단 요소 복구 / 상시 감시(작업 스케줄러) 설치·해제 |
| `Ops.ps1` | 로컬·원격 공통 작업 정의 |
| `PcRecovery.ps1` | 단일 PC GUI |
| `Teacher.ps1` | 교사용 원격 제어 GUI |

로그/백업: `C:\ProgramData\PcRecovery\` (각 PC)
