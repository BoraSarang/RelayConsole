# PLAN_wifi_auto_tcpip_relayconsole — USB 연결 시 자동 Wi-Fi ADB (macOS)

> 착수: 2026-09-27 · 규모 M · 상태: **완료 (육안 3단계 대기)**
> 참조 스크립트: `/Users/lee/Documents/AGENTS/development/scripts/scrcpy_run.sh` (참고 자료로만 읽음 · 실행하지 않음)
> 기존 기능: `WifiAdb.swift` · `Views/WifiOnboarding.swift` · `PLAN_wifi_onboarding_relayconsole`

---

## 0. 실측이 먼저다 — 기존 기능이 이 기기에서 고장이다

사용자 요청: "USB 를 연결 하면 자동으로 IP 도 사용 할 수 있도록". 자동화를 붙이려다
**이미 있는 Wi-Fi 전환 버튼이 이 기기에서 틀린 IP를 잡는다**는 걸 계측으로 확인했다.

| IP 판별 방법 | 실측 반환 | 판정 |
|---|---|---|
| ① 앱 1순위 `ip -s serial shell ip route get 1.1.1.1` | `10.148.183.154` (dev `rmnet_data1`) | ❌ **셀룰러 IP** |
| ② 앱 2순위 `ip -f inet addr show wlan0` | **빈 출력** | ❌ 인터페이스 없음 |
| ③ 앱 3순위 `ifconfig wlan0` | **빈 출력** | ❌ 동일 |
| ④ **맥 기본 게이트웨이** `route -n get default` | `10.233.247.205` | ✅ **정답** |

```
# adb shell ip -f inet addr  (실측 전문의 핵심)
1: lo:              inet 127.0.0.1/8
32: rmnet_data1@…:  inet 10.148.183.154/30     ← 셀룰러
60: swlan0:         inet 10.233.247.205/24     ← Wi-Fi (Samsung)
```

**근본 두 가지**
1. **Samsung 은 Wi-Fi 인터페이스가 `wlan0` 이 아니라 `swlan0`** — 하드코딩된 `wlan0` 은 빈 값
2. **`ip route get 1.1.1.1` 의 `src` 는 인터넷으로 나가는 경로의 주소** — 핫스팟 폰은
   셀룰러로 나가므로 **Wi-Fi IP 가 아니라 셀룰러 IP** 를 준다. 게다가 **빈 값이 아니라
   값을 반환하므로** ②③(올바른 방법)에 **도달조차 못 한다**

### 두 번째 실측 — 스크립트의 `ping` 도 이 기기에서 오판한다

스크립트는 도달 확인에 `ping -c 1` 을 쓴다. 그대로 베끼면 **연결 가능한 기기를
"닿지 않습니다" 로 처리**하게 된다.

| 확인 | 결과 |
|---|---|
| 맥 → `ping 10.233.247.205` | **100.0% packet loss** |
| 폰 → `ping 10.233.247.205` (자기 자신) | 0% loss, **0.142ms** |
| 맥 → `nc -z 10.233.247.205 5555` | **succeeded** |
| `adb -s 10.233.247.205:5555 get-state` | `device` |

같은 주소가 **자기 자신에게는 통하고 맥에서만 막힌다** = 경로 문제가 아니라
**핫스팟 폰이 ICMP 응답을 안 하는 것**. adb 포트(5555)는 열려 있다.
⇒ 도달 확인을 **`nc -z` (실제 서비스 포트)** 로 바꾼다. 우리가 하려는 일의 대상이
그 포트이므로 ping 보다 직접적인 신호이며, **이 기기에서 실제로 통과**함을 확인했다.

⇒ 지금 버튼을 누르면 `adb connect 10.148.183.154:5555` 를 시도하고 실패한다.
스크립트가 **게이트웨이를 1순위**로 둔 이유가 정확히 이것이다 (`# 핫스팟 환경` 주석).

## 1. 결정 (사용자 확정)
- **① USB 감지 시 자동 실행** — 기본 ON, 설정에서 OFF 가능
- **② 같은 폰이 USB/TCP 두 줄로 보이면 둘 다 유지 + 배지** — 배지(`USB` / `IP:5555`)는
  **이미 있음**(`MenuBarPopoverView.connectionBadge`). 신규 UI 불필요

