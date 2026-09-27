# PLAN — 로그 창 CPU (기다 태그 기기 측 제외) (2026-09-28)

> 성격: **성능 · 계측 기반 착수** · TODO 1순위 착수 지점
> 관련: `docs/TODO.md` "★ 1순위 로그 창 CPU" · `docs/plans/PLAN_log_search_relayconsole.md` · `.agent/session-2026-09-28-macos.md` §9
> 실기: SM-S901N (Android 15) · `10.38.120.211:5555` — 표시는 [표시①] 규칙대로 원문

---

## 0. 착수 전 계측 — TODO 의 질문에 대한 답

TODO 가 남긴 질문:

> ⚠️ **라벨 exclusion 지원 여부는 기기에서 확인해야 한다** — adb host 옵션만으로 되는지
> `logcat` 버전에 따라 다르다. **확인 없이 구현하지 말 것**

세 방법을 실기에서 각각 검증했다. **결론: 된다 — 단, `--regex` 가 아니라 필터식이다.**

| 방법 | 형태 | 실측 결과 |
|---|---|---|
| ① `--regex` 부정 순방위 | `--regex='^(?!.*SemApTrafficData)'` | ❌ **제외 안 됨.** SemAp 3,918건 잔존 |
| ② 기기 측 `grep -v -E` | `adb shell "logcat … \| grep -v -E 'SemApTrafficData\|HeatmapThread'"` | ✅ 제외됨 (0건) |
| ③ **logcat 필터식 `<tag>:S`** | `logcat -v time '*:W' 'SemApTrafficData:S' 'HeatmapThread:S'` | ✅ **제외됨 (0건)** |

`logcat --help` 원문(기기에 실제로 있는 문구):

> `*:S <tag>` prints only `<tag>`, **`<tag>:S` suppresses all `<tag>` log messages.**

**① 이 기기에서 실패한 이유** — Android 의 `logcat --regex` 는 ECMAScript 정규식 엔진을 쓰지 않는다
(libutils `RegExp`). **부정 순방위 `(?!…)` 를 지원하지 않고, 컴파일 실패도 오류 없이 통과시킨다.**
→ "수를 줄였다" 는 계측에 **`--regex` 가 아니라 allowlist(검색어) 로 잡혔다** 는 뜻이다.
검색 기능이 잘 먹는 이유가 "`--regex` 가 강력해서" 가 아니라 **양의 일치만 쓰기 때문**이었다.

**② 는 되지만 쓰지 않는다** — 원격 파이프라 quoting 위험(`|`·`'`), 프로세스 1개 추가,
그리고 adb 종료 시 원격 sh 의 수명 관리가 필요해진다(2026-09-27 의 adb 누적 회귀와 같은 종류).
**③ 은 adb 인자 배열 한 칸** — quoting 위험 0 · 추가 프로세스 0.

## 1. 무엇이 소음인가 — 20초 전수 스캔

`logcat -v time '*:W'` 20초 채집 = **282,655줄**.

| 태그 | 건수 | 비중 | **서로 다른 메시지** | 예시 |
|---|---:|---:|---:|---|
| `SemApTrafficData` | 261,521 | **92.5%** | **1** | `Empty traffic data` |
| `ActivityManager` | 6,009 | 2.1% | 44 | `Foreground service started from background…` |
| `ThermalManagerService$ThermalHalWrapper` | 1,483 | 0.5% | 2 | `no threshold data for temperature type 0` |
| `HeatmapThread` | 1,178 | 0.4% | 3 | `!@Could not open '/efs/FactoryApp/bsoh', errno = 13` |

**소음의 정의는 "비율" 이 아니라 "반복도" 다.** `SemApTrafficData` 는 메시지가 **딱 1종류**이고
20초에 26만 번(= 초당 1.3만 회) 반복된다. 사람이 그 1줄에서 새로 알 수 있는 것은 **0** 이다.
`HeatmapThread` 도 3종류가 모두 `/efs/FactoryApp` 공장 EFS 접근 실패 — 이 기기에 공장 EFS 가 없다는
사실의 반복이라 조치 대상이 아니다.

**부수 관측(결론 아님 — 고립하지 않았다)** — 두 태그 모두 네트워크 상태 조회와 함께 늘어난다.
같은 창에 `ActivityManager: … service com.nisargjhaveri.netspeed/.IndicatorService` 가 초당 1회 뜨고,
네트워크 속도 표시 앱의 포그라운드 서비스 경고가 반복된다. **어느 쪽이 원인인지는 규명하지 않았다.**

