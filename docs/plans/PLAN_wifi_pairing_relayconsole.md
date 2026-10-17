# PLAN_wifi_pairing_relayconsole — Android 11+ 무선 디버깅 페어링 + 재부팅 내구성 (macOS)

> 착수: 2026-10-17 · 규모 M · 상태: **1·2단계 구현 완료 — 실기기 검증 대기** (3단계 QR은 판정 전)
> 선행: `PLAN_wifi_onboarding_relayconsole`(수동 endpoint) · `PLAN_wifi_auto_tcpip_relayconsole`(USB→tcpip) · `PLAN_wifi_reconnect_relayconsole`(TCP 유실 재연결)
> 근거: `docs/research/RESEARCH_competitive_v2.md` §4.1 G1 · §5.1 P1-1 · 출처 [49][50] · TODO `T-2026-10-17-4`

---

## 1. 문제 — 기능 부족이 아니라 **신뢰성 결함**

현재 Wi-Fi 연결은 **USB를 꽂아 `adb tcpip 5555`를 걸어야** 열린다. 그 경로의 성질:

- `adb tcpip`은 adbd를 **재시작**한다(그 순간 USB 연결이 사라진다 — 이미 코드에 주석으로 기록됨).
- 그 TCP 서버는 **재부팅 시 사라진다** → 폰이 재부팅되면 사용자가 **USB를 다시 꽂아야** 한다.
- 즉 "켜져 있으면 감시된다"는 관제 전제가 **사용자 개입 없이는 성립하지 않는다**.

### 실측 (2026-10-17 · 테스트 기기 2대)

| 항목 | 값 | 의미 |
|---|---|---|
| adb | `1.0.41 / 37.0.1-15733141` | `adb pair` 지원 · mDNS 데몬 내장(`adb discovery 0.0.0`) |
| 현재 연결 | `192.168.86.49:5555`(S22 · Android 16/sdk36) · `192.168.86.30:5555`(Router · Android 12/sdk31) | 둘 다 **레거시 tcpip** |
| `settings get global adb_wifi_enabled` | **0** | 폰의 **무선 디버깅이 꺼져 있다** |
| `adb mdns services` | **빈 목록** | 무선 디버깅이 꺼져 있어 광고되는 서비스가 없다 |
| `service.adb.tcp.port` | `5555` | 레거시 서버가 5555에 열려 있다 |

AOSP 설계 문서([50])가 밝히는 Android 11+ 경로는 다르다.

- **Pairing Server는 폰에서** 돈다. 신뢰는 **공유 비밀**로 부트스트랩되고, 그 비밀은 **6자리 코드**(코드 페어링) 또는 **QR의 비밀 문자열**(QR 페어링)로 전달된다.
- 무선 디버깅을 켜면 adbd가 **TLS 서버**(랜덤 포트)와 **mDNS 광고 3종**을 띄운다:
  `_adb._tcp`(레거시 tcpip) · `_adb-tls-pairing._tcp`(페어링 창이 열린 동안) · `_adb-tls-connect._tcp`(무선 디버깅이 켜져 있는 동안).
- **한 번 페어링하면** 호스트는 mDNS로 `_adb-tls-connect`를 발견해 **자동으로 다시 붙는다**(GUID 기억). **포트가 매번 바뀌어도** IP:port를 다시 묻지 않는다.

즉 T-4의 본질은 두 가지다. ① **USB 없이 첫 연결**(페어링), ② **끊겨도 스스로 돌아오는 연결**(mDNS 재발견).

### 경쟁
AndroLaunch(88★ · macOS 메뉴바)가 **QR 무선 페어링**을 이미 제공한다([50] 부록 B). 우리에겐 "격차"가 아니라 **따라잡기**이며, 관제 앱에서 이건 **선택이 아니라 필수**다([50] §5.1 P1-1).

---

## 2. 범위 — 3단계 (1·2단계 구현, 3단계는 판정 후)

### 1단계. 페어링 온보딩 (6자리 코드) — USB 불필요
폰: `설정 > 시스템 > 개발자 옵션 > 무선 디버깅 > 페어링 코드로 기기 페어링` → 폰이 **6자리 코드 + IPv4:포트**를 보여준다.
앱: ① 코드·endpoint 입력(또는 mDNS가 발견한 페어링 서비스를 자동 채움) → ② `adb pair <ip:pairPort> <code>` → ③ `adb connect <ip:connectPort>`.

