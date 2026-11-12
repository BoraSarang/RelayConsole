# PLAN_postboot_hook_relayconsole — 부팅 후 첫 연결 훅 (adb root + 웨이크락 + 5555 영속)

> 착수: 2026-11-12 · 규모 M · 상태: **구현·실기기 검증 완료 (2026-11-12) · PR #144 squash merge `c50f4ef`**
> 선행: `PLAN_wifi_auto_tcpip_relayconsole`(USB→tcpip) · `PLAN_wifi_reconnect_relayconsole`(TCP 유실 재연결) · `PLAN_wifi_pairing_relayconsole`(mDNS 재부팅 내구성)
> TODO: `T-2026-11-12-1`

---

## 1. 문제 — 재부팅 뒤 USB 없이 :5555를 유지하려면

관제 대상 S7(`herolte` · LineageOS 21 · `userdebug`)은 재부팅 뒤에도 `:5555`로 붙어야 한다.
`:5555`가 재부팅 뒤에도 열리는 근거는 **폰 쪽 `persist.adb.tcp.port=5555`** 이며, 이 값은 앱이 아니라 폰이 제공한다.
`adb root`는 **5555를 열지 않는다** — adbd를 root로 재시작할 뿐이고, 그 순간 전송이 한 번 끊긴다.

따라서 앱이 자동화할 일은 다음 네 가지다.

1. 부팅 후 **첫 연결 성공**을 부팅 단위로 1회 판정한다 (앱 재시작마다 반복하지 않는다).
2. `adb root`로 adbd를 승격하고, **끊긴 전송을 앱이 먼저 다시 붙인다**.
3. root 권한으로 `/sys/power/wake_lock`에 이름을 1회 기록해, 기기가 잠들면서 Wi-Fi/ADB가 끊기는 것을 막는다.
4. 부팅 직후 Android가 Wi-Fi 국가 코드를 갱신하며 연결을 1회 끊는 동안 **화면을 90초 유지**해
   자동 재연결 창을 만든다(화면이 꺼져 있으면 재연결이 지연된다 — 2026-11-12 실측).

추가로 root 가능한 기기에서는 `persist.adb.tcp.port=5555`가 비어 있을 때 1회 설정해
**다음 부팅부터** USB 없이 `:5555`가 열리게 한다.

### 현재 기기 실측 (2026-11-12, 읽기 전용)

| 기기 | 빌드 | `ro.debuggable` | `adb root` | `persist.adb.tcp.port` | `service.adb.tcp.port` |
|---|---|---|---|---|---|
| S22 `192.168.190.49:5555` | `user` | `0` | 불가 | 비어 있음 | `5555` |
| A90 `192.168.190.208:5555` | `user` | `0` | 불가 | 비어 있음 | `5555` |
| S7 `192.168.190.216:5555` | `userdebug` | `1` | 가능(현재 adbd root) | `5555` | `5555` |

→ 훅은 **S7에서만 실제로 동작**하고, S22/A90은 "root 불가"로 조용히 건너뛴다.

## 2. 범위

### 포함
- 설정 토글 1개 (`relay.postBootHook`, 기본 OFF) — 모든 기기에 시도.
- 부팅 ID(`/proc/sys/kernel/random/boot_id`, 폴백 `/proc/stat`의 `btime`)로 **부팅당 1회**.
- 기기별 판정 결과를 UserDefaults에 영속 (`relay.postBoot.boot.<physicalId>`).
- `adb root` 출력 판정 · adbd 재시작 뒤 재연결(네트워크는 `disconnect`→`connect`, USB는 `get-state` 폴링).
- `/sys/power/wake_lock`에 `relayconsole` 기록 + 검증.
- root 가능 기기에서 `persist.adb.tcp.port=5555`가 비어 있으면 1회 설정.
- 부팅 직후 `screen_off_timeout`을 `max(원래, 120000)`ms로 올리고 90초 뒤 복구 — Wi-Fi 국가 코드 갱신 뒤 재연결 창.
- 미러링 중이면 보류(다음 틱에 재시도) — `adb root`가 scrcpy를 죽이기 때문.
- 결과를 `DebugLogger` + `IssueLog`(`postboot.hook`) + 설정 화면 상태 줄에 표시.
- 실패 시 부팅당 최대 3회, 10분 쿨다운 뒤 재시도.

### 제외
- mDNS 전용 전송(`adb-…._adb-tls-connect._tcp`)에서의 root 재시작 — `:5555`/USB 전송이 처리한다.
  mDNS만 있는 기기는 훅을 건너뛴다(로그 1회).
