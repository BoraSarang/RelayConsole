# PLAN_refactor_perf_stability_macos

> 성능 · 안정성 리팩토링 6단계 — 2026-09-26 · macOS
> 롤백 지점: 태그 `pre-refactor-perf` (main `27e90e3`)
> 브랜치: `chore/macos-refactor-p1-adapter-safety` (단계별 분기)
>
> **개정 이력**: 3차 조사(상태관리·수명주기) 결과로 1단계에 5건 추가 → 5단계 → **6단계**.
> 추가된 5건은 전부 실코드 재검증 완료 ([HARD] 위반 1건 포함).

---

## 0. 실측 기준선 (리팩토리 전)

| 지표 | 현재값 | 예산 | 판정 |
|---|---|---|---|
| adb 프로세스 (기기 1대) | 분당 120~240개 (10초 샘플링 62관측 ÷ 데몬 보정) | — | ❌ 과다 |
| slow 틱 adb 호출 | 기기당 25회 | — | ❌ |
| fast 틱 adb 호출 | 기기당 6회 | — | ❌ |
| 이벤트 1건당 JSON | 500건 전량 · **메인 스레드** | — | ❌ |
| `ConsoleStore` 관측 뷰 | 23개 body · 5초마다 전부 재평가 | — | ❌ |
| RSS (13시간 가동) | 155.5 MB | 300 MB | ✅ 여유 144.5MB |
| `swift test` | 332 passed / 0 failed / 6.5s | 60s | ✅ |
| `swift build` (캐시) | 3.7s | — | ✅ |
| adb 단일 호출 | 워밍 75~100ms · 콜드(doze) ~500ms | — | 정보 |

### 측정 방법 기록
- adb 호출 단위 비용: 동일 명령 5회 반복 → 워밍 75~100ms
- 배치화 가능성: `/proc` 6파일 개별 `cat` **342ms** vs 기기측 `for` 루프 1회 **125ms** → **2.7배**
- spawn 빈도: `pgrep -x adb` 16.7ms 간격 10초 샘플 → 662관측 − 상주 데몬 600 = 62. 44ms 프로세스를 16.7ms로 샘플링하므로 실제 spawn은 2~4/초

---

## 1단계 — 어댑버 안전화 + 즉시 결함 (안정성 · 저위험 · 최고 효과)

> 1-1~1-3은 최초 조사분, **1-4~1-8은 3차 조사에서 발견·실코드 재검증한 항목**.
> 전부 "이미 동작하는 앱"의 국소 수정이므로 위험도가 낮고 효과는 즉시다.

### 1-4 `runSiteCheck` await 전 인덱스 캡처 → 사이트 데이터 오염 (High · 신규)
`ConsoleStore.swift:320-330`
```swift
guard let idx = sites.firstIndex(where: { $0.id == site.id }) else { return }
let check = await SiteChecker.shared.check(sites[idx])   // 최대 10초
sites[idx].appendCheck(check)                            // ← idx 재확인 없음
```
`await` 동안 `removeSite`·`updateSite`·`addSite`·`clearSitesJobsDebug`가 `sites`를 재배열하면 `idx`가 **다른 사이트**를 가리킴.
→ A 사이트의 HTTP 상태·latency·SSL 만료일이 B 사이트 이력에 기록. 업타임%·dayBars·down/up 전이·위젯 siteUp/siteDown 오염.

**조치**: `await` 후 인덱스·대상 재조회. 불일치 시 결과 폐기 + `DebugLogger` 기록.

### 1-5 `ScrcpyController` 종료 핸들러 세대 혼동 race (Med · 신규)
`ScrcpyController.swift:243`
```swift
if self.process === p || self.runningSerial == serial {
```
`launch(A)` → `stop()` → 즉시 `launch(A)` 하면 **옛 프로세스의** terminationHandler가 `runningSerial == "A"`로 매칭되어 **새 프로세스 상태를 nil로 덮어씀**. 결과: scrcpy 실행 중인데 UI는 "미실행", `toggle` 중복 실행, bring-front 전부 스킵.

**조치**: 판정을 `self.process === p` 단독으로 (동일 serial 조건 제거). 프로세스 동일성은 identity로만 판정.