## 2. 부하가 100배 변한다 — 계측 방법의 함정

같은 명령을 5초씩 재면 **8,679줄 ~ 114,195줄** 이 나왔다. 스팸은 **간헐적**이다.

→ **5초 창 비교는 근거가 아니다.** 짝지측정(ABAB) + 총량 확인으로 바꾼다.
그리고 `logcat` 은 `-t/-T` 없이 **버퍼 덤프 후 추종**하므로 짧은 창의 앞부분은 과거 로그다.
지속 유입률을 재려면 `-T 1` 로 시작점을 잡아야 한다. 이 구분을 안 하면 **버퍼 크기만큼 부풀려진다.**

## 3. 효과 실측 (같은 기기 · 짝지측정)

| 조건 | 5초 줄 수 |
|---|---:|
| `*:W` | 114,195 → 58,520 → 58,033 |
| `*:W` + `SemApTrafficData:S` `HeatmapThread:S` | **14,791** (SemAp 0 · Heatmap 0) |

- **87% 감소** · stderr 0바이트 · `--------- beginning of …` 구획선 **보존**
- 앱 CPU(창 개방, `top -l 2`): **102.4%** / MEM 107MB / 스레드 7 → 개선 대상 그대로 남아 있음
- adb 자식 `logcat` **1개** — 2026-09-27 의 누적 회귀는 재발하지 않음

## 4. 변경 범위

| 파일 | 변경 |
|---|---|
| `Sources/RelayConsole/Views/LogViewerView.swift` | `LogcatFilter.noisyTags`(상수) · `filterSpecs(minLevel:excluded:)`(순수) · streamer 제외 상태 · arg 조립 · 푸터 배지 + 토글 |
| `Tests/RelayConsoleTests/LogViewerTests.swift` | 필터식 생성 · 태그 정합성 방어 테스트 |
| `Resources/Localizable.xcstrings` + `en.lproj` + `ko.lproj` | 3키 en/ko 1:1 |

## 5. 정직성 설계 [표시②]

**E 레벨 줄을 감추는 것**이라 기본값을 켜되 **숨기지 않는다**:

1. **푸터 배지** — `기기에서 %d개 태그 제외` 를 **항상** 보인다(토글 꺼도 "0개" 로 보인다)
2. **툴팁에 실제 태그명** — `SemApTrafficData, HeatmapThread`
3. **토글** — 기본 ON, 1클릭으로 전부 표시. `relay.*` 키에 저장
4. **범위 제한** — 제외는 **로그 창의 실시간 스트림에만** 적용된다.
   `IncidentBundle` 캡처(`logcat -d`)와 `logcatKeywords` 스캔은 **전량 그대로**다.
   → "incident 를 뽑아 보면 저게 보인다" 는 사실이 유지된다.
5. **검색과의 상호작용** — 검색어는 그 뒤에 적용되므로, 제외된 태그를 검색하면 0건이 난다.
   배지가 항상 보이므로 **숨겨지지 않지만**, 사용자가 혼란스러울 수 있다 → 본 PLAN 에 기록

## 6. 하지 않는 것 (계측 전까지 손대지 않는다)

- **`ThermalManagerService$ThermalHalWrapper`** (0.5%, 2종류 반복) — 유력하지만 **미검증 리스크가 있다**:
  태그에 `$` 가 들어가고 길이가 41자다. 로그가 기록될 때 태그가 절단/변형되면
  `<tag>:S` 가 **조용히 안 맞을 수 있다.** 지금 넣으면 "효과 없음" 을 못 구분한다 → 실측 후 판단
- 자동 감지(반복도 상위 태그를 자동 제외) — [표시②] 리스크가 커서 별도 과목
- 레벨 기본값 변경(`*:W`) · 링 2000행 · `textSelection(.enabled)` 등 렌더 쪽

## 7. 검증 [HARD]

- `swift test` → `./scripts/build-macos.sh debug` → **재시작된 앱으로** 로그 창 개방 → CPU 재계측
- 계측 전 상태(창 개방 102.4%)와 **같은 조건**에서 비교한다. 구버전 앱으로 측정하면 무의미하다
- L10n en/ko 1:1 · U+FFFD 0건

---

## 8. 최종 결과 (구현 후 계측)