- `service.adb.tcp.port`를 즉시 바꾸기 위한 **두 번째 adbd 재시작** — persist 설정은 다음 부팅부터 적용된다.
  ROM이 persist를 service로 승격하지 않으면 이 훅만으로는 다음 부팅에 5555가 열리지 않을 수 있다(한계로 기록).
- 폰이 **잠들기 전에** 웨이크락을 거는 부트 스크립트 — 앱은 연결된 뒤에만 실행할 수 있다.
  필요하면 Magisk `service.d`/init 스크립트로 폰 쪽에서 처리해야 한다(별건).

## 3. 설계

### 3.1 진입점
`DeviceMonitor.resolveDevices()`가 `found`를 계산한 뒤 매 틱 `PostBootHookController.consider(serials:)`를 호출한다.
- 새 연결뿐 아니라 **연결 중인 모든 기기**를 넘긴다 — 미러링 보류·앱 재시작 후 첫 틱을 모두 커버한다.
- 컨트롤러는 `inFlight` 집합으로 기기별 중복 실행을 막는다.
- 연결이 끊기면 `forget(serial:)`로 부팅 토큰 캐시를 지운다(재부팅 후 새 boot_id를 다시 읽기 위함).

### 3.2 부팅 1회 판정
1. `boot_id`를 읽어 `bootToken`으로 쓴다. 비어 있으면 `/proc/stat`의 `btime`을 쓴다.
   캐시는 60초 — Mac이 잠든 사이 폰이 재부팅한 경우에도 새 토큰을 다시 읽는다.
2. `ro.boot.serialno`(물리 ID)를 읽는다. 실패하면 serial로 폴백.
3. UserDefaults `relay.postBoot.boot.<physicalId>`와 비교한다.
   - 같으면 이미 처리한 부팅 → 즉시 반환.
   - 다르면 처리 대상.
4. 성공·스킵·실패(3회 소진) 시 토큰을 저장한다. 실패 중에는 10분 쿨다운.

### 3.3 실행 순서
```
설정 ON?
  → mDNS 전용? (예: 로그 1회 후 종료)
  → 미러링 중? (예: 보류, 다음 틱)
  → boot_id/physicalId 읽기
  → 이미 처리한 부팅? (예: 종료)
  → ro.debuggable == 1 또는 id -u == 0?
      아니오 → "root 불가" 스킵 + 토큰 저장
  → adb root
      - "already running as root" → 재시작 없음
      - "restarting adbd as root" → 재연결 대기
      - "cannot run as root" → 스킵 + 토큰 저장
  → 재연결 확인 (최대 20초)
  → id -u == 0 확인 (실패 시 재시도/실패)
  → persist.adb.tcp.port != 5555? → setprop persist.adb.tcp.port 5555 (실패는 경고)
  → /sys/power/wake_lock에 relayconsole 기록 + cat 검증
  → 부팅 직후 화면 90초 유지 (screen_off_timeout 임시 상향 → keyevent 224 → 복구)
  → 성공 토큰 저장 · IssueLog · 상태 줄
```

> **순서 근거 (2026-11-12 S7 실측)**: `adb unroot`로 재부팅 직후 상태(adbd=shell, uid 2000)를 재현하면
> `setprop persist.adb.tcp.port 5555`가 `Failed to set property 'persist.adb.tcp.port' to '5555'.`로 실패한다.
> persist 속성은 root 승격 **뒤**에만 쓸 수 있으므로 `root → persist → wakelock → settle` 순서를 고정한다.

### 3.4 재연결
- 네트워크(`IP:PORT`): 1초 뒤 `adb disconnect <serial>` → `adb connect <serial>` → `get-state` 폴링.
  - connect는 `ProcessRunner` 5초 데드라인. 75초 macOS TCP 대기 금지.
- USB: `adb -s <serial> get-state` 폴링만 한다(재열거는 adb 서버가 처리).
- 공통 상한 20초. 초과 시 실패로 기록하고 10분 뒤 재시도.

### 3.5 설정 UI
`설정 → 일반 → Wi-Fi ADB` 섹션에 토글 + 한계 설명 + 마지막 결과 줄.
- 문구: root 가능한 기기만 적용 · adbd 1회 재시작 · 미러링 중 보류 · `persist`는 다음 부팅부터.
- 결과 줄은 `PostBootHookController.lastMessage` (성공/실패 색 구분).

### 3.6 부팅 직후 화면 유지 (Wi-Fi 재연결 창)

