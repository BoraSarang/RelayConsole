# PLAN — macOS 위젯 (WidgetKit) · v1.15.0

> **수립일**: 2026-09-25 · **범위**: 3-family 전체 + Apple Development 서명 통일 + App Group(가이드 패턴)
> **참조**: `/Users/lee/Documents/AGENTS/development/guide/macos-widget.md` (TubeKeep 검증 사례)

---

## 1. 목표

메뉴바를 열지 않아도 **데스크톱/알림센터에서 한눈에** 보는 관제 요약 — "메뉴바에서 끝나는 관제"의 연장.

| Family | 내용 |
|---|---|
| `systemSmall` | tone 배지(critical/정상) + 선택 기기 `identLabel`·배터리%/충전/발열/오프라인 |
| `systemMedium` | 브리핑 한 줄(+critical 칩) · 사이트 4행(상태 dot + 7d%) · 기기 2행 + 작업 지연 |
| `systemLarge` | 브리핑 + 기기 3행 + 사이트 6행 + 최근 이벤트 3행(HH:mm·severity·제목·ident) + 마지막 업데이트 |

- 다크 전용 관제탑 토큰 (#1c1f2a · 숫자 SF Mono) — `docs/DESIGN.md` v2 승계
- 탭 딥링크 `relayconsole://<target>` (console/alerts/sites/jobs/insights/processes/logs/appnetwork/settings)

## 2. 구조

```
Sources/RelayWidgetCore/   ← SPM 타깃 (앱·위젯 공용 · public API)
  WidgetSnapshot.swift     모델 (schema v1) · tone/isEmpty · preview
  WidgetSnapshotStore.swift App Group 파일 저장소
Sources/RelayConsole/App/
  WidgetSnapshotSync.swift 60s 스로틀 기록 + WidgetCenter 리로드 · WidgetSnapshotBuilder(순수)
  WidgetDeepLink.swift     relayconsole:// 라우팅 (클로저 미주입 시 pending 보류)
Sources/RelayWidget/       ← xcodegen 전용 (SPM 미등록)
  RelayWidgetBundle(@main) · Provider · RelayWidgetView(3종) · WidgetStrings
WidgetXcode/               project.yml + Info-Widget.plist (xcodegen 생성)
Entitlements/              RelayConsole.entitlements(App Group만) · RelayWidget.entitlements(sandbox+App Group)
```

- **공유 매체**: App Group `6GPJQ7BQC9.com.borasarang.relayconsole` 컨테이너의 `widget-snapshot.json` (UserDefaults suite 대비 sandbox 경계 경로 예측 가능)
- **동기화**: `ConsoleStore` objectWillChange + UserDefaults.didChange → throttle 60s → 기록 → `WidgetCenter.reloadTimelines(ofKind: "RelayStatusWidget")` · 종료 시 flush
- **위젯 타임라인**: 즉시 1 entry + `.after(15분)` 예비 주기 (실시간성은 앱이 유도)
- **[표시①]** 스냅샷의 `ident`는 앱이 `identLabel`로 확정해 저장 (네트워크 `IP:PORT` 원문, 마스킹 없음 — 실측 확인 `10.233.247.205:5555`)
- **[표시②]** 모든 family 하단에 "마지막 업데이트 N" 표시 · 미측정 사이트는 `unknown`/nil (0으로 뭉뚱그리지 않음)
- **i18n**: 앱과 동일 `Localizable.strings` 공유 (ko/en **707키** 1:1, `widget.*` 17키 신규) — appex에 lproj 복사 확인 완료

## 3. 빌드 · 서명 (가이드 §4 그대로)

1. `swift build` (앱) → 번들 조립
2. `xcodegen generate` → `xcodebuild -target RelayWidget` (**SPM appex는 WidgetKit bootstrap 크래시 — 금지**)
3. `build/Debug/RelayWidget.appex` → `Contents/PlugIns/` 복사 (매번 재생성)
4. 앱 서명: **Apple Development (76811B50… · TEAM 6GPJQ7BQC9)** + `RelayConsole.entitlements` — 앱과 appex 팀 통일
5. `codesign --verify --deep --strict`

- ad-hoc 제거 근거: 팀 불일치 → 갤러리 미표시 (가이드 §2.1) · App Group은 `TEAMID.` 필수
- 앱은 **비샌드박스 유지** (adb/scrcpy 외부 호출) · 위젯 appex만 샌드박스

## 4. 검증 결과 (2026-09-25)

| 항목 | 결과 |
|---|---|
| `swift test` | **417 통과** (swift-testing 313 + XCTest 104, 신규 WidgetSnapshotTests 18) |
| `./scripts/build-macos.sh debug` | **EXIT=0** (위젯 xcodebuild + 서명 검증 통과) |
| appex/NSExtensionPointIdentifier | `com.apple.widgetkit-extension` ✓ |
| 앱·appex 서명 | 둘 다 Apple Development · TeamIdentifier=6GPJQ7BQC9 · `--verify --deep --strict` OK |
| entitlements | 앱: application-groups / 위젯: sandbox+application-groups ✓ |
| `pluginkit -m -A -D` | `com.borasarang.relayconsole.widget(1.15.0)` 등록 ✓ |
| 크래시 리포트 | RelayWidget **0건** ✓ |
| App Group 컨테이너 | 생성 + `widget-snapshot.json` 기록 갱신 확인 ✓ (비샌드박스 앱 기록 성공) |
| 앱 lproj → appex | `Contents/Resources/{ko,en}.lproj/Localizable.strings` ✓ |
| 딥링크 | `open relayconsole://alerts` → 콘솔 창 오픈 ✓ |

## 5. 남은 육안 (사용자)

가이드 §1 경로로 갤러리 확인:
```
데스크톱 빈 곳 우클릭 → "위젯 편집" → "+" 또는 검색 "Relay"
→ Relay 상태 (small/medium/large) 데스크톱/알림센터로 드롭
```
- 확인 1: 갤러리에 **Relay Console** 표시 (안 뜨면 가이드 §5 체크리스트)
- 확인 2: 3종 위젯 데이터 표시 (앱이 1회 실행된 상태 · 현재 실행 중)
- 확인 3: 위젯 탭 → 콘솔 창 열림 · `relayconsole://alerts` → Alerts 탭
- 확인 4: 위젯 추가 후 `pgrep -fl RelayWidget` + 크래시 리포트 0건 재확인

## 6. 설정 키

- 신규 없음 (기록 주기·주소는 하드코딩 상수: App Group ID, kind `RelayStatusWidget`, 파일 `widget-snapshot.json`)
