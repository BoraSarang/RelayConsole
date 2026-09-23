# 감시 이벤트 시스템 — RESEARCH & 설계 (보완판 v1.1)

> Android S22 대시보드 (CPU 8코어 18%·43°C / GPU Adreno 730 / MEM 4.9/7GB / SENSORS 8/39 / THERMAL 42.6°C) 기반, Apple Tier1/2 확장 고려

## 0. 목표
스로틀링을 시작으로 **임계값 + hysteresis + 쿨다운 기반 감시 이벤트**를 RelayConsole에 붙이고, 적중 시 **알림·기록·복구 안내**까지 끊김 없이 잇는다.

## 1. 아키텍처 (하이브리드 + 보완)

```
[수집기]                    [게이트]              [이벤트 파이프]           [후속 조치]
DeviceMonitor 5s ──┐
  thermalStatus    ─┼─→ ThresholdGate ──→ MonitorEvent ──→ ConsoleStore.ingest
  batteryStatus    ─┤     (enter/clear     (kind+severity+   ├→ EventStore (GRDB 5000건)
  PSI / load / mem ─┤      cooldown+        fingerprint)      ├→ 시스템 알림 (UNUserNotification)
  SettingWatch     ─┘      hysteresis)                         ├→ ntfy 역푸시 (옵션)
  LogcatWatch ────────────────────────────────────────────────┘└→ 팝오버/콘솔 "Latest events"
                                                              └→ 메뉴바 배지 (초록→주황)
```

### 핵심 컴포넌트 3개 (보완)

| 컴포넌트 | 역할 | 위치 | 보완점 |
|----------|------|------|--------|
| **ThresholdGate** | enter/clear/cooldown + hysteresis, 중복 발화 방지 | `Utils/ThresholdGate.swift` | `enterThreshold != clearThreshold`로 플래핑 방지. State Machine: normal → triggered → cooldown → normal |
| **WatchRule** | 규칙 정의 (id, metric, 임계, 주기, 플랫폼) | `Models/MonitorEvent.swift` 확장 | `platform: .androidOnly / .appleOnly / .all` 필드 추가. Apple `thermalState` 매핑용 |
| **AlertAction + Event** | 이벤트 발생 후 무엇 할지 | `ConsoleStore.notify` 확장 | `severity` + `fingerprint(deviceID+kind+metric)` 도입으로 kind 비대화 방지 |

## 2. 이벤트 정의 (Phase별)

### Phase 1 — 즉시 구현 (기존 수집기 재사용)

| 이벤트 | 진입 | 복귀 (hysteresis) | 후속 조치 |
|--------|------|-------------------|-----------|
| **스로틀링** | Thermal Status ≥3 (SEVERE) / iOS thermalState ≥2 (serious) | status ≤1 (MODERATE 이하), 60s 쿨다운 | ① 배너 "스로틀링 해제" / ② ntfy priority=4 / ③ 콘솔 이벤트 1건 / ④ 메뉴바 주황점 |
| 충전 전이 | status 전이 (0→1, 1→2) | 전이성 (자동 해제 없음) | 팝오버 배지 "충전 중" 토글 |
| 보호모드 | mode 0→1 | 1→0 | 설정 카드 하이라이트 |
| 설정 변경 | key delta | 로그성 | SettingWatch 그대로 |

### Phase 2 — 임계 알림

| 이벤트 | 진입 | 복귀 | 후속 조치 |
|--------|------|------|-----------|
| **PSI 압박** | memory some avg10 ≥ 5.0 | <3.0 120s 유지 | "메모리 압박" 알림 + Top RSS 스냅샷 (MEM 카드 데이터 재사용) |
| **load 급증** | load1 ≥ 코어수×2 (S22 8코어 → 16) | < 코어수×1 60s | 알림 + 포그라운드 앱 표시 |
| **메모리 부족** | MemAvailable < 10% | >20% 60s | 알림 + "정리 권장" |
| **배터리 건강 하락** | Bsoh 90→85 구간 하락 | 1회성 (fingerprint로 중복 방지) | 이력 타임라인 기록 |
| **신호 급락** | RSRP Δ ≤ −6 또는 level 하락 | level 회복 | 네트워크 카드 워닝 |

### Phase 3 — 스트림/복합

| 이벤트 | 소스 | 후속 조치 |
|--------|------|-----------|
| ANR/크래시 | logcat 키워드 확장 | 즉시 알림 + 해당 라인 저장 |
| 복구 자동 알림 | clear 조건 충족 | "복구됨" 알림 (다운→업 패턴) |

## 3. 알림 파이프 상세

```
MonitorEvent 발생 (kind+severity+fingerprint)
  ├─ [A] ConsoleStore.recentEvents.insert(0) → 팝오버 "Latest" 갱신
  ├─ [B] EventStore.append → GRDB 영구 보관 (최대 5000, FIFO)
  ├─ [C] 알림 필터
  │     설정 대상: throttlingAlert, psiAlert, memoryAlert, healthDrop, signalDrop
  │     2중 안전: Gate.cooldown (60s) + notify.lastFired[fingerprint] (5분)
  ├─ [D] UNUserNotification (macOS)
  ├─ [E] ntfy 역푸시 (Notify 모듈, priority 매핑)
  │     스로틀링/크래시 → priority 4 / high
  │     설정변경/충전 → priority 3 / default
  └─ [F] 메뉴바 배지
        심각 이벤트 존재 시 MenuBar-Online 아이콘 + 초록점 → 주황점 교체
        (다크모드 대응: white_22 아이콘 사용, 점은 컬러 유지)
```