## 2. 알고리즘 (스크립트 준수 + 자동화 안전장치)

```
USB 기기 신규 감지
  ├─ 이미 <ip>:5555 TCP 로 열려 있으면  → 아무것도 하지 않는다 (멱등)   ★신규
  ├─ IP 후보 결정
  │   ① 맥 게이트웨이 (핫스팟이면 = 폰)      ★1순위 — 위 버그의 해법
  │   ② 기기 ip addr 의 Wi-Fi 인터페이스(wlan*/swlan*/wlp*) inet
  │   ③ 기기 ifconfig 전체
  │   ④ ip route get src  ← ★마지막으로 강등 (셀룰러일 수 있음)
  ├─ nc -z -G 2 <ip> 5555                  ★신규 — 닿지 않으면 tcpip 하지 않는다
  │    실패 → "도달 불가" 라는 **명확한 사유**로 종료 (adbd만 재시작된 채 끝나지 않게)
  │    ★ ping 이 아니라 **adb 포트**다 — 아래 실측 근거
  ├─ adb -s <usb> tcpip 5555
  ├─ adbd 준비 대기 — **connect 를 최대 3회 · 2초 간격 재시도**  ★고정 대기(800ms) 대체
  ├─ adb disconnect <ip>:5555   (고아 연결 정리)
  ├─ adb connect <ip>:5555
  └─ "No route to host" → adb kill-server → start-server → 1회 재시도  (스크립트)
```

### "USB 를 뽑아도 IP 로 계속" 되는 원리 (사용자에게 설명할 사실)
`adb tcpip 5555` 는 **기기(adbd)이 네트워크에서 리스닝을 하도록** 전환하는 명령이다.
케이블을 뽑는 것은 adbd 를 죽이지 않으므로 **TCP 연결은 그대로 살아 있다.**
다만 **기기를 재부팅하면 adbd 가 USB 모드로 돌아가므로 다시 한 번** tcpip 이 필요하다.
→ 그래서 "USB 를 연결하면 자동으로" 가 정확히 올바른 트리거다 (재부팅 = USB 를 다시 꽂게 됨).

### 자동 모드에서 반드시 지킬 안전장치
| 위험 | 방어 |
|---|---|
| `tcpip` 실행 시 adbd 재시작 → **USB 가 잠깐 사라졌다 돌아옴** | 신규 감지 루프에 재진입하지 않도록 **멱등 검사 + 쿨다운** |
| 같은 기기에 중복 실행 | in-flight 세트 + 직렬화 |
| 자동 실패가 사용자에게 방해 | 자동 경로는 **팝업 없음** — 버튼 옆 배지 + IssueLog |
| 사용자가 이미 TCP 를 열었는데 다시 tcpip | **이미 열려 있으면 skip** → 흔들림 자체가 없음 |

## 3. IN / OUT
**IN** — IP 판별 순서 수정(버그) · `swlan0` 계열 지원 · ping 도달 확인 · connect 재시도 ·
`disconnect→connect` · No-route-to-host 복구 · 자동 트리거(기본 ON) · 설정 토글 ·
자동 상태 배지 · L10n · 테스트

**OUT** — 기기 목록에서 USB 항목 숨김(사용자 결정) · 백그라운드 상시 감시(폴링 훅만 사용) ·
`adb tcpip` 자동화 스크립트 설치(brew/경로 변경 금지)

## 4. 테스트 (신규 9건)
1. `isWifiInterface` — `swlan0` ✓ `wlan0` ✓ `wlp2s0` ✓ `rmnet_data1` ✗ `lo` ✗ `ap0` ✗
2. `parseWifiIp` — `ip addr` 다중 블록에서 Wi-Fi 만 (`lo`/`rmnet_data1` 건너뜀)
3. **`resolveIp` 순서** — 실측 샘플 그대로: 게이트웨이가 정답, `routeText`(셀룰러)는 **미사용**
4. `resolveIp` — 게이트웨이 없으면 기기 `ip addr` → ifconfig → route 순
5. 게이트웨이가 셀룰러 IP 라면? → 게이트웨이를 **쓰면 안 된다**(분기 필요성 검토)
6. 기존 `parseWlanIp` 테스트 4건 **회귀 없음**
7. args 형태 3건 회귀 없음
8. 멱등 판정 — 이미 TCP 열려 있으면 skip
9. L10n en/ko 1:1 + **변환자 나열** (기존 전수 스캔이 자동 검증)

