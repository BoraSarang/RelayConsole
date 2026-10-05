# RESEARCH_auto_diagnose — 자동 진단 재료 추출 (2026-10-05)

> 방향: 상태가 발생하면 앱이 **스스로 원인을 캐내어** 리포트한다 (관제탑의 다음 단계).
> ## 실측 완료 (S22 SM-S901N · 10.112.134.138:5555 · 2026-10-05)
> 아래 ✅🔬⛔은 실측 판정이다. 원칙 유지: 이상 **감지 시에만** 무거운 명령 1회.

## 1. 크래시가 났다 → "누가, 왜, 얼마나 자주"

| 재료 | 상태 | 원천 |
|---|---|---|
| FATAL EXCEPTION 패키지·예외타입·발생 위치 | ✅ 파서 있음 (`extractProcessDeathContext`) | `logcat -b crash` (IncidentBundle이 이미 덤프) |
| 패키지별 크래시 빈도·최근 N일 추이 | ✅ 가능 | 기존 이벤트 + DeviceDaily 집계 (새 코드 소량) |
| dropbox 크래시 목록 (`data_app_crash`) | ✅ 실측 | `dumpsys dropbox --print` 0.1초·당일 7건 확인 — 전체 덤프가 아니라 목록+최신 N건만 읽는다 |
| 난독화 스택의 근본 원인 | ⛔ | 매핑 파일 없이 원인까지는 불가 — "대략" 선에서 멈춘다 |

## 2. 온도가 올라갔다 → "주범은 누구"

| 재료 | 상태 | 원천 |
|---|---|---|
| 발열 시점 CPU 상위 프로세스 스냅샷 | ✅ 실측 | `top -n 1 -b -o %CPU,CMDLINE` 0.4초·파싱 가능 — throttling enter 시점에 1회 |
| 충전 중 + 핫스팟 여부 (가장 흔한 조합) | ✅ 있음 | 배터리 상태 + 네트워크 상태 (오늘 실측 Status 4가 이 조합) |
| 뜨거운 센서 종류 (skin/battery/soc) | ✅ 실측 | thermal zone 30종 읽기 가능 (pa 47.1℃·cpuss 45℃ 확인) — 최고온 3개만 리포트 |
| 커널 wakelock급 원인 | ⛔ | `dumpsys batterystats`급 무게 — 이상 시 1회만 고려, 평소 금지 |

## 3. LTE 신호 감소 → "빈번한가, 왜 그런가"

| 재료 | 상태 | 원천 |
|---|---|---|
| RSRP/RSRQ/SINR + RAT/BAND 추이 | ✅ 있음 | SignalGrade + metricsHistory |
| 빈도·지속·시간대 패턴 ("빈번한가") | ✅ 가능 | DeviceDaily + insight patterns 집계 (새 코드 소량) |
| 셀 변경 추정 (핸드오버 정황) | ✅ 실측 | `dumpsys telephony.registry`에 서빙셀(mCi/mPci/mTac/earfcn/bands)+이웃셀 — **오늘 345↔93 셀 변경 실측** (mCi 끝자리 ...23↔...87). 단 출력이 수 MB급이라 기기 내 grep으로 mCi/mPci/RSRP만 뽑아 전송 |
| "어째서 좋지 않은가"의 진짜 이유 | ⛔ | 기지국·전파 환경은 기기에서 모름 — **원인 불명으로 적고 패턴만 낸다** ([표시②]) |

## 4. 배터리 광탈 → "얼마나 빨리, 누가 먹나"

| 재료 | 상태 | 원천 |
|---|---|---|
| 방치 추적 (충전 없이 임계 이하 지속) | ✅ 있음 | BatteryNeglectTracker |
| 소모 속도 (%/h) | ✅ 가능 | levelHistory 기울기 (새 코드 소량) |
| UID별 소모량 (주범) | ✅ 실측 | `dumpsys batterystats --checkin` 1858줄·0.24초 — 이상 감지 시 1회만 (상시 금지) |
| Doze/대기 상태 구분 | ✅ 실측 | `dumpsys deviceidle` 읽기 가능 |

## 5. ANR → "어디서 멈췄나"

| 재료 | 상태 | 원천 |
|---|---|---|
| ANR 발생 + 패키지 | ✅ 있음 | logcat 키워드 감시 |
| ANR 목록 (횟수·시각) | ✅ 실측 | `/data/anr/` 목록 읽기 가능 (9/21 2건 확인) |
| main 스레드 스택 | ⛔ 실측 | 파일 내용은 **Permission denied** — logcat 정황 + CPU로 "대략"만 |

## 6. 연결 끊김 → "왜 자주 끊기나"

| 재료 | 상태 | 원천 |
|---|---|---|
| 끊김 빈도·시간대 패턴 | ✅ 거의 공짜 | ConnectionSessionStore + IssueLog device 로그 (오늘 이미 쌓임) |
| 재연결 실패 원인 분류 | ✅ 있음 (오늘 추가) | `wifi.reconnect.failed` / `wifi.server.restart` 로그 |

## 7. 이름 후보 (사용자: "자동 도우미"는 이상함)

- **자동 진단** (권장) — 원인을 캐낸다는 의미가 제일 정확
- 자동 점검 — 정기 검진 뉘앙스, 이벤트-트리거와 거리 있음
- 원인 분석 — 리포트 문서 느낌, 기능명으로는 약함

## 8. 다음 단계

1. 🔬 항목 실측 (기기 연결 시, S22 우선) — 명령별 출력·권한·비용 기록
2. `PLAN_auto_diagnose` 작성 — 트리거별 진단 파이프라인 + 리포트 진입점 (Alerts 상세 "진단" 섹션 후보) + L10n
3. 구현은 트리거 1개씩 (크래시 → 발열 순 권장 — 재료가 가장 익었다)