### 8-1. 비용의 진짜 출처 — "개방 순간"의 링 버퍼 덤프

첫 측정에서 가장 이상한 점이 있었다. **기기 유입률이 45줄/초**(스팸 꺼짐)인 구간에서도
앱 CPU 는 개방 직후 **99%** 였다. 살아 있는 줄이 45줄/초인데 99% 가 나올 이유가 없다.

원인은 **`logcat` 이 `-t/-T` 없이 링 버퍼 전체를 먼저 덤프**하는데,
그 버퍼(main 5MiB · 소비 4MiB)에 **이전 스팸 구간의 역사가 그대로 남아 있기 때문**이었다.

| 버퍼 덤프 (`logcat -d`) | 줄 수 |
|---|---:|
| `*:W` | **231,982** |
| `*:W` + `SemApTrafficData:S` `HeatmapThread:S` | **16,763** (7.2%) |

즉 **"개방 순간 99%" 의 주된 원인은 라이브 스팸이 아니라 버퍼에 쌓인 과거 스팸**이었다.
→ 이 때문에 adb 측 제외가 효과가 있는 이유가 단순해진다: **전송량 자체를 줄인다.**

### 8-2. CPU 짝지 A/B

스팸이 간헐적이므로 **순서를 뒤집어 2라운드**, 각 측정에서 **부하를 동시에** 잡았다.

| 라운드 | 제외 OFF | 제외 ON | 동시 유입률(줄/3초) |
|---|---|---|---|
| 1 (OFF 먼저) | 98.5% → 42.4% | 4.8% → 12.8% | 19→398 / 20→299 |
| 2 (OFF 먼저) | 99.3% → 27.4% | 14.5% → 12.6% | 138→167 / 143→175 |
| 이전 라운드 (ON 먼저) | 101.6% → 49.3% → 12.4% | 61.5% → 9.4% → 3.6% | 220 / 280 |
| 이전 라운드 (ON 먼저) | 101.1% → 55.1% → 32.5% | 61.4% → 11.7% → 3.8% | 286 / 308 |

**순서를 바꿔도 결론이 같다** → 순서 효과(측정 순서에 따른 편향) 가 아니다.
개방 직후 **99% → 5~15%**, 안정 구간 **27~55% → 3.6~14.5%**.

### 8-3. 첫 계측의 오류를 남겨 둔다

초기 측정에서 **"초당 1.4만 줄을 1% 로 줄인다"** 는 기대를 TODO 에서 읽었다.
실제로 줄은 **-90.6%**(스팸 창 176,311 → 16,581 줄/8초) 가 맞지만,
**"CPU 의 40% 가 1% 가 된다" 는 식의 환상은 계측하지 않았다.** 환상은 남아 있었다.

**계측 부수 발견** — 스팸은 6초당 **22줄 ~ 114,195줄** 로 **100배** 변한다(간헐적).
`logcat` 은 버퍼 덤프 후 추종하므로 **짧은 창의 앞부분은 과거 로그다.**
→ 5초 창 비교는 근거가 되지 않는다. **짝지측정 + 부하 동시 계측**이 유일하게 정직한 방법.

## 9. 부수 발견 — `(?i)` 가 이 기기에서 죽는다 (같은 근원)

`noisyTags` 와 다른 기능에서 **같은 엔진 한계**가 또 나왔다.

```
adb shell logcat -v time '*:W' --regex=(?i)ActivityManager
  → 0줄 · stderr: regex_error was thrown in -fno-exceptions mode
```

종전 코드 주석은 "logcat `--regex` 는 Java `Pattern` 이므로 `(?i)` 지원된다" 였으나 **거짓**이었다.
→ **대소문자 무시 검색이 이 기기에서 항상 0건**이었다(앱은 원인을(stderr) 그대로 보여 줬다 — [표시②] 는 작동).

**수정(사용자 지시)** — `(?i)` 접두 대신 **글자별 문자클래스**: `anr` → `[aA][nN][rR]`.
문자클래스는 어떤 엔진에서도 뜻이 통한다. 실기 검증(버퍼 덤프 기반 결정적 비교):

| 패턴 | `Scheduler` 표본 결과 |
|---|---:|
| `Scheduler` (정확히) | 585줄 |
| `scheduler` (전부 소문자) | 36줄 |
| `SCHEDULER` (전부 대문자) | 0줄 |
| **`[sS][cC]…` (문자클래스)** | **607줄** = 585 + 36 의 합집합 |

