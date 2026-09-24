# PLAN_floating_graphs_relayconsole.md — 기기 그래프 플로팅창 (A7/F1)

> 생성일: 2026-09-24 | 상태: **구현 완료 — 사용자 통합 테스트 대기** (투명도·헤더 안정화 포함)
> 모체: 사용자 요청 · 벤치마크 **TetherLens** `FloatingWindowController` + `FloatingWindowView`
> 앱: **Relay Console** | 목표 버전: **1.4.0** | 최소 OS: **macOS 26.0**
> bd: `RelayConsole-d2e`
> 이전 스프린트: A5/A2 **홀드**

---

## 1. 목표

팝오버/콘솔 기기 대시보드의 그래프를 **항상 위 떠 있는 플로팅 창**에서 연속 관찰.

| 항목 | 내용 |
|------|------|
| 기본 그래프 | **Network**(up/down) · **CPU**(%) |
| 진입점 | 팝오버 카드 핀 버튼 · Settings · 메뉴바 플로팅 토글 |
| 표시 카드 선택 | Network·CPU **기본 on** + GPU·Memory 토글 (TetherLens 최종 패턴 채택) |
| 개인정보 | 전부 로컬 (외부 전송 없음) |

### 출처 (TetherLens)
- `FloatingWindowController.swift` — borderless `NSPanel` · `.nonactivatingPanel` · `.floating` · 드래그·높이 자동 fit·위치 유지
- `FloatingWindowView.swift` — 네트워크 상단 고정 + CPU/GPU/RAM 토글 · 호버 닫기
- 채택: **복합 패널 1개 + 카드 show/hide** (개별 차트 detach는 TetherLens도 제거한 패턴 — 미채택)

---

## 2. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| 단일 플로팅 `NSPanel` (항상 위 · 모든 Space) | 카드별 개별 창 detach · 다중 인스턴스 |
| 기본 **Network + CPU** · GPU/Memory 토글 | Apple 기기 (메트릭 히스토리 없음 — Android 전용) |
| 기존 `OPSparkline` + 카드 축소 재사용 (SwiftUI Charts 미도입) | 축·툴팁·zoom 인터랙티브 차트 |
| `relay.float.*` 설정 · Settings 섹션 · 팝오버 진입 | 네트워크 up/down 분리 히스토리 개편 (별 이슈) |
| 위치·표시 카드·**투명도** UserDefaults 유지 | (투명도는 사용자 요청으로 IN 전환 — `relay.float.opacity`) |
| 헤더 고정 슬롯 (hover opacity-only) · `menuIndicator` 숨김 — 출렁임 방지 | 실시간 네트워크 샘플링 주기 변경 |
| i18n 3처 · 금지 grep · `swift test` · `build-macos.sh debug` **1.4.0** | 카드별 개별 창 detach (아키텍처 OUT 유지) |

### 아키텍처 (TetherLens 이식)

```
ConsoleStore (ObservableObject — Notification 브리지 불필요)
  │ metrics(for: serial) / selectedDevice / card* 토글
  ▼
FloatingGraphController.shared  (NSPanel · 신규)
  └─ NSHostingController(FloatingGraphView)
        ├─ 기기 헤더 (이름 · online)
        ├─ Network 카드 (항상 on · DroidCards.network 축소)
        ├─ CPU 카드 (기본 on)
        └─ GPU / Memory (옵션 · @AppStorage)
```

**WindowFocus 주의:** `dismissMenuBarPanels()`가 `.statusBar` 레벨 NSPanel을 닫음 → 플로팅 그래프 패널은 **제외 목록**에 `floatingGraphWindowID` 추가 (AlertBanner 패턴).

---

