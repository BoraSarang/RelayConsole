# PLAN_alerts_relayconsole.md — Alerts 사이드바 v0.9.1

> 생성일: 2026-09-24 | 상태: **구현 (육안 대기)**
> 벤치마크: Zabbix · Grafana · Intune · Kandji · ManageEngine · iStat Menus
> 앱: **Relay Console** | 버전: **0.9.1** (Sites·Jobs 포함 시 1.0.0) | macOS 26.0
> PR **#10** (A) + PR-B (화면·액션·export)

---

## 1. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| AlertsView: 3탭 활성 / 무음 / 해소 | Slack · 이메일 · 에스컬레이션 |
| 필터: 심각도 · 기간 · 기기(source) | label 복합 검색 문법 |
| 기기(serial) 그룹핑 + 개별 전개 | 사용자 규칙 빌더 (12종 내장 유지) |
| 행 액션: ack · 메모 · mute(1h/24h) | 반복 mute timing (요일/시간) |
| `WatchEvent` + `source`/`ackAt`/`note`/`mutedUntil` | GRDB / SQLite |
| EventStore 필터 · update · export JSON/CSV | Late/NoData 심각도 |
| Apple connect/disconnect → WatchEvent | 설정 watch 토글 이관 |
| i18n `alerts.*` · 테스트 · DEBUG 주입 | 수동 resolve synthetic clear (v2) |

### 출처 (채택 근거)

| 기능 | 출처 |
|------|------|
| 3탭 Active/Muted/Cleared | Kandji Global Alerts |
| 심각도+상태+기간 필터 | Intune · Grafana History |
| serial 그룹핑 | Alertmanager group_by |
| ack + 메모 | Zabbix problem update |
| mute 만료 silence | Grafana Silence |
| export | ManageEngine (차별화) |
| Apple 이벤트 편입 | 현황 갭 (문자열만 EventStore 미진입) |

---

## 2. 스키마

```swift
enum WatchSource: String, Codable, Sendable { case android, apple }

// WatchEvent 신규 (Optional — 기존 JSON 하위호환)
var source: WatchSource?      // nil → android
var ackAt: Date?
var note: String?
var mutedUntil: Date?

enum AlertsState { case active, muted, cleared }
// active:  !isClear && mute 만료/없음
// muted:   !isClear && mutedUntil > now
// cleared: isClear
```

`WatchKind` 신규: `appleConnected` · `appleDisconnected`

- fingerprint: `serial:kind` (Apple serial = udid)
- decode 실패 시 새 필드 nil 기본 → Android 이력 그대로 로드

---

## 3. EventStore / ConsoleStore API

```swift
// 순수 필터 (테스트용 static)
WatchEventAlerts.filter(events, by: AlertsFilter, now:) -> [WatchEvent]

struct AlertsFilter {
  state: AlertsState? · severities: Set<WatchSeverity>?
  sources: Set<WatchSource>? · serial: String?
  since/until: Date? · search: String?
}

ConsoleStore:
  filteredWatchEvents(_:) -> [WatchEvent]
  updateWatchEvent(id:ackAt:note:mutedUntil:)  // save 동반
  exportJSON(events:) / exportCSV(events:)
```

- maxEvents **500** 유지 · GRDB 없음
- mute 만료: 파생 (저장 정리 v2)

---

## 4. AlertsView

```
[활성 n][무음 n][해소 n]  심각도▾  기간▾  기기▾   [JSON][CSV]
▸ [source] serial — n건
  ⚠ title  detail  시각  [확인][무음][메모]
```

- `ConsoleView.alerts` → `AlertsView` (placeholder 제거)
- severity 점 = 팝오버 팔레트 (critical/warning/info/clear)
- empty = `alerts.empty.*`

---

## 5. Apple 편입

- `AppleDeviceMonitor` 연결/해소 시 `WatchEvent` 생성 → `ingestWatch`
  - info · `source: .apple` · 제목 `event.appleConnected` / `event.appleDisconnected`
- 기존 문자열 `pushEvent` 유지 (팝오버 하위호환)

---

## 6. 설정 키

| 키 | 기본 |
|----|------|
| `relay.alerts.defaultPeriod` | `24h` |
| `relay.watch.*` 15종 | SettingsView 유지 |

---

## 7. 구현 순서 (PR)

| PR | 내용 |
|----|------|
| **A #10** | 스키마 · 필터/update/export · Apple WatchEvent · 테스트 |
| **B #11** | AlertsView 3탭·필터·그룹·액션·export · ConsoleView · 설정 · 0.9.1 |
| **육안** | 사용자 체크리스트 (아래) |

---

## 8. 검증 (DoD)

- [x] `swift test` **139/139**
- [x] 기존 JSON (신규 필드 없음) 로드 OK — Optional defaults
- [x] debug 0 error · i18n **315/315/315** missing 0
- [x] 금지 grep 0 · 버전 **0.9.1**
- [ ] 3탭 · 필터 · 그룹 · ack/mute/메모 재시작 유지 — **육안**
- [ ] Apple 연결/해소 Alerts 반영 · export 파일 — **육안**

### 육안 순서

1. 디버그 → **Alert critical 주입** → Alerts: 활성 1 · critical 표시
2. 행 **✓ 확인** → 실 표시 · **무음 1시간** → 무음 탭으로 이동
3. **메모** 인라인 저장 → 재실행 후 유지
4. **Alert 해소 주입** → 해소 탭
5. 기간·심각도·플랫폼 필터 · serial 그룹 접기/펴기
6. **JSON / CSV** export 파일 열람
7. 설정 → Alerts 기본 기간 변경 시 초기값 반영

---

## 9. 백로그 (v2+)

- 수동 resolve · Slack webhook · mute timing · unread 뱃지 · flapping · 30일 TTL · GRDB