### 1-6 하트비트 토큰 평문 로그 — **[HARD] 위반** (신규 · 최우선)
`ConsoleStore.swift:566`
```swift
DebugLogger.shared.info("Jobs", "[INFO] [FEATURE] 작업 추가 \(job.name) token=\(job.token)")
```
`[HARD] 로그 마스킹` 위반. 하트비트 토큰은 **원격 curl 호출이 가능한 비밀값** → stdout/unified log 노출. `DebugLogger`에 마스킹 로직이 전무하며 `NotifyChannel.maskSecret`(124)도 **호출처 0건**.

**조치**: 토큰을 `maskSecret`으로 교체. "토큰 평문 금지" 테스트 추가.

### 1-7 기기 0대인데 메뉴바 아이콘이 "Online" — [표시②] 위반 (Med · 신규)
`RelayConsoleApp.swift:199-201`
```swift
let empty = store.inventory.devices.isEmpty   // "한 번이라도 본 기기" 기준
```
`DeviceInventory.markOffline`(279-282)는 플래그만 바꾸고 배열에서 제거하지 않음 → 첫 기기 1회 연결 후엔 기기 0대여도 `isEmpty == false` → **사용자를 오도**. 부수 영향: Wi-Fi IP 변경 시 새 항목 + `metricsHistory` 60점 ring 누적으로 **상시 실행 앱의 메모리 무한 증가**(3단계 F8·F9와 동일 근원).

**조치**: 아이콘 판정을 `devices.contains(where: \.isOnline)`로. 오프라인 기기 제거(=`prune`)는 3단계에서 메모리와 함께 처리.

### 1-8 `WifiAdb.disconnect` 성공인데 오류 스타일 — [표시②] 위반 (Low · 신규)
`WifiAdb.swift:196-213` — `enableWifi`(140-141)·`connect`(176-177)는 진입부에서 `statusIsError = false`를 리셋하지만 `disconnect`는 **리셋하지 않음**. 이전 실패 후 해제 성공 시 오류 문구가 **붉은 오류색으로 표시된 채 성공 문구**가 나온.

**조치**: 진입부에 `statusIsError = false` 1줄 (동일 패턴 준수)

### 1-1 `DeviceMonitor.run` 교착 (High)
`Sources/RelayConsole/Droid/DeviceMonitor.swift:982-996`
```swift
proc.standardError = Pipe()                            // 만들고 끝 — 읽지 않음
try proc.run()
let data = out.fileHandleForReading.readDataToEndOfFile()  // stderr 64KB 초과 시 영구 대기
proc.waitUntilExit()                                      // 타임아웃 없음
```
- adb가 stderr에 64KB를 넘기면 자식이 `write`에서 블로킹 → stdout EOF 미도달 → `readDataToEndOfFile()` 영구 대기
- 네트워크 ADB 반개방 TCP 시 무한 대기
- 정지 시 **DeviceMonitor actor 전체 정지** → `stop()`·`shutdown()` 처리 불가
- **대조 사례(같은 저장소의 안전 구현)**: `Sites/SiteChecker.swift:120-148` — deadline 루프 + `proc.terminate()`
- **부수 문제 [표시②] 위반**: 실패 시 stderr를 버리고 `ErrorCode.adbConnectFailed`만 던짐 → 실제 원인 미노출

**조치**
1. `stderr`를 `out`과 동일하게 소진 (또는 `FileHandle.nullDevice`로 폐기)
2. 데드라인 도입 — `proc.isRunning` 폴링 + `Task.sleep(50ms)`, 초과 시 `terminate()` → 필요 시 `interrupt()`
3. 실패 시 **stderr 원문을 에러에 첨부** (`ErrorCode` 또는 전용 `AdbRunError`)
4. 2단계에서 async 전환 계획이므로, 데드라인은 동기 `Date()` 기준으로 1단계에서 구현 (CancellationError 전파 지연 방지)

**테스트**: 데드라인 초과 시 `terminate()` 호출 / stderr 보존 / 정상 경로 무변경

