# RESEARCH_competitive_v1.md — 경쟁 앱 비교 · 차별화 · 기능 제안 (v1)
> 생성일: 2026-09-24 | 상태: **조사 완료** · 방향 확정(사용자 승인)
> 목적: 시장 지형·경쟁 포지션·차별화 킬러·기능 백로그 원본 보존
> 후속: 본 계획(알림 채널) 완료 후 **리서치 재검토 → 개선 항목 도출** 예정
> 범위 확정(사용자): **알림 채널 1순위** · **로컬 전용** · **Apple Phase 2 보류** · README 작성 · 재검토 주기

---

## 1. 시장 지형 — 교차 카테고리

Relay Console은 세 시장이 교차하는 지점에 위치.

| 카테고리 | 대표 | 특징 |
|---------|------|------|
| **A. 메뉴바 ADB 유틸** | AndroidDeviceManager, Adb-DECK, AndroLaunch, EmuHub, BootBar | 기기 연결·빠른 토글·미러링 — 단기 유틸, 감시 없음 |
| **B. 풀 ADB GUI** | Droidective, ADB Studio, ADBOSS, Super ADB Manager, adb-tui | APK·파일·터미널·56종 도구 — 개발 도구 중심, 메뉴바 상주 없음 |
| **C. 업타임/인프라 모니터** | Uptime Kuma, Gatus, openstatus, Kuvasz | HTTP/TCP/ping + 상태 페이지 — 기기 무관, 서버 중심 |
| **D. 디바이스 팜/플릿** | OpenSTF/DeviceFarmer(사실상 사망), STF, drizz-farm, MPhone, DeviceKit | 웹 대시보드·세션·자동화 — 설치·운영 부담 큼, 개인용 아님 |
| **E. 맥 메뉴바 시스템 모니터** | Stats(exelban), iStat Menus | 맥 자체 모니터링 — 외부 기기 무관 |

**공백**: A(가벼움) + C(감시 지속성) + 메뉴바 상주를 한 앱으로 묶은 것이 없음.
대부분 “연결했을 때 열어보는 도구” 또는 “서버를 돌리는 SaaS”.

---

## 2. 현 상태 (v1.1.1) vs 경쟁 포지션

### 이미 가진 것

| 영역 | Relay Console | A·B (ADB) | C (Uptime) | D (팜) |
|------|--------------|-----------|------------|--------|
| 메뉴바 상주·한눈 감시 | ✅ | 일부 | ❌ | ❌ |
| Android 실시간 8카드 + 5분 스파크라인 | ✅ | 일부 스냅샷 | ❌ | 일부 |
| 감시 18종 + hysteresis + ack/mute/note | ✅ | ❌ | 임계만 | ❌ |
| Sites(7d/30d Google식 + 가동률) | ✅ | ❌ | ✅ | ❌ |
| Jobs 하트비트 (loopback) | ✅ | ❌ | ✅ 일부 | ❌ |
| 기기 + 사이트 + 작업 통합 알림 폭 | ✅ | ❌ | ❌ | 부분 |
| scrcpy 원클릭 (외부) | ✅ | ✅ | ❌ | ✅ |
| Apple Trust Phase1 | ✅ (보류) | 일부 | ❌ | 일부 |
| 셋업 부담 | 낮음 | 낮음 | 서버 필요 | 높음 |

### 뒤처지는 것

| 결함 | 참고 |
|------|------|
| APK 설치·앱 관리·파일 탐색 없음 | ADB Studio, Droidective, ADBOSS |
| Wi-Fi 페어링/QR 온보딩 약함 | ADB Studio, AndroLaunch |
| 앱 제어 깊이 얕음 | ADB AppControl, Droidective |
| 외부 알림 없음 (Slack/ntfy/웹훅) | openstatus, Uptime Kuma, Grafana |
| 상태 페이지·공유 없음 | openstatus, Kuvasz |
| 팀/플릿·예약·세션 없음 | drizz-farm, DeviceKit, MPhone |
| AI/MCP 연동 없음 | adb-tui(MCP), DeviceKit(AI) |
| TLS/도메인·SSL 만료 감시 없음 | Uptime 경쟁 |
| 루트 README 없음 | 전 경쟁 존재 |

### 외부 리서치 원본 (검색 출처 요약)

