# PLAN — 메뉴바 AppKit 전환 (NSStatusItem) · T-2026-10-13-5

> 작성: 2026-10-13 · 플랫폼: macOS · 선행: `PLAN_menubar_devices.md` (A안 문자열 정렬 — 한계 실측으로 폐기)

## 1. 배경 — 왜 구조를 바꾸나

메뉴바 속도 표시를 SwiftUI `MenuBarExtra` label의 **단일 `Text`** 로 그려 왔다 (A안).
문자열 공백으로 열 정렬을 흉내 냈으나 실측에서 **DroidRelay와 닮지 않았다** (사용자 확정):

- 문자열 정렬은 **공백 칸 수**로만 폭을 못박는다. SF 폰트에서 공백·단위 글리프(K/M/B)의
  실제 pt 폭이 달라 **셀 경계가 흔들린다** (`6K` ↔ `60B` 시작점 어긋남 — 캡처 4배 확대 실측).
- DroidRelay는 셀마다 **`NSTextField` 고정폭 + 우측 정렬**이라 구조적으로 완전 정렬이다.
  필드 단위 정렬은 문자열로 재현 불가 — **렌더링 방식을 바꿔야 한다.**

부수 이득: macOS 26+ 에서 `MenuBarExtra` 씬이 시스템 설정으로 꺼지면 **크래시 로그 없이
프로세스가 조용히 종료**된다 (DroidRelay `StatusItemController` 교훈). `NSStatusItem`은
`isVisible = false` 로만 끝나 프로세스가 살아 있다.

## 2. 결정 — DroidRelay `StatusItemController` / `MenuBarSpeedView` 구조 이식

참조 구현: `~/Documents/Apps/DroidRelay/apps/macos/Sources/DroidRelayMac/`
(같은 사용자 앱 · 검증된 수치 그대로 옮긴다 — 새로 발견하지 않는다)

### 렌더링 규격 (DroidRelay 실측값 그대로)

| 항목 | 값 |
|---|---|
| 컨테이너 | `NSStatusItem.variableLength` + **`statusItem.view` 직접 교체** (button title·image·서브뷰는 전부 실패한 DroidRelay 실측) |
| 폰트 | `monospacedDigitSystemFont(9, .medium)` — 2줄 = 21pt < 메뉴바 22pt |
| 화살표 | SF Symbol `arrow.up/down` 11pt semibold, template |
| 아이콘 | RelayConsole `MenuBar-Online/Off` NSImage **18pt**, 두 줄 걸침 + 심각도 점 7pt |
| 열 폭 | 샘플 **`"1023M"`** (menuRateAlways 상한 5자)로 고정 측정 + 2pt, gap 2pt |
| 정렬 | `NSTextField.alignment = .right` + **`paragraphStyle.alignment = .right`** (둘 다 필요 — DroidRelay 실측) |
| 줄 높이 | `ascender - descender + leading` 실측, `baseY = (22 - lineH*2)/2` |
| 필드 | 4개 = 2열 × 2행 — 열 = `menuPickedColumns`(온라인·serial 정렬·최대 2) |

### 구조

```
RelayConsoleApp (SwiftUI App)
 ├─ MenuBarExtra scene 삭제
 ├─ body 평가 시 StatusItemController.shared.adopt(...) — openWindow/openSettings 클로저 주입
 │    + FloatingGraphController·WidgetDeepLink 클로저 주입 (구 label onAppear 이동)
 ├─ AppDelegate.applicationDidFinishLaunching → StatusItemController.shared.install()
 │    (install ↔ adopt 순서 무관 — 양방향 pending 안전 API)
 └─ Window/Settings scenes 그대로 유지 (창·설정은 SwiftUI)

StatusItemController (신규, App/)
 ├─ install(): NSStatusItem + RelayMenuBarView + 갱신 구독
 │    · 갱신: ConsoleStore.objectWillChange + UserDefaults.didChangeNotification (menubarSpeed/All)
 │    · 값: BriefingLogic.menuPickedColumns 재사용 — 순수 함수 테스트 그대로 유효
 ├─ adopt(): SwiftUI body 평가 시 클로저 주입 (openConsole 등 7개 + 딥링크/플로팅)
 ├─ togglePopover(): NSPopover(.transient) + NSHostingController(MenuBarPopoverView 360×560)
 ├─ 우클릭: NSMenu (콘솔 열기 · Relay 종료 — 기존 L10n 키 재사용)
 └─ 강한 참조: statusItem·popover·speedView 모두 컨트롤러가 붙든다 (해제 = 아이콘 소실)

RelayMenuBarView (신규, App/)
 └─ DroidRelay MenuBarSpeedView 레이아웃 동일 + RelayConsole 요소 (아이콘·심각도 점·2열 기기값)
      · 메뉴바 off 설정이면 필드 숨김(폭 0) → 아이콘만
      · 미측정은 "—" 유지 (0과 구분 [표시②]) — DroidRelay의 "빈 칸"과 차이
```

### MenuBarPopoverView 변경 (최소)

- `@Environment(\.dismiss)` 1건 → `var onClose: () -> Void` 주입 (NSHostingController+NSPopover
  에서 SwiftUI dismiss는 보장되지 않음) — floating toggle 닫힘 동작 유지
- `onAppear/onDisappear` (WindowFocus 팝오버 연동)는 그대로 — hosting view 부착/제거로 발동

## 3. 위험 · 대응

| 위험 | 대응 |
|---|---|
| `openWindow` Environment는 body 평가 시에만 유효 → AppKit 컨트롤러에서 창 열기 불가 | body 평가 시 `adopt()` 클로저 주입. install 전 호출이면 pending 후 install 시 적용 |
| `statusItem.view` 전환 시 `button` nil — toolTip·performClick 불가 | 클릭은 `NSView.mouseDown` 직접 수신 (DroidRelay 동일), 팝오버 기준 뷰는 `speedView` |
| 팝오버 열림/닫힘 알림 (WindowFocus 창 복원) | hosting onAppear/onDisappear 발동 — 실측 확인, 미발동 시 NSPopoverDelegate 보완 |
| AppKit 뷰 갱신 주기 | objectWillChange 구독 (push) — DroidRelay 500ms 폴링 불필요 |
| MenuBarExtra 제거로 label onAppear 사라짐 | 주입 코드 전부 `adopt()` 로 이동 — flush 패턴(WidgetDeepLink) 그대로 |

## 4. 검증 게이트 [HARD]

1. `swift test` 0 failed (기존 + 신규: 4필드 문자열/숨김 로직 순수 함수)
2. `./scripts/build-macos.sh debug` EXIT=0 (번들 재생성·재서명·앱 재시작)
3. L10n en/ko 1:1 (우클릭 메뉴 키 신규 시 동시 추가)
4. **캡처 판독 루프**: 재시작 후 30초 경과 → `screencapture -R612,0,900,45` → 4배 확대 판독 —
   열 정렬이 DroidRelay와 동일한지 (A안의 `6K/60B` 어긋남 재발 없음) **픽셀 확인 없이 완료 선언 금지**
5. 육안: 클릭→팝오버 열림/닫힘, 우클릭 메뉴, 콘솔/설정 창 열림, 심각도 점

## 5. 제외

- 메뉴바 2열·단위·설정 토글(`relay.menubarSpeed/menubarAll`) 기능은 **무변경** — 렌더만 교체
- 우클릭 메뉴는 최소 구성 (콘솔·종료) — 추가 항목은 사용자 요구 시