→ 엔진이 문자클래스를 지원하고 **양쪽 대소문자를 모두 찾는다**는 것이 실기로 증명됐다.
회귀 고정: `caseInsensitiveNeverUsesInlineFlags` (되돌리면 잡힌다).

---

## 10. 3번째 태그 — 안전 필터가 검증된 태그를 버리고 있었다

`ThermalManagerService$ThermalHalWrapper` 는 TODO 에 "**실기 검증 후** 다룬다" 로 남아 있었다.
검증부터 했다.

### 10-1. 선행 검증 — `$` 와 39자가 문제인가

| 항목 | 결과 |
|---|---|
| 버퍼 덤프 중 해당 태그 | **2,874줄** (기록 형태 `E/ThermalManagerService$ThermalHalWrapper: …`) |
| `'<tag>:S'>` 적용 후 | **0줄** ✅ |
| 과잉 제외 여부 | 전체 194,910 → 185,309 = **딱 2,874줄만 감소** ✅ |
| 메시지 종류 | 2 (`no cooling device for cooling type 0` · `no threshold data for temperature type 0`) |

→ **`$` 도 길이 39자도 문제가 아니다.** 필터식 문법에서 `$` 는 특별하지 않다.

### 10-2. 그런데 내 안전 필터는 이 태그를 버렸다

직전 세션에서 만든 `safeTags` 의 허용 집합은 `A-Za-z0-9_` 였다 → **`$` 가 있는 이 태그는
조용히 탈락했다.** 실효가 아니라 **실패처럼 보이는** 상태였다(제외 안 되는데 배지만 뜬다).
`noisyTagsAreFilterSafe` 테스트가 이걸 잡아냈다 — 방어선을 먼저 깔아둔 것이 값을 했다.

→ **검증된 예외는 예외로 들여다보다.** `$` 를 허용 집합에 넣고, 왜 안전한지는 계측값으로 남겼다.
회귀 테스트 `dollarSignTagSurvivesTheSafetyFilter` 추가.

### 10-3. 지형을 재 보고 목록을 멈췄다

3종 제외 후 잔여 버퍼 13,811줄의 전수:

| 태그 | 건수 | 비중 | 메시지종류 | 판정 |
|---|---:|---:|---:|---|
| `ActivityManager` | 5,574 | 40.4% | 101 (94%가 1종) | **남긴다** |
| `BluetoothPowerStatsCollector` | 1,104 | 8.0% | 23 | 남긴다 |
| `System.err` | 710 | 5.1% | 186 | 남긴다 |
| `PermissionService` | 590 | 4.3% | **1** | **보류** |
| `LocalDisplayAdapter` | 513 | 3.7% | 513 | 남긴다 |
| `DeviceStorageMonitorService` | 332 | 2.4% | **2** | **보류** |

**`ActivityManager` 를 왜 남겼나** — 반복도로 보면 소음이다(5,247줄이 동일한 한 줄).
그런데 그 줄은 **범인 앱 이름을 담고 있다**(버퍼에 앱 7종):
`Foreground service started from background … : service com.nisargjhaveri.netspeed/.IndicatorService`.
`Empty traffic data` 와 달리 **"무엇이 이 기기를 망가뜨리는가" 를 말해주는 신호**다.
→ 기본 제외하지 않는다. **사용자가 고르게 하는 것이 정답**이며 태그 선택 UI 는 별도 과목.

**`PermissionService` · `DeviceStorageMonitorService` 를 왜 보류했나** — 순수 반복이라
제외 대상으로는 유효하다. 그러나 이미 7% 로 줄인 잔여량에서 **6.7%** 뿐이고,
숨기는 `E` 레벨 줄이 늘어날수록 배지보다 **침묵** 이 된다.
→ **뺄 이유가 부족하다.** 측정값과 판단 근거를 남기고 TODO 로 넘긴다.

## 11. 남은 설계 질문 — 목록이 아니라 **선택지** 로

사용자가 "이 태그를 숨겨라" 를 직접 할 수 있으면, 위의 모든 판단
(`ActivityManager` 를 남긴 이유 · `PermissionService` 를 뺀 이유)이 **사용자에게 넘어간다.**
그게 [표시②] 관점에서 가장 정직한 형태다 — AI 가 대신 판단하는 것보다.
→ **태그 선택 UI** 를 별도 과목으로 등록.