### 설정 UX (제안)

```
설정 → 감시 알림
  ☑ 스로틀링 (SEVERE 이상)          [즉시]  플랫폼: Android+iOS
  ☑ 메모리 압박 (PSI ≥ 5)           [5분 쿨다운]  플랫폼: Android
  ☑ 배터리 건강 하락                [1회성]  플랫폼: All
  ☐ 충전 시작/종료                  [시스템 알림만]
  임계값: [온도 40°C] [PSI 5.0] [Mem 10%]
  복구 시 "해제 알림" 받기  ☑
```

## 4. 보완 설계 상세

### 4.1 Hysteresis

기존 `>=3`만 하면 3↔2 반복 시 플래핑으로 알림 10회 발생.
```
enterThreshold = 3 (SEVERE)
clearThreshold = 1 (LIGHT)
상태: 0 NONE → 3 SEVERE 진입 → active → 1 이하로 60초 유지해야 clear
```
Apple 매핑: `enter 2 (serious), clear 0 (nominal)`

### 4.2 Fingerprint + Severity

kind를 20개로 늘리지 말고, fingerprint로 중복 방지.
```
fingerprint = "\(deviceID):\(kind.rawValue):\(metricKey)"
severity = .info / .warning / .critical
예: "S22:throttling:thermalStatus" / "S22:psi:memorySome"
```
lastFired[fingerprint] 5분 체크 → 같은 기기+같은 지표 중복 알림 0건

### 4.3 플랫폼 추상화

```swift
enum PlatformSupport { case androidOnly, appleOnly, all }
struct WatchRule {
  let id: String
  let metric: MetricKey // thermalStatus, psiSome, load1, memAvailablePct, bsoh, rssi
  let platform: PlatformSupport
  let enter: Double
  let clear: Double
}
```

## 5. 실행 계획 (2갈래 중 A 권장)

### 경로 A — 구현

| 단계 | 작업 | 산출물 | 검증 |
|------|------|--------|------|
| A1 | `ThresholdGate` 유틸 + 단위 테스트 | `ThresholdGate.swift` + Tests | enter/clear/cooldown/플래핑 4케이스 |
| A2 | 스로틀링 이벤트 연결 (DeviceMonitor thermalStatus delta) | kind `.throttling` + severity | 실기기 Status 3→알림 1회 |
| A3 | ConsoleStore.notify 필터 확장 + 5분 쿨다운 | notify 규칙 + EventStore | 중복 알림 0건, GRDB 5000건 FIFO |
| A4 | 충전/보호모드/설정 확장 | 추가 kind | 팝오버 이벤트 표시 |
| A5 | PSI/load/mem 임계 (Phase2) | WatchRule 테이블 초안 | S22에서 load 16 초과 시 1회 |
| A6 | 문서화 + PLAN 등록 | 본 문서 | — |

**소요**: A1–A3 핵심 반나절, A4–A5 하루.

### 경로 B — 체크리스트

```markdown
- [ ] 1. ThresholdGate 유틸 생성 (enter/clear/cooldown + hysteresis)
- [ ] 2. MonitorEventKind에 throttling + severity + fingerprint 추가
- [ ] 3. DeviceMonitor.thermalStatus delta → onEvent 발행
- [ ] 4. ConsoleStore.notify 대상 kind 확장 + 5분 쿨다운
- [ ] 5. 설정 화면: 알림 on/off + 임계값 편집 + 플랫폼 뱃지
- [ ] 6. ntfy priority 매핑 (스로틀링=4, 설정변경=3)
- [ ] 7. 메뉴바 경고 배지 (주황점 white_22 아이콘)
- [ ] 8. 실기기 검증: 게임 실행 → Status 3 → 알림 1회 → 60s 후 복구 알림
- [ ] 9. 리서치 문서화 + PLAN_v0.x 등록
```

## 6. 리스크·주의

| 리스크 | 대응 |
|--------|------|
| 알림 폭주 | 2중 쿨다운 (Gate 60s + notify 5분) + hysteresis clear 1 |
| 무거운 dumpsys 상시 폴링 | 기존 5s 주기 유지, 메모리/PSI만 5s, 나머지는 10s |
| kind 비대화 | enum 대신 severity+fingerprint, Phase3부터 WatchRule 테이블로 |
| Outpost/이중 저장소 | RelayConsole에 먼저 붙임 (수집기 완성). Outpost는 ntfy 수신만 |
| 복구 알림 피로 | "해제 알림" 토글 기본 ON, critical만 복구 알림 |

## 7. 다음 액션

**선택 3번: 문서 저장 → A1 착수 (ThresholdGate e2e)**

- 본 문서 `docs/research/RESEARCH_watch_events.md` 커밋
- `Utils/ThresholdGate.swift` 구현 + 테스트
- 실기기 S22로 스로틀링 유도 테스트

---
작성: 2026-09-23, 기반: Android Relay S22 대시보드 + Apple Relay 계획서
