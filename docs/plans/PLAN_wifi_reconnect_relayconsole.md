# PLAN_wifi_reconnect_relayconsole — TCP 유실 시 자동 재연결 (macOS)

> 착수: 2026-09-27 · 규모 M · 상태: **완료 (육안 대기)**
> 이어받음: `PLAN_wifi_auto_tcpip_relayconsole` (자동 개방 + stale 정리)

---

## 0. 무엇이 빠졌나 (자기 검토에서 발견)

`disconnectStaleEndpoints` 를 만든 뒤 검토하다 **더 큰 결함**을 찾았다. 정리는 "새 엔드포인트를
연 직후"에만 불리므로, **새 엔드포인트를 여는 경로가 없으면 정리도 실행되지 않는다.**

```
1. 앱 실행 중 IP 10.38.120.211 로 연결됨
2. 사용자가 폰을 다른 핫스팟으로 이동 → IP 가 172.30.x.x 로 바뀜
3. ★ 앱이 새 IP 로 reconnect 하지 않는다
      autoEnableIfEnabled 는 "USB 신규 감지"(DeviceMonitor:1034)에서만 호출된다
4. USB 도 뽑으면 새 IP 로는 아무도 connect 를 시도하지 않는다
5. 옛 10.38.120.211 항목이 stale 로 남음 → 같은 폰 2개 → 폴링 2배
```

**"USB 를 뽑아도 IP 로 계속" 라는 목표 자체가 IP 변경에 강해야 완성**된다.
이번 PLAN 의 대상: **TCP 엔드포인트 유실을 앱이 스스로 감지하고 다시 붙는다.**

## 1. 결정 (사용자 확정)
- **A** — TCP 엔드포인트 유실 시 **자동 재연결**. 사용자가 USB 를 다시 꽂지 않아도 된다.

## 2. 핵심 설계 — 물리 ID 로 "어느 기기" 를 추적한다

| 문제 | 답 |
|---|---|
| 유실된 TCP 엔드포인트가 **어느 폰**이었나? | `ro.boot.serialno` — IP 가 바뀌어도 고정(실측) |
| 새 IP 가 뭔가? | **맥 게이트웨이**(핫스팟이면 폰) → 2차 `ip addr` → `ifconfig` → `ip route` |
| 폰이 USB 로도 붙어 있는가? | 있으면 `tcpip` + connect, 없으면 **connect 만** (adbd 가 이미 TCP 모드) |
| tcpip 이 필요 없다 | 이미 TCP 모드면 `tcpip` 은 **adbd 를 재시작**하므로 건드리지 않는다 |

**재연결 흐름**
```
TCP 엔드포인트가 adb devices 에서 사라짐 (DeviceMonitor 끊김 루프)
  └─ 그 serial 이 TCP 형태인가?  (콜론 있음)
       └─ USB 모드 아님 (TCP 모드라면 tcpip 불필요)
            └─ 재연결 시도 (쿨다운 적용)
                 ① IP 후보 판별 (게이트웨이 1순위 — 기존 resolveIp 재사용)
                 ② nc 도달 확인
                 ③ adb connect
                 ④ 성공 → stale 정리 (같은 폰의 옛 IP)
                    실패 → 쿨다운 후 다음 폴링에서 재시도 (무한루프 방지)
```

### 안전장치 (이 작업의 핵심 위험 = 무한 재시도)
| 위험 | 방어 |
|---|---|
| connect 실패 → **무한 재시도** (폴링 5초마다 → adb 폭주) | **쿨다운** 기본 60초 · 연속 실패 시 지수 증가 |
| USB 로도 붙어 있는데 TCP 로 붙으려 함 (adbd USB 모드) | USB 존재 시 `tcpip` 먼저 (기존 auto 경로 재사용) |
| 사용자가 Wi-Fi ADB 를 끄고 싶은데 계속 붙음 | 설정 OFF 시완 무동 (`autoModeKey` 존중) |
| 재연결 중 새 이벤트 발산 | 재연결은 **끊김 1회당 1회**만 — 성공하면 루프 종료 |

## 3. IN / OUT

**IN** — TCP 유실 감지 · 물리 ID 기반 추적 · IP 재판별 · `nc` 확인 · `connect` · 쿨다운 ·
성공 시 stale 정리 · 재연결 결과 배지/로그

**OUT** — 백그라운드 상시 스캔 · Wi-Fi 스캔 API 로 네트워크 탐색(네트워크 권한 추가 필요) ·
`adb mdns services` (mDNS discovery — 추후 별건)

## 4. 테스트 (신규 8건 예정)
1. `isNetworkEndpoint` — TCP/USB 구분 (기존)
2. `parseDeviceList` — 유실 감지 입력 (기존)
3. **쿨다운** — 즉시 재시도 금지 · 쿨다운 경과 후 허용 · 연속 실패 시 지수 증가
4. **재연결 대상 판정** — TCP 유실만 대상 · USB 유실은 대상 아님
5. `shouldReconnect(autoEnabled:isNetwork:usbPresent:cooldownElapsed:)`
6. IP 후보 재사용 (기존 `resolveIp` 테스트가 보장)
7. `staleNetworkEndpoints` 회귀 (기존 5건)
8. 실패 시 `statusIsError` + 사유 노출 ([표시②] — 조용히 실패 금지)

## 5. 검증 (DoD)
- [x] `swift test` **490 + 104 = 594 / 0 failed** (착수 시 586, +8)
- [x] `./scripts/build-macos.sh debug` **EXIT=0** · L10n **766키 en/ko 1:1** · U+FFFD 0건
- [x] **쿨다운 판정 8건 고정** — 즉시 재시도 금지 · 60초 경과 허용 · 실패 시 2배 증가 ·
      15분 상한 · 15분 지나면 무조건 재시도(영구 포기 안 함) · 모드 OFF 차단 · USB 유실 배제
- [ ] **육안**: 핫스팟 이동(또는 Wi-Fi 끄기/켜기) 후 **USB 재삽입 없이** 기기 재등장
- [ ] **계측(육안 시 가능)**: 재연결 순간 adb 자식 수가 유실 → 0 → 재연결 후 정상,
      **무한 루프 없음** 확인

## 6. 남기는 사실
- **무한 재시도는 adb 폭주로 이어진다** — 폴링이 5초 주기이므로 쿨다운 없이는
  분당 12회 connect 시도가 된다. 쿨다운은 선택이 아니라 필수다
- **IP 재판별은 "같은 폰" 을 보장하지 않는다** — 같은 네트워크의 다른 폰일 수도 있다.
  그래도 `nc` + connect 로 실접속을 확인하므로 **연결되면 그 폰이 맞다**(adb 가 인증한다)
