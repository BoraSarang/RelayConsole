# PLAN_wifi_onboarding_relayconsole.md — A2 Wi-Fi ADB 온보딩

> 생성일: 2026-09-24 | 상태: **구현 완료** (사용자 일괄 검토 대기) · bd: `RelayConsole-z9i`
> 모체: `RESEARCH_competitive_v1` §8 **P1-3** · `PLAN_v0.3` · `PLAN_v0.7`
> 앱: **Relay Console** | 목표 버전: **1.6.0** | 최소 OS: **macOS 26.0**

---

## 1. 목표

USB로 연결된 Android 기기를 **메뉴바 콘솔에서 바로 Wi-Fi ADB로 전환·연결**한다.
경쟁(ADB Studio·AndroLaunch) 대비 — 감시 패널과 같은 화면에서 원클릭 온보딩.

| 항목 | 내용 |
|------|------|
| USB→Wi-Fi | 선택 기기에 `adb tcpip 5555` → wlan IP 읽기 → `adb connect IP:5555` |
| 수동 연결 | `IP:PORT` 입력 → `adb connect` (검증 포함) |
| 끊기 | 네트워크 serial → `adb disconnect` |
| 표시 | 대시보드 헤더 Wi-Fi 버튼 · 빈 상태 안내 강화 |

### OUT
- Android 11+ 무선 디버깅 **pairing 코드 플로우** (`adb pair`) — 별 이슈
- QR 스캔 페어링 · mDNS 자동 discovery UI
- 기기 쪽 Wi-Fi 켜기/설정 이동 (권한·프래그먼트 한계)

---

## 2. 범위 (IN / OUT)

| IN | OUT |
|----|-----|
| `WifiAdbLogic` 순수 (IP 파싱·엔드포인트 검증·tcpip/connect 인자) | `adb pair` pairing 코드 |
| `WifiAdbController` IO (tcpip/connect/disconnect/IP 조회) | QR·mDNS |
| 헤더 Wi-Fi 버튼 (USB 기기에서) · 빈 상태 안내 | Settings 전용 탭 |
| 시트: 원클릭 전환 + 수동 connect + disconnect | |

---

## 3. 설정키

| 키 | 타입 | 기본 | 설명 |
|----|------|------|------|
| `relay.wifi.defaultPort` | String | `5555` | tcpip/connect 기본 포트 |

(미설정 시 코드 기본 5555 — AppStorage는 UI 노출 최소)

---

## 4. 모델·로직

```swift
// WifiAdbLogic (순수 · 테스트)
parseWlanIp(from route/ifconfig text) -> String?
validateEndpoint("10.0.0.5:5555") -> String? // nil=OK, 아니면 i18n key
tcpipArgs(serial:port:) -> [String]
connectArgs(endpoint:) -> [String]
defaultEndpoint(ip:port:) -> String
```

```
WifiAdbController (ObservableObject)
  enableWifi(serial:)  // tcpip → IP → connect → 결과 메시지
  connect(endpoint:)
  disconnect(serial:)
  fetchDeviceIp(serial:) -> String?
```

---

## 5. UI

- **DroidDashboard 헤더**: USB serial일 때 `Wi-Fi` 칩 버튼 (scrcpy 옆)
- **빈 상태**: "네트워크 기기" 힌트 아래 **Wi-Fi로 연결** 버튼 → 시트
- **시트** `WifiOnboardingSheet`:
  1. USB 기기 선택 (있으면) → **USB→Wi-Fi 전환** 원클릭
  2. 수동: TextField `IP:PORT` + 연결
  3. 현재 네트워크 기기 → 끊기
  4. 상태 라인 (성공/오류 · i18n)

---

## 6. 파일 변경

| 파일 | 변경 |
|------|------|
| `Droid/WifiAdb.swift` | Logic + Controller (신규) |
| `Views/WifiOnboarding.swift` | HeaderButton + Sheet (신규) |
| `Views/DroidDashboardView.swift` | 헤더·빈 상태 연결 |
| `Views/MenuBarPopoverView.swift` | (선택) 빈 상태 동일 버튼 |
| i18n 3처 | `wifi.*` 키 |
| `Tests/.../WifiAdbTests.swift` | Logic 신규 |
| 버전 7처 | **1.6.0** |

---

## 7. DoD

- [x] `parseWlanIp` · `validateEndpoint` 테스트
- [x] USB 기기 → 원클릭 tcpip+connect 경로 (IO는 컨트롤러)
- [x] 수동 `IP:PORT` 검증 거부 + 연결
- [x] i18n **461** 3처 parity · 금지 grep 0 · `swift test` · `build-macos.sh debug` **1.6.0**
- [ ] 사용자 일괄 검토

---

## 8. 버전 1.6.0 동기화처

Info.plist · build-macos.sh(3) · AppDelegate · SettingsView · MenuBarPopoverView · AGENTS.local.md · README.md