- `WhileEndless/AndroidDeviceManager` — macOS 메뉴바 ADB, Swift/AppKit, 10초 탐지·root/인증 표시·WiFi/USB
- `Zaphkiel-Ivanovna/adb-studio` — native macOS ADB GUI
- Vysor vs scrcpy — 무료/오픈소스/저지연 vs 상용·드래그앤드롭
- `openstatusHQ/openstatus` — status page+uptime 통합, self-host, MCP server, monitoring as code
- Stats (exelban) — macOS 메뉴바 시스템 모니터, free·open-source
- `Dinip/adb_metrics` — ADB→InfluxDB+Grafana
- OpenSTF/DeviceFarmer 쇠퇴 — DeviceLab 등 대체

---

## 3. 차별화 킬러 포지션

### 킬러 한 줄
> **“서버를 띄우지 않는, 맥 메뉴바의 개인 관제탑 — 폰·사이트·정기 작업을 하나의 알림 폭으로.”**

### 킬러 축 3

1. **K1 올인원 관제 폭** — serial=device, site, job을 같은 WatchEvent 파이프에 넣음
2. **K2 설치 0·서버 0 지속 감시** — 메뉴바 상주 + JSON 영구화 + 127.0.0.1 하트비트
3. **K3 관제탑 UX** — 다크 전용 · 색+텍스트 병기 · Sites 상태 바 타임라인

---

## 4. 채택 대상 기능 (Adopt — 우선순위)

| # | 기능 | Impact | Effort | 비고 |
|---|------|--------|--------|------|
| **A1** | **외부 알림: ntfy / Slack 웹훅** | 최상 | 중 | **본 계획 착수** |
| A2 | Wi-Fi ADB 온보딩 개선 | 상 | 하~중 | |
| A3 | 앱 관리 미니 허브 | 상 | 중 | |
| A4 | 파일/스샷 갤러리 | 중 | 중 | |
| A5 | Sites SSL/도메인 만료 + assertion | 상 | 중~상 | |
| A6 | Sites 90일 캘린더 + 그룹/태그 | 중 | 중 | |
| A7 | 라이브액티비티/Dock 배지/그룹화 | 중 | 하 | |
| A8 | 로그인 항목 + 헤드리스 | 중 | 하 | |
| A9 | Apple Phase 2 | 중 | 중 | **보류 (기기 확보)** |
| A10 | MCP 서버 (로컬) | 중~상 | 중 | |

---

## 5. 신규 킬러 기능 (Differentiate)

### TIER S
- **S1** 통합 관제 피드 = 아침 브리핑 한 줄 (sites·jobs·폰·critical)
- **S2** Device Health Score (배터리·발열·스로틀 가중 0–100)
- **S3** 관제 규칙 Rules as Code (로컬 YAML)
- **S4** Incident Bundle — ANR/크래시/사이트 down 자동 캡처 번들

### TIER A
Things/캘린더 연동 · 스샷 스크랩북 · 멀티 스냅샷 그리드 · Prometheus/JSON export(선택) · cron 등 기기 태그 · 충전 방치 리포트

### TIER B 피할 방향
- 완전한 파일 탐색기·ADB 터미널·56종 툴박스 (Droidective 영역)
- 클라우드 디바이스 팜·Appium 오케스트레이션
- 웹 상태 페이지 SaaS 정면 승부
- 내장 미러링 재구현 (scrcpy A안 유지)

---

## 6. 사용자 확정 방향 (2026-09-24)

1. **알림 채널 (A1)** — 1순위 구현
2. **로컬 전용** — 클라우드/웹 상태 페이지 제외
3. **Apple Phase 2** — 기기 확보 전 보류 유지
4. **README** — 함께 작성 (권장 방향 수용)
5. **본 계획 완료 후** — 리서치 재검토 → 개선 항목 재도출

---

## 7. 포지셔닝 메시지 (초안)

- **대상**: 홈랩·사이드 프로젝트 운영 개발자·퍼셔널 오너 (기기 1~5 + URL + cron)
- **한 줄**: *“메뉴바에서 끝나는 관제 — 폰·사이트·작업을 한 배지로.”*
- **비교**: Uptime Kuma는 서버 필요, STF는 죽었고, ADB GUI는 감시를 못 함
- **톤**: 관제탑·다크·숫자 SF Mono
