# Relay Console

> macOS 메뉴바에 상주하는 **개인 안드로이드·사이트·작업 관제탑**.  
> 서버를 띄우지 않고도 폰·URL·크론 하트비트를 한 배지와 한 알림 폭으로 지킵니다.

- **플랫폼**: macOS 26.0+ (SwiftUI `MenuBarExtra`)
- **번들 ID**: `com.borasarang.relayconsole`
- **버전**: 1.16.0
- **언어**: 한국어 · English

---

## 왜 Relay Console인가

- **서버 없음** — 맥 메뉴바에 상주하는 개인 관제탑: 폰(USB·Wi-Fi)·URL·크론 하트비트를 한 배지와 한 알림 폭으로 감시
- **로컬 전용** — 데이터는 이 기기에서만, 외부 전송은 사용자가 연결한 알림 채널(ntfy/Slack)에만
- **설치·운영 부담 낮음** — 빌드 한 번으로 메뉴바 상주, 별도 서버 불필요

**한 줄**: *메뉴바에서 끝나는 관제 — 폰·사이트·작업을 한 배지로.*

---

## 기능

### 메뉴바 · 팝오버
- 기기 수·배터리·critical 주황 배지
- 팝오버: **아침 브리핑 한 줄**(사이트·지연 작업·폰·critical), 사이트 요약, Jobs overdue, 발열 배너, 권장 후속 조치 체크리스트
- 종료 버튼 + 확인 알림
- 설정 → 일반에서 브리핑 표시 on/off

### 위젯 (macOS WidgetKit · 1.15.0)
- 데스크톱/알림센터용 **Relay 상태** 위젯 3종: small(선택 기기 배터리·발열) / medium(브리핑+사이트+작업) / large(기기·사이트·최근 이벤트 전체)
- 메뉴바 앱이 **60초 간격**으로 스냅샷을 App Group에 기록 — 위젯은 "마지막 업데이트" 시각을 항상 표시
- 위젯 탭 → 콘솔/Alerts 등 해당 화면으로 바로 이동 (`relayconsole://` 딥링크)
- 추가: *데스크톱 우클릭 → "위젯 편집" → 검색 **Relay***

### 기기 관제 (Android · Apple Phase1)
- 8카드: CPU / GPU / MEM / SENSORS / BATTERY / NETWORK / THERMAL / STORAGE
- 5분 스파크라인 · 메모리·프로세스 상위 · scrcpy 원클릭 미러링(읽기 전용 기본)
- 감시 18종: 스로틀링·배터리·PSI·load·메모리·Bsoh·RSRP·ANR·크래시 등  
  hysteresis + 쿨다운 · 시스템 알림 · 화면 상단 배너 · Alerts ack/mute/note
- Apple: `libimobiledevice` Trust-only 연결·배터리/스토리지 카드 (Phase1)

### 사이트 (Sites)
- HTTP / TCP / ping 체크 · 7d·30d 상태 바 · 가동률% · 스파크라인
- 실패 임계(failThreshold) · down → Alerts 편입

### 작업 (Jobs)
- `127.0.0.1` 하트비트 수서버 · overdue/grace · curl 토큰 등록
- overdue → Alerts

### 알림 · 연동 (1.3.0)
- Alerts 3탭(활성/무음/해소) · 필터 · JSON/CSV export
- **외부 채널**: **ntfy**(서버·토픽·Bearer) · **Slack Incoming Webhook**
- 최소 심각도(warning/critical) · 복구 이벤트 토글 · 테스트 전송
- 설정 → **연동** 탭에서 구성 · 토큰/웹훅은 기기에만 저장
- 팝오버 헤더 **아침 브리핑 한 줄** (S1)

---

## 설치

### 요구
- macOS **26.0** 이상
- **xcodegen** — 위젯 extension 빌드 필수 (`brew install xcodegen`)
- (선택) Android **platform-tools** — `adb` PATH 또는 brew
- (선택) **scrcpy** — 미러링 (`brew install scrcpy`)
- (선택) **libimobiledevice** — Apple 기기 (`brew install libimobiledevice`)
- (선택) ntfy 서버 또는 Slack Incoming Webhook

