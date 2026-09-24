# PLAN_health_score_relayconsole.md — S2 Device Health Score

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-czg`
> 모체: `RESEARCH_competitive_v1` §8 **P3 (S2)** · Stats·iStat 시각 점수
> 앱: **Relay Console** | 목표 버전: **1.11.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

배터리·발열·스로틀을 가중 합산한 **0–100 기기 건강 점수**를 대시보드·메뉴바 팝오버·헤더에 노출한다.
파생 지표만 계산(ADB 추가 수집 없음), 서버·클라우드 없음.

| 구성 (가중치) | 신호 | 가중 |
|---------------|------|------|
| Battery | `batteryLevel` · `batteryHealthPct`(SOH) · 충전 | **40%** |
| Thermal | `thermalStatus` 0–6 · 온도 °C | **40%** |
| Throttle | `cpuUsePercent` · `load1` | **20%** |

**밴드**: ≥80 good · ≥50 fair · 그 외 poor

### OUT
- 히스토리·추세 차트 · 새 ADB 수집 사이클 · Apple 스냅샷(Phase 2) · 알림 트리거 연동

---

## 2. 범위

| IN | OUT |
|----|-----|
| `HealthScoreLogic` 순수 점수·밴드 | 새 폴링 주기/커맨드 |
| HEALTH 카드 + 헤더 점수 칩 | 메트릭 아카이브 DB |
| `relay.cards.health` On/Off (기본 ON) | 위험 임계 알림 |
| Settings 카드 토글 1종 | — |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.cards.health` | Bool | `true` | HEALTH 카드 표시 (대시보드·팝오버) |

---

## 4. 모델·로직

```swift
// Sources/RelayConsole/Droid/HealthScore.swift
struct HealthBreakdown: Equatable {
  var total: Int      // 0...100
  var battery: Int    // 0...100
  var thermal: Int
  var throttle: Int
  var bandKey: String // settings-independent: health.band.good|fair|poor
}

enum HealthScoreLogic {
  static let batteryWeight = 0.4
  static let thermalWeight = 0.4
  static let throttleWeight = 0.2

  static func score(from snapshot: DeviceSnapshot) -> HealthBreakdown?
  static func bandKey(total: Int) -> String
  static func bandColorKey(total: Int) -> String // ok | warn | bad (OPColor 매핑용 라벨은 UI)
}
```

- `score`: 오프라인·데이터 전무 시 `nil`
- 배터리 점수: 레벨(충전 시 하한 보정) + SOH(없으면 100 가정) 평균
- 발열 점수: thermalStatus 등급 점수와 온도 점수의 max
- 스로틀 점수: CPU%·load1 중 존재하는 값의 min (보수적)
- 가중 합 후 0…100 clamp, `round`

---

## 5. UI

- **HEALTH 카드**: 총점 큰 숫자 + `ProgressView` + 3구성 바 + 밴드 라벨 (good=ok / fair=warn / poor=bad)
- **헤더 칩**: `Health → 92` (온라인·점수 존재 시, 팝오버 동일)
- **설정 → 카드**: HEALTH 토글

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `Sources/RelayConsole/Droid/HealthScore.swift` | 로직 (신규) |
| `Sources/RelayConsole/Views/DroidCards.swift` | `health` 카드 |
| `DroidDashboardView` · `MenuBarPopoverView` | 카드 노출 + 헤더 칩 |
| `App/ConsoleStore.swift` | `relay.cards.health` |
| `Views/SettingsView.swift` | 카드 토글 + 버전 표시 |
| `Tests/.../HealthScoreTests.swift` | 점수·밴드·nil 경계 |
| i18n 3처 | `droid.card.health.*` · `settings.cards.health` |
| 버전 7처 | **1.11.0** |

---

## 7. DoD

- [x] 가중 합·밴드·nil·경계(0/100·오프라인) 회귀 테스트
- [x] 대시보드 + 팝오버 HEALTH 카드 · 헤더 칩
- [x] 카드 On/Off · Settings 토글
- [x] i18n 3처 parity **506키** · 금지 grep 0 · `%s` 0
- [x] `swift test` **59 + 219** · `build-macos.sh debug` **1.11.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.11.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md · McpProtocol.serverVersion
