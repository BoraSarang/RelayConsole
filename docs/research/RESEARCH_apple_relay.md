# RESEARCH_apple_relay.md — Apple 플랫폼 확장 리서치 (통합)
> 생성일: 2026-09-23 | 상태: **조사 완료 — 구현 계획 미확정 (PLAN 미작성)**
> 목적: Relay Console의 Apple 방향 2종 조사를 하나로 통합 보관
> 원본 A: `/Users/lee/Downloads/Apple-Relay-Planning-Report.md` (Apple 기기를 **감시 대상**으로 추가)
> 원본 B: 세션 내 iOS/iPad 조사 (iPhone/iPad를 **호스트**로 전환)
> 재조사 방지용 — 최종 PLAN 확정 전 참고 문서

---

## 0. 두 방향을 먼저 구분 (핵심)

| | **방향 A — Apple 기기 감시** | **방향 B — iOS 호스트 포팅** |
|--|------------------------------|------------------------------|
| 한 줄 | 맥 Relay에서 iPhone/iPad **상태 카드** 표시 | iPhone/iPad에 Relay를 **이식**해 Android를 관제 |
| 관계 | Android 카드와 **동일 패럴런티** 추구 | Android는 그대로, **기기만 바뀜** |
| 연결 | USB Trust / Developer Mode 터널 | **LAN 무선 ADB만** (USB 불가) |
| 기존 자산 | 배터리·스토리지·디바이스 카드 재사용 | SwiftUI UI·디자인 토큰·L10n 재사용 |
| 원본 | Apple-Relay-Planning-Report.md | 세션 조사 (adbtv / iadb-ios / App Store) |
| 난이도 | 호스트 도구 체인 (libimobiledevice 등) | ADB 프로토콜 네이티브 클라이언트 |
| 우선순위 제안 | 🟡 방향 A Phase 1 (1–2주, 빨리 보임) | 🟡 별도 앱/브랜치, 큰 공사 |

**한 줄 결론**: A는 "Relay가 Apple 기기도 본다", B는 "Relay가 iPhone에서도 돌아온다". 서로 독립이며, 같은 메뉴바 UX·카드 디자인을 공유한다.

---

## 1. 방향 A — Apple 기기를 감시 대상으로 (원본 A 요약·검증)

### 1-1. 전제: Android 패럴런티는 iOS에서 1:1 불가

안드로이드 카드(S22 기준) 벤치마크:
- 코어별 CPU 온도·진동수, Adreno 730 GPU, 39센서 샘플링 레이트
- 배터리 84%·36°C·health 91%·4.15V·cycle 807
- 써멀 존 PA1THM/AP/BAT, 네트워크 RSRP, 스토리지 live R/W

iOS는 샌드박스로 `/proc`, `/sys`, `dumpsys`를 **어떤 App Store 앱에도 노출하지 않음**.
- 코어별 온도·진동수: **불가**
- GPU 모델 문자열: **불가** (FPS/활용률만 개발 모드)
- 센서 목록+주기: **호스트 측 불가** (동반 앱 필요)
- 열 상태: `ProcessInfo.thermalState` 4단계 enum만 (nominal/fair/serious/critical)

### 1-2. 호스트 경로 2단계