1. `settings get system screen_off_timeout`을 읽는다. `-1`(항상 켜짐)이면 그대로 둔다.
2. `max(원래, 120000)`ms로 임시 상향하고, 원래 값과 시각을 UserDefaults에 예약한다.
3. `input keyevent 224`(WAKEUP)로 화면을 깨운다.
4. 90초 대기 — Android `WifiCountryCode`의 부팅 시 1회 `Disconnect wifi to force update` 뒤
   자동 재연결이 완료될 시간을 준다.
5. 원래 `screen_off_timeout`으로 복구한다. 복구에 실패하면 예약을 남겨 다음 실행에서 재시도한다
   (10분 이내만 — 그 사이 사용자가 바꿨을 수 있다).

> 2026-11-12 19:17 S7 이탈은 웨이크락 실패가 아니라 이 국가 코드 갱신과 화면 꺼짐이 겹친 것이었다.
> 20:00:58 재부팅에서는 이 창으로 재연결을 확보했다. 잠금화면 정책 때문에 화면이 다시 꺼질 수는 있으나,
> 목적은 화면 상시 켜짐이 아니라 **재연결 창**이다.

## 4. 파일

| 파일 | 변경 |
|---|---|
| `Sources/RelayConsole/Droid/PostBootHook.swift` | 신규 — 순수 로직 + `@MainActor` 컨트롤러 |
| `Sources/RelayConsole/Droid/DeviceMonitor.swift` | `consider`/`forget` 호출 |
| `Sources/RelayConsole/Views/SettingsView.swift` | 토글·설명·상태 줄 |
| `Sources/RelayConsole/Resources/{en,ko}.lproj/Localizable.strings` | 문구 키 en/ko 동시 |
| `Sources/RelayConsole/Utils/ErrorCodes.swift` | `E-MAC-ADB-0009`, `E-MAC-ADB-0010`, `E-MAC-PERM-0001` |
| `Sources/RelayConsole/Utils/IssueLog.swift` | `postboot.hook` 종류 |
| `Tests/RelayConsoleTests/PostBootHookTests.swift` | 순수 로직 테스트 |
| `docs/TODO.md` · `docs/CHANGELOG.md` · `docs/MANUAL_VERIFY.md` | 기록 |

## 5. 검증 (2026-11-12 완료)

- `swift test` **909/909** (신규 24 — 판정·부팅 토큰·재시도·화면 유지/복구).
- `./scripts/build-macos.sh debug` 완료 — 1.25.0, build `20261112.200829`.
- 실기기:
  1. S7 2차 재부팅(20:00:58) → USB 없이 `:5555` 연결 ✅
  2. 로그 `root=restarted · persist=유지 · wake=held · settle=90초`, `postboot.hook` `ok:true` ✅
  3. `cat /sys/power/wake_lock`에 `relayconsole`, 화면 꺼짐에서도 ADB 유지 ✅
  4. 같은 부팅에서 앱 재시작 → 훅 재실행 없음 ✅
  5. S22/A90 → `건너뜀 — root 불가 (debuggable=0 uid=2000)`, 연결 유지 ✅
  6. 미러링 중 보류 — 코드 경로만 확인, 실제 재현은 `MANUAL_VERIFY` §40 126 ⬜
- `MANUAL_VERIFY` §40 121~125 ✅ · 126 ⬜.

## 6. 리스크·한계

| 리스크 | 대응 |
|---|---|
| `adb root`가 미러링을 끊는다 | 미러링 중 보류, 종료 뒤 재시도 |
| `adb root` 직후 앱이 못 붙는다 | 명시적 disconnect/connect + 20초 폴링, 실패는 상태·로그 |
| production 빌드에서 `adb root` 오작동 | `ro.debuggable`/`id -u` 선검사로 호출 자체를 막음 |
| 폰이 연결 전에 잠든다 | 앱으로 해결 불가 — 폰 쪽 부트 스크립트 필요(한계 명시) |
| 부팅 직후 Wi-Fi 국가 코드 갱신이 연결을 끊는다 | 90초 화면 유지로 재연결 창 확보. 잠금화면 정책으로 화면이 다시 꺼질 수는 있음 |
| `screen_off_timeout` 복구 실패 | 원래 값을 UserDefaults에 예약, 다음 실행에서 10분 이내 재시도 |
| ROM이 persist를 service로 승격하지 않는다 | 다음 부팅 5555 미보장 — 로그·문서에 한계 기록 |
| 설정 OFF인데 토큰이 남는다 | 토큰은 설정과 무관하게 기기별로만 저장, OFF면 consider가 즉시 반환 |
