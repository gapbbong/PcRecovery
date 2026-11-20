# PcRecovery

Windows 복구 + Windows Update 상시 감시 도구. 단일 PC용 GUI와, 실습실(24대) 교사용 원격 제어 콘솔로 구성됩니다.

## 단일 PC
`Recovery.bat` 실행 (관리자 권한 자동 요청) → 진단 / 복원 지점 / DISM+SFC / 디스크 검사 예약 / 업데이트 가드.

## 실습실 (워크그룹, WinRM) - 학생 PC는 한 번만 방문
1. **학생 PC 24대 (PC마다 1회)**: 이 폴더를 USB로 가져가 관리자 권한으로 `Setup-Student.bat` 실행.
   - 마지막 줄에 `모든 점검 통과: 이 PC 는 다시 방문할 필요가 없습니다`가 나오면 끝. 실패 항목이 나오면 그 자리에서 해결하고 재실행.
   - 교사용 IP가 고정이면 `Setup-Student.bat 192.168.0.100`처럼 IP를 주어 접속을 제한할 수 있음(생략 시 같은 서브넷 허용 - IP가 바뀌어도 재방문 불필요).
   - 이름/IP/MAC/로컬 관리자 계정이 USB의 `collected` 폴더에 저장됨.
   - 직접 확인할 것: BIOS의 Wake-on-LAN (전원 켜기를 쓸 경우), 사용할 로컬 관리자 계정/비밀번호.
2. **교사용 PC**: USB의 `collected` 폴더를 이 폴더로 복사한 뒤 `Setup-Teacher.bat` 실행 → `hosts.csv` 자동 생성 + TrustedHosts 등록.
3. `Teacher.bat` 실행 → 로컬 관리자 계정 입력 → `0. 연결 테스트`로 24대 확인 후 작업 실행.

이후 학생 PC 방문 없이 가능한 것: 가드 갱신(`2. 가드 배포/갱신`), 새 기능 추가(`스크립트 파일 원격 실행...`), 재부팅/종료/전원 켜기, 모든 복구 작업. WinRM·방화벽 설정이 깨져도 상시 감시(1시간마다)가 자동 복구합니다.

학생은 관리자 권한이 없는 계정을 쓰는 것을 전제로 합니다.

## 파일
| 파일 | 역할 |
|---|---|
| `UpdateGuard.ps1` | 업데이트 차단 요소 + 원격 제어 설정 복구 / 상시 감시(작업 스케줄러) 설치·해제 |
| `Ops.ps1` | 로컬·원격 공통 작업 정의 |
| `PcRecovery.ps1` | 단일 PC GUI |
| `Teacher.ps1` | 교사용 원격 제어 GUI |
| `Setup-Student.*` / `Setup-Teacher.*` | 1회 설정 |

로그/백업: `C:\ProgramData\PcRecovery\` (각 PC)