#### Tier 1 — Trust-only (`libimobiledevice`)
- "이 컴퓨터를 신뢰"만으로 동작. 개발자 모드·DDI·터널 **불필요**
- 바이너리: `idevice_id`, `ideviceinfo` (배터리 capacity·charging), `idevicediagnostics` (ioreg·배터리 health·cycle·voltage)
- 검증 사례: [iPhoneStatus](https://github.com/vincentlauriat/iPhoneStatus) — Process로 위 도구 호출, 메뉴바에 배터리 health/cycle/스토리지/디바이스 정보
- Wi-Fi만으로는 배터리 lockdown 쿼리 실패 보고 있음 (USB Trust 기준)
- Apple Watch: libimobiledevice **미지원**

#### Tier 2 — Developer Mode + Tunnel (`pymobiledevice3` / `libinstruments`)
- 전제: iOS 16+ 개발자 모드 ON, DDI 마운트, **iOS 17+는 `tunneld` 상주** 필요
- 해금:
  - `developer dvt sysmon system` → CPU_TotalLoad/UserLoad/System, vm stats, netBytesIn/Out, diskBytes*
  - `developer dvt sysmon process` → 프로세스별 CPU/mem top
  - `developer dvt graphics` → FPS·GPU 활용률
  - `diagnostics battery` → health·cycle·voltage
- 주의: iOS 17+ tunneld는 xcuitest와 함께일 때 `IncompleteReadError` 등 불안정 이슈 존재
- 그래도 **코어별 온도·센서 주기·GPU 모델명은 영원히 없음**

#### 비공개 API 경로 (Tier 3 — 동반 앱)
- 온기기 앱: `IOPMPowerSource` 배터리 온도, `host_statistics`, `proc_pidinfo`
- **App Store 금지** (Guideline 2.5.1). AltStore 등 개인 시드 sideload 전용
- usbmux forward로 맥 Relay와 병합 가능

### 1-3. 피처 패럴런티 매트릭스 (카드별)

| 카드 | Android 현재 | Apple Tier 1 | Apple Tier 2 |
|------|--------------|--------------|--------------|
| Device Info | 모델·SDK·ADB IP | ✅ 100% (lockdown info) | + DDI/cryptex |
| Battery | %·°C·health·V·cycle | ✅ %·health·cycle·V (온도는 헬스 프록시) | + live monitor |
| CPU | 18% + 8코어 + loadavg | ❌ | ⚠️ 총부하만, 코어 바 없음 |
| GPU | Adreno 730 + % | ❌ | ⚠️ FPS·%만 |
| Memory | 4.9/7GB + top | ⚠️ 총량만 | ⚠️ + top 프로세스 |
| Sensors | 8/39 + rates | ❌ | ❌ (동반 앱) |
| Network | up/down + RSRP | ❌ | ⚠️ bytes 델타만 |
| Thermal | 존별 °C | ⚠️ enum 배너만 | ⚠️ enum + 히스토리 |
| Storage | 21/223GB + R/W MB/s | ⚠️ total/used | ⚠️ + live I/O |

### 1-4. 원본 로드맵 (Phase 1→4)

1. **Phase 1 Trust-only (1–2주)** — `brew install libimobiledevice` 탐지, Swift Process 래퍼, 배터리/스토리지/디바이스/써멀 enum 카드, 메뉴바 흰색 아이콘
2. **Phase 2 Developer Mode opt-in (2–4주)** — pymobiledevice3 번들 또는 Swift libinstruments interop, sysmon 2–3초 루프, CPU/Mem/Net 카드
3. **Phase 3 동반 앱 (1–2개월, private)** — 센서·배터리 온도, usbmux forward 병합
4. **Phase 4 기타** — iPad 동일, Watch/AirPods/Apple TV **범위 밖**

### 1-5. 방향 A 메뉴바 UX 시사 (원본 §6)
- 다중 기기: 플랫폼 중립 아이콘 + 카운트 배지 (`2`), 긴 텍스트는 노치 잘림 위험
- 단일 기기: 플랫폼별 흰 아이콘 + 초록 점 (`android_online_green_white`, `apple_online_green_white`)
- 베이스는 Template, 초록 점은 non-template 오버레이 (Custom NSStatusItem view)

> 참고: 현재 저장소 아이콘은 `MenuBar-Off` / `MenuBar-Online` 2종만 존재. Apple 전용 아이콘은 미생성.

---

## 2. 방향 B — iPhone/iPad를 Relay 호스트로 (세션 조사)

### 2-1. 현재 코드베이스 기준 (2026-09-23 확인)

| 항목 | 현재 |
|------|------|
| Package.swift | `.macOS(.v26)` **한정** |
| ADB 호출 | `DeviceMonitor.swift:540` `Process()` + `/usr/bin/adb` |
| UI | SwiftUI 전용 — 카드·팝오버·L10n 72키 공유 가능 |
| macOS 전용 | `MenuBarExtra`, `WindowFocus`, `AppDelegate`, `LSUIElement` |

### 2-2. 판정표

| 플랫폼 | 판정 | 근거 |
|--------|------|------|
| **iPhone/iPad** | **가능 (LAN 무선 ADB만)** | 아래 2-3 참조. USB ADB 불가. |
| **macOS** | 완료 (v0.4) | 메뉴바 UX·z-order 해소 진행 중 |
| **visionOS** | 부분 가능 | SwiftUI 공유, 동일 네트워크 ADB. App Store 다중 플랫폼 포함 가능. |
| **watchOS** | 비실용 | 화면·연결 모델 부적합 |
| **tvOS** | 이론상 가능 | adbtv 계열과 코드 공유 여지. 목표 불명확. |

### 2-3. 기술 제약

| 항목 | iPhone/iPad | macOS |
|------|-------------|-------|
| USB ADB 직접 | **불가** — iOS는 DriverKit·범용 USB host 미지원. MFi·카메라 어댑터로 ADB 불가. iPadOS만 DriverKit 여지(ADB 클래스 아님) | 가능 (현재) |
| 무선 ADB (Wireless Debugging) | **가능** — Android 11+ 페어링(6자리/QR), 수동 IP:port, mDNS | 가능 |
| `Process()`로 adb CLI | **불가** — iOS에 프로세스 스폰 API 없음 | 가능 |
| 순수 Swift ADB 클라이언트 | **필수** — CNXN/AUTH, Shell v2, Sync, TLS 1.3 + SPAKE2 페어링 내장 | 대안 |

**아키텍처 변화 (B 채택 시):**
```
현재:  SwiftUI → ConsoleStore → DeviceMonitor.Process("/usr/bin/adb")
목표:  SwiftUI → ConsoleStore → AdbTransport
                                 ├─ macOS: 기존 adb CLI (Process)
                                 └─ iOS:   네이티브 ADB 프로토콜 클라이언트
```

### 2-4. 검증된 참고 구현

| 프로젝트 | 특징 |
|----------|------|
| [maxduke/adbtv](https://github.com/maxduke/adbtv) | SwiftUI iPhone/iPad 범용, `ADBClientCore` Swift 패키지: 네이티브 패킷·stream·sync, Wireless Debuging 페어링 (TLS 1.3/SPAKE2), Bonjour mDNS, QR, iCloud Keychain ADB 신원, Android TV 원격. iOS 17+. Self-signed는 Bonjour/QR 숨김 → 수동 IP fallback. |
| [h33h/iadb-ios](https://github.com/h33h/iadb-ios) | iOS 네이티브 ADB: discovery·페어링, shell v2, logcat, 파일, 스크린샷. UI 재설계 중(비즈니스 레이어만 유지). |
| App Store [Wireless Debug / ADBolt](https://apps.apple.com/us/app/wireless-debug/id6761755052) | **상용 검증**: iOS 17+, QR 페어링·mDNS·셸·로그·패키지·파일·APK 설치. 같은 Wi-Fi 필수. |
| App Store [DevMate ADB Connect](https://apps.apple.com/us/app/adb-connect-debugger-for-atv/id6757657259) | iOS 13+: 페어링·IP·파일·패키지·logcat·원격 제어. |
| [adbx](https://github.com/imvaskii/adbx) | 데스크톱 TUI: `_adb-tls-pairing._tcp` / `_adb-tls-connect._tcp` mDNS 자동화 패턴. |
| [DroidMux](https://github.com/poapoauu/DroidMux) | Rust: SPAKE2·TLS1.3·STLS 페어링 스택 참조 (언어는 다름). |

### 2-5. 분배·권한 (B)

- **Local Network** usage description 필수 (mDNS·TCP)
- Bonjour 전체 discovery: `_adb-tls-pairing._tcp`, `_adb-tls-connect._tcp` — `NSBonjourServices` 선언
- restricted **Multicast Networking** entitlement: 유료 개발자 계정+프로비전 없으면 self-signed에서 무효 → Discovery/QR 숨기고 **Pair with Code / Add Manually**만 노출 (adbtv 패턴)
- App Store 출시 가능 (ADBolt·DevMate 증명) 또는 AltStore sideload
- Camera permission (QR 페어링 시)

### 2-6. 권고 (B)

1. 방향 B는 **별도 타겟/브랜치**에서 `Package.swift` 플랫폼 분기 + `#if os(macOS)` 분리부터
2. 트랜스포트 계층을 추상화 (`AdbCLI` vs `AdbNative`) 후 카드 UI는 공유
3. USB 관제 문구 금지 — 포지셔닝은 **LAN 무선 관제**
4. 라이선스 확인 후 adbtv `ADBClientCore` / iadb 프로토콜 레이어 참조

---

## 3. 통합 우선순위 제안 (미결 — 사용자 확정 필요)

| 순위 | 안 | 이유 |
|------|----|------|
| 1 | 메뉴바 UX收尾 (WindowFocus 육안 + push/PR) | 이미 구현 완료분 정리 |
| 2 | **방향 A Phase 1** (Trust-only Apple 배터리 카드) | 상대적 작은 공사, 기존 카드 재사용, 맥 안에서 완결 |
| 3 | 방향 A Phase 2 (Developer Mode) | power user opt-in |
| 4 | 방향 B (iOS 호스트) | 큰 공사 — 새 ADB 스택, 별도 앱 아이덴티티 검토 |

**미결 질문**
- [ ] 방향 A와 B 중 무엇을 v0.5로 잡을까? (또는 둘 다 장기 백로그?)
- [ ] A의 의존 배포: brew 탐지 vs 번들링?
- [ ] B를 같은 번들ID로 App Store multiplatform인가, 별도 앱인가?
- [ ] Apple 전용 메뉴바 아이콘 생성 필요 시점?

---

## 4. 원본 위치

| 조각 | 경로 |
|------|------|
| Apple 감시 리포트 (영문 원문) | `/Users/lee/Downloads/Apple-Relay-Planning-Report.md` |
| iOS 호스트 조사 | 본 문서 §2 (세션 웹 검색 결과) |
| Android Device Care 참고 | `docs/research/RESEARCH_droid_devicecare.md` |

## 5. Sources (방향 A 원본 인용 유지)

[1] https://github.com/vincentlauriat/iPhoneStatus
[2] https://github.com/doronz88/pymobiledevice3/blob/HEAD/.codex/skills/pymobiledevice3-device-operator/references/transport-and-safety.md
[3] https://github.com/alleneubank/agent-profile/blob/HEAD/plugins/engineering-practices/skills/platform-tooling/references/physical-ios/diagnostics-perf.md
[4] https://github.com/doronz88/pymobiledevice3/pull/1359
[5] https://developer.apple.com/documentation/foundation/processinfo/thermalstate
[6] https://github.com/libimobiledevice/libimobiledevice/blob/master/README.md
[7] https://github.com/amrit-nigam/ios-battery-wifi/blob/HEAD/NOTES.md
[8] https://github.com/gianmarco0001/doctor-battery
[11] https://github.com/doronz88/pymobiledevice3/issues/1682
[12] https://github.com/hazmi-e205/libinstruments/blob/HEAD/README.md
[14] https://github.com/gregsramblings/ios-charging-monitor

방향 B 추가:
- https://github.com/maxduke/adbtv
- https://github.com/h33h/iadb-ios
- https://apps.apple.com/us/app/wireless-debug/id6761755052
- https://github.com/imvaskii/adbx
- https://github.com/poapoauu/DroidMux
- https://developer.android.com/tools/adb