### 1-2 폴링 루프 취소 후 추가 tick (High)
`DeviceMonitor.swift:94-100`
```swift
while !Task.isCancelled {
    try? await Task.sleep(nanoseconds: 5_000_000_000)  // 취소 시 CancellationError를 삼킴
    guard let self else { break }
    await self.tick()                                   // ← 취소 여부 미검증, 그대로 실행
}
```
`try?`가 `CancellationError`를 삼킨 뒤 `tick()`이 1회 더 실행됨 (slow 틱이면 기기당 최대 25회 adb spawn).

**조치**: `sleep` 직후 `guard !Task.isCancelled else { return }` 삽입

**테스트**: 취소 직후 tick 미실행

### 1-3 `ConnectionSessionStore.flush()` 영구 no-op (Med)
`Utils/ConnectionSessionStore.swift:11,56-58` — `dirty`에 `true`를 대입하는 코드가 **프로젝트 전체에 0건**. `flush()`는 항상 아무것도 하지 않음. `ConsoleStore.shutdown`이 호출하나 무효.

**조치**: `open`/`close`에서 `dirty = true` 설정 → 저장은 기존 호출부(`save()`)가 이미 있음. 중복 저장 방지는 `save()`가 `dirty = false`로 만드는 구조 활용

**테스트**: `open` 후 `flush()`가 실제 저장 경로를 태움

### 1-4 버전 하드코딩 3곳 낡음 (Low · 정합성)
정본 `Resources/Info.plist` = **1.16.0**

| 위치 | 값 | 판정 |
|---|---|---|
| `Views/MenuBarPopoverView.swift:145` | 1.16.0 | ✅ 일치 |
| `Views/SettingsView.swift:468` | **1.14.0** | ❌ |
| `RelayMcpCore/McpProtocol.swift:117` | **1.14.0** | ❌ |
| `App/AppDelegate.swift:8` | **1.15.0** | ❌ |

**조치**: 앱 표시 2곳은 `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` 단일 소스. `McpProtocol.serverVersion`은 `RelayMcpCore`(번들 밖)라 유지하되 `1.16.0`으로 정합 · 시작 로그도 단일 소스

**테스트**: 버전 표기 정합 (앱 표시 2곳이 `Info.plist`와 같은지)

### 1단계 완료 판정
- `swift test` 0 failed (기존 332 유지 + 신규)
- `./scripts/build-macos.sh debug` EXIT=0
- **사용자 육안**: adb 기기 1대 상태에서 대시보드 정상 표시, 실패 시 사유 노출 확인
- 문서: TODO T-반영 · `error_message_ko.json` 필요 시 갱신 · session 로그

---

## 2단계 — ADB 배치화 + 폴링 구조 (성능)

| 대상 | 근거 | 효과 |
|---|---|---|
| slow 틱 25회 → ~13회 | `/proc` 6회 342ms → 1회 125ms **2.7배 실측** | 기기당 slow 틱 −450ms |
| `cat` 12회 → 마커 1~2회 | 기기측 `for` 루프 + `@@경로` 마커 | 시간당 27,360 → ~14,000 spawn |
| `settings get` 3회 → 1회 | `settings list system\|global` | −2회 |
| `dumpsys` 3회 → 1회 | 셸 파이프로 묶기 | −2회 |
| 기기별 병렬 tick | 현재 완전 직렬 — head-of-line blocking | 지연 해소 |
| 실제 주기 왜곡 정직화 | `sleep(5s)+tick` → 실질 9~10s, 링 60칸 "5분"이 조용히 9분 | 타임스탬프 추가 |
| 키워드 `lowercased()` 사전 계산 | `AdbClient.swift:499` — 라인×키워드마다 재계산 | String 할당 감소 |

**주의**: 마커 프로토콜은 원격 `sh`에 의존 → `2단계` 검증에서 실기기로 4종 경로(공백·한글 포함) 재확인

---

## 3단계 — 신선도 · 정직성 (안정성 = 표시 규칙 ②)

