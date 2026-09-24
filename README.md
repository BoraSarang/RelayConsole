# Relay Console

> macOS 메뉴바에 상주하는 **개인 안드로이드·사이트·작업 관제탑**.  
> 서버를 띄우지 않고도 폰·URL·크론 하트비트를 한 배지와 한 알림 폭으로 지킵니다.

- **플랫폼**: macOS 26.0+ (SwiftUI `MenuBarExtra`)
- **번들 ID**: `com.borasarang.relayconsole`
- **버전**: 1.4.0
- **언어**: 한국어 · English

---

## 왜 Relay Console인가

| | Relay Console | Uptime Kuma류 | ADB GUI·메뉴바 유틸 |
|--|---------------|---------------|---------------------|
| 메뉴바 상주 관제 | ✅ | ❌ | 일부 |
| 안드로이드 실시간 카드 | ✅ | ❌ | 스냅샷 위주 |
| 사이트 + 크론 하트비트 | ✅ | 사이트만 | ❌ |
| 감시·ack·무음·메모 | ✅ | 임계 알림 | ❌ |
| ntfy / Slack 외부 알림 | ✅ | ✅ | ❌ |
| 설치·운영 부담 | **낮음** | 서버 필요 | 낮음 |

**한 줄**: *메뉴바에서 끝나는 관제 — 폰·사이트·작업을 한 배지로.*

---

## 기능

### 메뉴바 · 팝오버
- 기기 수·배터리·critical 주황 배지
- 팝오버: **아침 브리핑 한 줄**(사이트·지연 작업·폰·critical), 사이트 요약, Jobs overdue, 발열 배너, 권장 후속 조치 체크리스트
- 종료 버튼 + 확인 알림
- 설정 → 일반에서 브리핑 표시 on/off

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
  App/        ConsoleStore · EventStore · Alerts 배너 · AppDelegate
  Droid/      ADB · 감시 엔진 · 스냅샷 · scrcpy
  Apple/      libimobiledevice Phase1
  Sites/      HTTP·TCP·ping 체커
  Jobs/       하트비트 서버
  Views/      메뉴바 팝오버 · 콘솔 · 설정 · Alerts
  Utils/      파서 · ThresholdGate · NotifyChannel · DebugLogger
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
- 로그·외부 알림에 기기 **전체 시리얼**을 남기지 않습니다 (뒤 4자리만).
- 토큰·웹훅 URL은 하드코딩하지 않습니다.