## 3. 설정키 (`relay.float.*`)

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.float.enabled` | Bool | false | 마지막 표시 여부(재실행 자동 show 아님 — 명시 toggle) |
| `relay.float.showNetwork` | Bool | **true** | Network 카드 |
| `relay.float.showCPU` | Bool | **true** | CPU 카드 |
| `relay.float.showGPU` | Bool | false | GPU 카드 |
| `relay.float.showMemory` | Bool | false | Memory 카드 |
| `relay.float.origin` | String | nil | `"x,y"` 위치 유지 |
| `relay.float.opacity` | Double | 1.0 | 패널 alpha (0.35…1.0 clamp) |

**최소 1개 카드 보장:** 전부 off면 Network를 강제로 표시 (TetherLens network always-on).

---

## 4. UI

### 4.1 플로팅 패널 (신규 `FloatingGraphView`)

```
┌─────────────────────────────┐
│ ● Pixel 7 · USB      [⋯][×]│  ← 헤더 = 드래그 영역 · 호버 시 버튼
│ ─────────────────────────── │
│ 네트워크  ↑0.2 ↓1.4 MB/s    │
│ ▁▂▃▅▆▃▂▄ (sparkline)       │  ← 항상 on
│ ─────────────────────────── │
│ CPU  23%  ████████░░        │
│ ▂▅▇▆▄▃▂▁ (sparkline)       │  ← 기본 on
└─────────────────────────────┘
```

- 스타일: borderless · `level = .floating` · `nonactivatingPanel` · 다크 `0x0F111A` · 모서리 12 · 그림자 on
- 폭 **300**pt · 높이 = 콘텐츠 auto-fit (TetherLens `fitToContent` 이식)
- 위치: `relay.float.origin` 유지 · 화면 밖 clamp
- 닫기: 호버 × → `hide()` (`orderOut`, `isReleasedWhenClosed = false`)
- [⋯]: 투명도 Slider + 카드 토글 Menu (menuIndicator 숨김)
- 반투명 아이콘: popover 슬라이더 (0.35…1.0)
- 헤더 우측 **고정 74pt 슬롯** — insert/remove 없이 opacity/hitTesting만 (출렁임 방지)

### 4.2 진입점

| 위치 | 동작 |
|------|------|
| 팝오버 `cards` 상단 | 플로팅 아이콘 버튼 → `FloatingGraphController.toggle()` |
| Settings → 카드 (또는 일반) | “플로팅 그래프” 토글 + 카드 4개 체크 |
| 메뉴바 footer | 작은 그래프 아이콘 (선택 — MVP에서 생략 가능) |

`openFloat` 클로저는 `openProcesses` 패턴으로 `RelayConsoleApp` → `MenuBarPopoverView` 주입.

### 4.3 데이터 (기존 유지 — 변경 없음)

- `store.metrics(for:)` → `OPSparkline` 재사용 (Network·CPU 히스토리 이미 존재)
- 네트워크는 기존 단일 series (up+down) — **분리 개선은 OUT** (다음 이슈)
- Android 전용 · Apple 선택 시 빈 상태 안내 1줄

---

## 5. 파일 변경 목록

| 파일 | 변경 |
|------|------|
| `Sources/RelayConsole/App/FloatingGraphController.swift` | **신규** — NSPanel 싱글턴 · toggle/show/hide · drag · fitToContent · origin 저장 |
| `Sources/RelayConsole/Views/FloatingGraphView.swift` | **신규** — 헤더 + 카드 스택 + 토글 Menu |
| `Sources/RelayConsole/App/WindowFocus.swift` | 플로팅 그래프 ID 제외 (dismiss에서 보호) |
| `Sources/RelayConsole/App/RelayConsoleApp.swift` | 명령/진입 wiring (필요 시) |
| `Sources/RelayConsole/Views/MenuBarPopoverView.swift` | 카드 영역 상단 플로팅 토글 버튼 · `openFloat` 클로저 |
| `Sources/RelayConsole/Views/SettingsView.swift` | 플로팅 섹션 (enabled + 카드 4 + **투명도 슬라이더**) · about **1.4.0** |
| `Sources/RelayConsole/Views/DroidCards.swift` | shell에 옵션 핀/Float 액션 (선택 — MVP는 카드 상단 버튼만) |
| `Resources/Localizable.xcstrings` + ko/en `.strings` | `float.*` 신규 키 (3처 parity) |
| `Resources/Info.plist` 등 버전 7처 | **1.4.0** |
| `Tests/RelayConsoleTests/FloatingGraphTests.swift` | **신규** — 카드 선택 · origin 파싱 · **clampOpacity/storedOpacity** |
| `docs/TODO.md` · `AGENTS.local.md` · `README.md` | 기능·버전 기록 |

---

## 6. DoD

- [x] `FloatingGraphController` toggle/show/hide · 위치 재실행 유지
- [x] 기본 표시 **Network + CPU** · GPU/Memory 토글 저장
- [x] 카드 전부 off 방지 (Network 강제 유지)
- [x] 팝오버 → 플로팅 진입 · Settings 토글 동기화
- [x] `WindowFocus.dismissMenuBarPanels`가 플로팅 창을 닫지 않음
- [x] 헤더 고정 슬롯 · 메뉴 오픈 시 레이아웃 출렁임 없음
- [x] 투명도 (`relay.float.opacity`) — 플로팅 popover + Settings 슬라이더 · panel alpha 동기화
- [x] i18n 3처 동치 (430) · `%s` 없음
- [x] 금지 grep 0 · `print(` DebugLogger만
- [x] `swift test` 통과 · `./scripts/build-macos.sh debug` **1.4.0**
- [ ] **사용자 통합 테스트** (팝오버 핀 · 카드 토글 · 드래그 · 닫기 · 투명도 · 헤더 안정 · Settings 동기화)

---

## 7. 버전 1.4.0 동기화처

`Resources/Info.plist` · `scripts/build-macos.sh`(3) · `AppDelegate` · `SettingsView` · `MenuBarPopoverView` · `AGENTS.local.md` · `README.md`

---

## 8. 리스크

| 리스크 | 대응 |
|--------|------|
| `WindowFocus`가 패널 auto-dismiss | 제외 ID 목록 (`alertBannerWindowID` 옆) |
| nonactivating + borderless drag 이슈 | TetherLens local event monitor 이식 |
| Apple 기기 메트릭 없음 | Android-only 안내 · 빈 상태 |
| 네트워크 series가 10s 이상 coarse | MVP 수용 · 분리/샘플링은 별 이슈 |
| `OPSparkline`이 작게 보임 | 플로팅 전용 height 40~48 승격 |