## 5. L10n (en/ko 1:1 · 7키)
| 키 | ko | 비고 |
|---|---|---|
| `settings.wifi.section` | Wi-Fi ADB | 설정 섹션 |
| `wifi.setting.auto` | USB 연결 시 자동으로 Wi-Fi ADB 열기 | 기본 ON |
| `wifi.setting.auto.help` | 케이블을 뽑아도 IP 로 계속 연결됩니다. **재부팅하면 USB 를 다시 꽂을 때마다** 한 번씩 필요합니다. | 한계를 설명에 적음 |
| `wifi.auto.notReachable` | %@ 에 닿지 않습니다 — 같은 Wi-Fi 에 있는지 확인하세요 | `nc` 실패 [표시②] |
| `wifi.auto.waiting` | adb 연결 대기 중… (%d/%d) | `%d` — 숫자 키 규칙 (크래시 교훈) |
| `wifi.auto.alreadyOpen` | 이미 Wi-Fi 로 열려 있습니다 — %@ | 멱등 skip |
| `wifi.badge.autoFailed` | 자동 연결 실패 | 배지 (팝오버) |

## 6. 검증 (DoD)
- [x] `swift test` **463 + 104 = 567 / 0 failed** (착수 시 551, **+16**)
- [x] `./scripts/build-macos.sh debug` **EXIT=0** (앱 + appex 팀 `6GPJQ7BQC9` 일치)
- [x] L10n **762키 en/ko 1:1** · U+FFFD 0건 · 신규 컴파일 경고 0
- [x] **계측**: IP 판별 순서 = 실측 샘플로 검증. `nc -z 10.233.247.205 5555` **succeeded** (실기)
- [x] **회귀 실증**: `routeText` 를 1순위로 되돌리면 `routeTextIsNeverPreferredOverIfAddr` 가
      **실패**하고 셀룰러 IP(`10.148.183.154`)를 고르는 것을 확인 → 복구
- [ ] **육안 (사용자 — USB 물리 연결 필요, 코드로 대체 불가)**
  1. USB 꽂기 → **자동으로** IP 열림 (`*:5555` 항목 등장)
  2. **USB 뽑기 → 그대로 유지** (이게 핵심)
  3. 기기 재부팅 → USB 再삽입 → 자동 재연결 (재부팅마다 tcpip 1회 필요)

## 6-1. 실기에서 못 돌린 부분 (이유 명시)
`adb tcpip` → `connect` 는 **USB 물리 연결이 있어야** 실행된다. 지금 이 기기는
Wi-Fi(`10.233.247.205:5555`)로만 붙어 있어 그 경로는 계측하지 못했다.
코드 경로(IP 판별·도달 확인·멱등·재시도)는 전부 순수 함수/단위 테스트로 고정했고,
**나머지는 위 육안 3단계가 유일한 증거**다. 추측으로 통과시키지 않는다.

## 7. 남기는 사실
- **`ip route get <외부주소>` 의 `src` 는 "인터넷으로 나가는 쪽" 의 주소** 라 Wi-Fi 라고 가정하면 안 된다.
  핫스팟 + 셀룰러 동시 켜진 기기에서는 **항상 셀룰러가 나온다.**
- **맥의 기본 게이트웨이는 핫스팟 폰이면 곧 폰 IP** 다 — 기기한테 묻지 않고 알 수 있는 정보가 있다
- `adb tcpip` 은 **상태를 바꾸는 명령**이다(읽기 전용 아님). 실패해도 USB 경로는 살아 있으므로
  위험도는 낮지만 **adbd 가 재시작**된다는 사실을 상태 표시에 반영한다
