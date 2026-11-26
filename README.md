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
3. `Teacher.bat` 실행 → 로컬 관리자 계정 입력 → `9. 연결 테스트`로 24대 확인 후 작업 실행.

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
| `Freeze.*` | 보호(껐다 켜면 C: 초기화, UWF). Enterprise/Education 전용. Status/Install/Enable/Disable. 교사용 콘솔에도 버튼 있음 |

로그/백업: `C:\ProgramData\PcRecovery\` (각 PC)


## 보호 (UWF)
- 순서: Setup-Student 통과 -> `Freeze Install` -> 재부팅 -> `Freeze Enable` -> 재부팅.
- 업데이트/설정 변경: `Freeze Disable` -> 재부팅 -> 작업 -> `Freeze Enable` -> 재부팅.
- 보호 중 C: 의 학생 파일은 재부팅하면 사라집니다. `C:\ProgramData\PcRecovery`(로그)와 Defender 폴더는 제외됩니다.
- PC 이름 변경은 보호 전에 끝내세요.


## 실행 순서 (파일명 앞 번호)
| 번호 | 파일 | 어디서 | 언제 |
|---|---|---|---|
| 1 | `1_Student_SetupAll.bat` | 학생 PC | PC 이름 변경 후 한방 설정 (계정, 교사용 접속, 보호 기능 설치, 자동 재부팅). 보호는 켜지 않음 - 학생 계정 첫 로그인 후 교사용 콘솔의 `보호 켜기 + 재부팅`으로 켬 |
| 2 | `2_Student_FixRemote.bat` | 학생 PC | 교사용 연결이 액세스 거부일 때 (User/1211, 관리자 그룹, 원격 설정 복구) |
| 3 | `3_Student_ProtectOff.bat` | 학생 PC | 업데이트/설정 변경 전 보호 해제 (재부팅) |
| 4 | `4_Student_ProtectOn.bat` | 학생 PC | 작업 후 보호 켜기 (재부팅) |
| 5 | `5_Student_CheckProtect.bat` | 학생 PC | 보호/설정 상태 점검 (결과 txt 저장) |
| 6 | `6_Teacher_Setup.bat` | 교사용 PC | collected 복사 후 hosts.csv/TrustedHosts 갱신 |
| 7 | `7_Teacher_Console.bat` | 교사용 PC | 교사용 제어 콘솔 (창 제목 옆 vN = Teacher.ps1 버전) |

## 2단계 운영 순서
1. PC 이름 변경 -> `1_Student_SetupAll.bat` (재부팅 후 student 자동 로그인, 첫 화면 질문은 정책으로 꺼짐)
2. 학생 화면에서 바탕화면까지 들어온 것을 확인 -> 교사용 콘솔에서 해당 PC 선택 -> `18. 보호 켜기 (10초 후 재부팅)`
3. 교사용 콘솔 표의 MAC/Windows/보호/CPU/메모리/디스크는 `정보 새로고침`(수동) 또는 `자동 새로고침`(30초)으로 갱신