- `DeviceMonitor` `try?` 39회 중 **38회가 실패를 기록조차 하지 않음** → adb 전부 실패해도 화면은 정상값 + `lastError` 없음
- `DeviceInventory.swift:270` — 모든 adb 호출 실패해도 `lastSampleAt`을 현재 시각으로 갱신 → "방금 측정" 위장
- 조치: `staleFields: Set<String>` + 연속 실패 카운터 전파, 값 재사용 시 `lastSampleAt` 갱신 금지
- logcat: 4회 전수 스캔(`logcatHitBreakdown`·`countLogcatHits`×2·`lastLogcatTimestamp`) → 1회 병합, 출력 크기 상한
- 기기 해제 시 `metricsHistory`·`lastNetPushAt`·`lastDailyIngestAt`·`dropboxScannedAt` 정리 (네트워크 ADB는 IP가 serial → DHCP 변경 시 키 무한 증가)

---

## 4단계 — 메인 스레드 정지 (성능)

| 스토어 | 현재 | 조치 |
|---|---|---|
| `EventStore` | 이벤트 1건마다 **500건 전량 인코딩을 MainActor에서**, 디바운스 0 | 디바운스 + 백그라운드 인코딩 |
| `SitesJobsStore` | 사이트 8 × 이력 300 = **최대 14,400 레코드 5초마다 메인** | 디바운스 + 경량 projection |
| `WidgetSnapshotStore` | **유일하게 동기 atomic write가 메인** (6개 중) | 백그라운드 encode+write, `reloadTimelines`만 메인 |
| `DeviceDailyStore` | 전체 맵 재인코딩이 메인 | `nonisolated` 큐 |

---

## 5단계 — SwiftUI 렌더 (성능)

- `ConsoleStore` 단일 평면(관측 가능 57개 = `@Published` 15 + `@AppStorage` 42) → 스토어 분리 + `@Environment(\.store)`
- `InsightsView`: `insight` **13회** · `report` **9회**(매번 `patterns` 전체) · `monthGrid` **셀마다 500건 필터**(≈15,500회/평가) → body 1회당 **약 19,500회 이벤트 순회**
- `AlertsView`: body당 필터 4회 × 500건
- `FloatingGraphController`: **모든 `leftMouseUp`에서 무조건 `fitAll()`** (최대 6창 × 4회 레이아웃 + `setFrame(display:true)`) + `store.objectWillChange`가 5초마다 재호출 → 드래그 실제 발생 시로 게이트, 구독을 `objectWillChange` → `store.$metricsHistory`로 좁히기
- `DateFormatter` body 내 신규 3곳 → `static let` hoisting (`FileBrowserView:16-20` 선례 있음)
- `String(format:)` 26건
- `LogViewerView`: `id: \.offset` + 매 `removeFirst` → **200줄 id 전부 이동 = 전 행 재구성** → 단조 증가 `seq` 도입
- `DeviceDailyStore`·`ConnectionSessionStore`가 `ObservableObject` 아님 → 값 갱신이 UI에 반영되지 않는 **정확성** 문제 (성능 리팩토리와 함께 처리해야 캐시 정합성 성립)

---

## 조사 결과 — 리팩토리 불필요로 판정 (실행 안 함)
- `ScrollView`+`VStack` 오남용 **0건** (전부 `LazyVStack`/`LazyVGrid`)
- retain cycle **0건** (`FloatingGraphController` 전 클로저 `[weak self]`)
- `AnyView` 1곳(`DroidCards.swift:355`) — 카드 1장분으로 제한적
- 강제 언랩 `fatalError`/`try!` **0건** (`Sources/` 전체)
- `deinit` 부재 — 전부 싱글턴이라 무해
- `@EnvironmentObject` 사용처 0건
- `Dictionary` 순회 중 변형(`syncPanels`) — COW로 **크래시 안 함**. 에이전트 "crash 가능" 지적은 과장 → 반영 안 함

---

## 전 단계 공통 규칙
1. `swift test` → `./scripts/build-macos.sh debug` **2개 모두 실행** 전 "완료" 표현 금지 ([HARD] 최상단 규칙)
2. 1단계 = 1 PR · main 직접 push 금지
3. 단계 완료 시: TODO 갱신 · `error_message_ko.json` · `.agent/session-2026-09-26-macos.md` 기록
4. 표시가 바뀌는 단계는 **사용자 육안 확인 필수**
5. 성능 개선은 **단계 전/후 동일 조건 실측**으로만 보고 (추측 금지)