외부 바이너리는 **자동 다운로드하지 않습니다.** 설치는 사용자가 brew 등으로 직접.

### 빌드 · 실행

```bash
git clone https://github.com/BoraSarang/RelayConsole.git
cd RelayConsole
./scripts/build-macos.sh debug
```

스크립트가 `~/Applications/RelayConsole.app`를 생성하고 실행합니다.

### 테스트

```bash
swift test
```

---

## 외부 알림 채널 설정 (ntfy · Slack)

설정 → **연동** → **외부 알림 채널**

### ntfy
1. [ntfy.sh](https://ntfy.sh) 또는 자체 ntfy 서버에서 **토픽** 발행 권한 준비
2. 서버 URL + 토픽 입력 (자체 서버·토큰이면 Bearer 토큰 추가)
3. **ntfy** 토글 ON → **테스트 전송**

### Slack
1. Slack 앱에서 **Incoming Webhook** URL 복사
2. 웹훅 URL 입력 → **Slack 웹훅** 토글 ON → **테스트 전송**

이벤트는 시스템 알림과 **같은 필터·5분 쿨다운**을 통과한 뒤 외부로 전송됩니다.  
실패 시 디버그 로그에 `E-MAC-NOTIFY-0001`이 기록됩니다.

---

## 설정 키 접두어

모든 설정은 `relay.*` (UserDefaults). 예: `relay.notify.ntfy`, `relay.watch.throttling`, `relay.cards.cpu`.

---

## 프로젝트 구조 (요약)

```
Sources/RelayConsole/
  App/          ConsoleStore · CoalescingWriter · EventStore · AlertBanner · AppDelegate
  Droid/        ADB(PollBatch 배치) · 감시 엔진 · ProcessRunner · scrcpy
  Apple/        libimobiledevice Phase1
  Sites/        HTTP·TCP·ping 체커
  Jobs/         하트비트 서버
  Incident/     ANR·크래시·siteDown 번들 캡처
  Models/       WatchEvent · SitesJobs · InsightLogic
  Views/        메뉴바 팝오버 · 콘솔 · 설정 · Alerts · 인사이트
  DesignSystem/ 토큰 · 공통 컴포넌트
  Utils/        파서 · ThresholdGate · NotifyChannel · IssueLog · DebugLogger
Sources/RelayMcpCore/   로컬 MCP 프로토콜·데이터 (읽기 전용)
Sources/RelayWidgetCore/ 위젯 공유 스냅샷 모델 · App Group 저장소
docs/         PLAN · RESEARCH · DESIGN · TODO
```

---

## 문서

| 문서 | 내용 |
|------|------|
| `docs/DESIGN.md` | 관제탑 토큰·다크 전용 규칙 |
| `docs/TODO.md` | 진행·보류·완료 |
| `docs/plans/` | PLAN_v0.x · alerts · sites · notify |
| `docs/research/` | 경쟁 리서치·감시 이벤트·Apple 조사 |
| `docs/api/HEARTBEAT.md` | 하트비트 엔드포인트 |
| `AGENTS.local.md` | 프로젝트 AI 규칙 |

---

## 라이선스 / 브랜드

- 앱 이름: **Relay Console** (구 Outpost → 브랜드 이관)
- 아이콘: `BrandKit/`
- 외부 도구(adb, scrcpy, libimobiledevice, ntfy, Slack)의 라이선스는 각 프로젝트를 따릅니다.

---

## 주의

- 하트비트 서버는 **127.0.0.1**에만 바인드됩니다 (외부 노출 금지).
- 기기 식별자는 **화면·알림·내보내기에서 원문 그대로** 표시합니다 — 무선 기기는 `IP:PORT`,
  USB 는 `기기명 · 시리얼`. `…5555` 로 축약하면 무선 기기 구분이 불가능해집니다.
  마스킹(뒤 4자리)은 **DebugLogger · 로그 파일 출력에만** 적용됩니다.
- 하트비트 토큰·웹훅 URL은 하드코딩하지 않으며, 로그에는 **마스킹**해 기록합니다.