`connect` 포트는 페어링 포트와 **다르다**(둘 다 랜덤). 그래서 2단계의 mDNS가 곧바로 필요하다.

### 2단계. 재부팅·포트 변경 내구성 (mDNS 자동 재발견)
`adb mdns services`로 `_adb-tls-connect._tcp` 인스턴스(`adb-<serial>-<random>`)의 **현재 IP:port**를 얻어 재연결한다.
- 재부팅·Wi-Fi 변경·포트 재할당에서 **사용자 개입 없이** 복구되는지가 판정 기준이다(§4.2).
- 기존 재연결 루프(`PLAN_wifi_reconnect`)에 **후보 소스 하나를 더하는** 형태로 붙인다(로직 신설 금지).

### 3단계(판정 후). QR 페어링
AOSP 문서 기준으로 QR은 **호스트가 만들어 폰이 스캔**한다. 페이로드는 WPA3 패스프레이즈 형식을 빌린
`WIFI:T:ADB;S:<instance-name>;P:<password>;;` 이고, 폰의 카메라 핸들러가 `T:ADB`를 보고 **요청된 인스턴스 이름으로 페어링 서버를 띄운다**(`studio-<random10>`).
QR도 최종적으로는 `adb pair` 한 번이다 — 다른 건 **6자리를 눈으로 읽는 대신 QR로 전달**한다는 점뿐이다.

- 구현 비용: QR 생성은 `CoreImage.CIQRCodeGenerator`로 가볍다.
- 남은 위험 두 가지: ① **호스트가 만든 비밀 문자열을 `adb pair`가 그대로 받아들이는지**(문서 예시는 12자 비밀을 그대로 쓴다 — 가능성 높음, 실측 필요), ② 요청한 인스턴스 이름의 페어링 서비스를 **mDNS에서 골라내는 것**(같은 네트워크에 폰 여러 대).
- **판정 전에는 넣지 않는다.** 1·2단계가 동작하면 3단계는 순수 편의 기능이다.

### 유지(폴백 — 삭제 금지)
- Android 10 이하 · 무선 디버깅을 못 쓰는 기기 → **기존 USB → `adb tcpip` 경로 유지**.
- mDNS가 막힌 네트워크(AP 격리) → **수동 endpoint 입력 유지**(`wifi.manual.*`, 이미 있음).

---

## 3. 설계

### 3.1 순수 로직 — `WifiAdbLogic` (전부 테스트 고정)

| 함수 | 입력 → 출력 | 고정하는 것 |
|---|---|---|
| `parseMdnsServices(_:)` | `adb mdns services` 출력 → `[AdbMdnsService]` | 헤더 줄 무시 · **가변 공백/탭** 열 구분 · `ipv4:port` 분해 |
| `pairingEndpoints(_:)` | 서비스 배열 → 페어링 후보 | `_adb-tls-pairing._tcp` 필터 |
| `connectEndpoints(_:)` | 서비스 배열 → 연결 후보 | `_adb-tls-connect._tcp` 필터 (재부팅 내구성의 입력) |
| `endpointHosts(_:)` | 서비스 배열 → 호스트 IP 집합 | 이미 연결된 IP는 후보에서 제외 |
| `isValidPairingCode(_:)` | 문자열 → Bool | 6자리 숫자만(공백·하이픈은 허용) |
| `pairArgs(endpoint:code:)` | → `["pair", "ip:port", "code"]` | 인자 순서 고정 |
| `isPairSuccess(output:)` | `adb pair` 출력 → Bool | adb는 실패해도 exit 0일 때가 있다 — **출력 판정**(기존 `isConnectSuccess`와 같은 원칙) |
| `pairFailureHint(output:)` | 출력 → 사용자 문구 키 | "wrong password"·"failed to connect"·시간 초과 구분 |

### 3.2 컨트롤러 — `WifiAdbController`
- `func refreshMdnsServices() async` — `adb mdns services` 실행 → `@Published mdnsServices` (UI 목록·자동 채움).
- `func pair(endpoint: String, code: String) async` — `adb pair` → 성공하면 **곧바로 `connect`까지**(mDNS 연결 후보 우선, 없으면 사용자가 넣은 호스트의 기본 포트).
- 실패는 `lastError`에 **원문 출력**을 남긴다 — 사용자가 폰 화면과 대조할 수 있게.
- `ProcessRunner`(기존 유틸)로 실행하고 타임아웃을 건다 — `adb pair`는 **코드 입력 대기**로 멈출 수 있다(실측: 인자 없이 실행하면 "Enter pairing code:" 프롬프트).

### 3.3 UI — `WifiOnboardingSheet`
- 새 섹션 **"Android 11+ 무선 디버깅"**: 폰 절차 안내(3줄) + 코드 입력칸 + [페어링] + mDNS 탐색 결과 목록(탭하면 endpoint 채움).
- 기존 "USB → Wi-Fi" 섹션은 **Android 10 이하 / 무선 디버깅 불가** 안내와 함께 유지.
- 새 배너·새 상태 머신을 만들지 않고 `statusMessage`·`busy`를 재사용한다.

### 3.4 키 · 테스트
- L10n `wifi.pair.*` — ko/en **같은 키명 동시 추가**(키 수 1:1 유지). 기존 `wifi.manual.pairHint`(현재 안내 문구)를 대체·계승한다.
- 단위 테스트: 3.1의 순수 함수 전부 + **실측 mDNS 출력을 픽스처로** 고정.

---

## 4. 검증

### 4.1 단위
`swift test` — 파서·필터·코드 검증·성공 판정·힌트 매핑.

### 4.2 실기기 (사용자 손 필요 — 폰 화면 조작)
1. 폰: 무선 디버깅 ON → "페어링 코드로 기기 페어링" 화면을 연다.
2. 앱: mDNS가 **페어링 서비스를 자동으로 채우는지** 확인(못 채우면 수동 입력이 정상 동작하는지).
3. 페어링 → `adb devices`에 `adb-<serial>-<random>._adb-tls-connect._tcp` 형태로 뜨는지.
4. **재부팅 내구성 [핵심]**: 폰 재부팅 → 앱이 **USB 없이** 다시 붙는가.
   - 무선 디버깅 토글이 재부팅 후에도 켜져 있는지는 **기기별로 다를 수 있음 — 미검증**. 이 실측이 "무엇을 약속할 수 있는지"를 정한다.

### 4.3 기록
- `docs/MANUAL_VERIFY.md`에 "무선 디버깅 페어링(USB 없이)" · "재부팅 후 자동 재연결" 2항목 추가.
- `docs/TODO.md` T-2026-10-17-4 완료 조건: 4.2의 3·4번 실측 통과.

---

## 5. 리스크 · 한계 (거짓 약속 금지)

| 리스크 | 대응 |
|---|---|
| 무선 디버깅 토글이 재부팅 시 **꺼지는 기기** | 실측 후 UI 문구에 한계를 명시 — "USB 1회"가 아니라 **토글 1번**임을 정확히 쓴다 |
| AP 격리·mDNS 차단 | 수동 endpoint 입력 유지(이미 있음) |
| 페어링·connect 포트가 매번 다름 | mDNS 재발견(2단계). 실패 시 폰 화면 숫자를 그대로 받는 입력 유지 |
| 같은 네트워크에 폰 여러 대 | instance 이름(`adb-<serial>`)으로 구분 — 시리얼을 알면 `DeviceSnapshot`과 대조 가능 |
| adb 출력이 버전마다 다름 | 파서·판정을 순수 함수로 두고 **실측 출력을 픽스처로 고정** |
| `adb pair`가 코드 대기로 멈춤 | 항상 인자로 코드를 넘기고 타임아웃을 건다 |

### 하지 않을 것
- 폰에 앱 설치(**정책 유지**) · 폰이 우리 QR을 띄우게 하는 역방향(불가 — QR은 호스트가 만든다) · Windows/Linux 포팅.

---

## 6. 출처
- [49] Android 개발자 문서 — adb(Android 11+ 무선 디버깅) — https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11
- [50] AOSP — `packages/modules/adb/docs/dev/adb_wifi.md` (Pairing Server · mDNS 3종 · QR `WIFI:T:ADB;S:...;P:...;;`) — https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md
