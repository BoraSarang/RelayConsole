# RESEARCH_droid_devicecare.md — Droid Device Care 대시보드 조사
> 생성일: 2026-09-23 | 상태: **조사 중 (1차) — 최종 계획 미확정**
> 목적: 맥에서 안드로이드 상태를 Device Care 수준으로 보여주는 기능 조사 기록
> 재조사 방지용 원본 데이터 — 최종 PLAN 확정 전 참고 문서

---

## 0. 조사 스코프 & 현재 위치

| 항목 | 상태 |
|------|------|
| 시장·경쟁 분석 | ✅ 완료 (외부 리서치 + 검증) |
| ADB 수집 가능성 | ✅ SM_S901N 실측 완료 |
| 기존 Outpost 코드 분석 | ✅ 완료 |
| TetherLens 패턴 조사 | ✅ 완료 |
| UI 레퍼런스 (DevCheck/Inware 등) | ✅ 1차 정리 |
| **iStat 대시보드 목업 분석** | ✅ 완료 — §11 (HTML 복사 + 스크린샷) |
| 카드 On/Off 설계 방향 | 🟡 초안 |
| 스타일 방향 (미니멀 vs 데이터덕후) | 🟡 목업 = 데이터덕후 2열 — 채택 여부 미결 |
| 메뉴바 기본 표시값 | 🟡 목업 예시는 CPU/MEM/BAT/온도/NET — 미결 |
| **최종 구현 계획 (PLAN_v0.7)** | 🔴 미작성 — 추가 조사 후 |

**다음 단계**: 안드로이드 쪽 추가 조사 → 스타일·범위 확정 → PLAN_v0.7 작성.

**아티팩트**: `docs/research/Istat-Menus-Android-Dashboard.html` (Downloads에서 복사, 197KB React 번들)

---

## 1. 시장·경쟁 (외부 리서치 + 검증)

### 1-1. 핵심 결론
- 데스크톱(맥/윈) 안드로이드 앱 대부분은 **미러링·제어** 중심.
- **예쁘게 상태만 보여주는 전용 대시보드 앱은 사실상 공백.**
- 기기내 앱(DevCheck·Inware·AIDA64)은 화려하나 **폰 안에서만** 볼 수 있음.
- → 틈새: **iStat Menus for Android** / 맥 메뉴바 상주 상태 대시보드.

### 1-2. 경쟁표

| 앱 | 플랫폼 | 포지션 | 상태 모니터링 |
|----|--------|--------|---------------|
| Scrcpy | Linux/Win/Mac | 오픈소스 미러링 표준, 경량·저지연 | 거의 없음 |
| Vysor | Chrome/Win/Mac/Linux | 상용 미러링 | 화면 위주 |
| AirDroid | Web/Win/Mac | 파일·문자·알림 관리 | 배터리/저장소 수준 |
| ApowerMirror | Win/Mac/Android/iOS | 미러링+녹화 | 미러링 품질 |
| Android Studio Device Manager | Win/Mac | 개발자 공식 | Profiler (개발용) |
| **DevCheck** | Android 내 | 하드웨어 실시간 모니터 | Dashboard·그래프·플로팅 — **최고 UI 레퍼런스** |
| **Inware** | Android 내 | Material 3 Expressive 미니멀 | 배터리 사이클·쓰로틀 애니메이션 타일 |
| AIDA64 / CPU-Z / Device Info HW | Android 내 | 스펙 조회 | CPU 클럭·배터리·센서 |
| CPU Monitor / 3DMark | Android 내 | 게이지·3D 차트 | 성능 테스트 UX 참고 |

### 1-3. 차별화 후보 (아이디어 단계 — 채택 아님)
1. **타임라인 히스토리** — 온도/드랍/쓰로틀 발생 시점 기록 (GRDB 확장)
2. **플로팅 위젯** — scrcpy 창 옆 오버레이 (TetherLens NSPanel 패턴 이식 가능)
3. **알림 임계값** — 온도 45°↑, 배터리 건강 80%↓ 등 (기존 ConsoleStore.notify 확장)

---

## 2. ADB 수집 가능성 — SM_S901N 실측 (2026-09-23)

### 2-1. 기기 스펙
| 항목 | 값 |
|------|-----|
| 모델 | SM-S901N (Galaxy S22) |
| OS | Android 16 (API 36), One UI 8 |
| SoC | SM8450 Snapdragon 8 Gen 1 (`r0qksx`/`taro`) |
| GPU | Adreno 730, OpenGL ES 3.2 |
| 부트 | verifiedbootstate=`green`, debuggable=0, secure=1 |
| Knox | `knox.kg.state=Completed` (Knox 0 활성 알림 없음) |
| dumpsys 서비스 | **361개** |
| 센서 | **39개** H/W (가속·자이로·자기·밝기·기압·보행 등) |
| 디스플레이 | 1080×2340, density 480 (override 420) |
| CPU | 8코어 (cpu0~7), governor=`walt`, cpu0 cur 1171200 / max 1363200 |
| Wi-Fi | 현재 **disabled** (LTE 사용 중) |
| 통신 | KT, LTE, RSRP -100, level 3 |
| 동시 실행 | **scrcpy 서버 이미 가동** (미러링 공존 전제) |

### 2-2. 수집 가능 지표 표 (카드 후보)

| 카드 | 지표 | adb 명령어 | 파싱 | 권장 주기 | 비고 |
|------|------|-----------|------|-----------|------|
| **기본/기기** | 모델·Android·SDK·부트·Knox | `getprop ro.*` | low | 연결 시 1회 | |
| **배터리** | level·온도·전압·충전 status | `dumpsys battery` | low | 15s | 현재 UI가 `-` 표시 버그 있음 |
| | 건강 Bsoh·ASOC·추정 사이클 | `mSavedBatteryBsoh/Asoc/Usage` | low~med | 1시간 | One UI 6.1.1+ 일부 필드 — 부재 시 "지원안함" |
| | 보호모드·임계치 | `mProtectBatteryMode/Threshold` | low | 30s | 보호모드 카드 핵심 |
| **발열** | Thermal Status 0~6 | `dumpsys thermalservice` | low | 5s | 실측 Status **3** |
| | AP/SKIN/BAT/USB 온도 | `Temperature{mValue,mName}` 정규식 | low~med | 5~10s | AP 53° / SKIN 44.3° / BAT 42.3° 실측 |
| **CPU** | Load 1/5/15 | `/proc/loadavg` | low | 2~5s | 4.49/5.13/4.45 실측 |
| | 전체%/top 프로세스 | `dumpsys cpuinfo` or `top -n 1` | med | 3~5s | |
| | 코어 클럭·governor | `/sys/devices/system/cpu/cpu*/cpufreq/*` | low | 2s | sysfs power_supply는 권한거부, cpufreq는 OK |
| **GPU** | 벤더/렌더러/ES 버전 | `dumpsys SurfaceFlinger \| grep GLES` | low | 연결 시 | Adreno 730 확인 |
| | 점유율/드랍 | `dumpsys gfxinfo` | med/high | 수동 | 무거움 — 상세 OFF 기본 |
| **메모리** | Total/Available/Swap | `/proc/meminfo` | low | 5s | 7394216 kB total, 가용 ~2.8GB 실측 |
| | RSS Top N | `ps -A -o RSS,NAME --sort=-rss` | low | 5~10s | jupjup 697MB 등 실측 |
| | PSS 전체 | `dumpsys meminfo` | med | **3.33s — 상시 폴링 금지** | Broken pipe 주의 |
| **저장소** | 용량/잔량% | `df -h /data` | low | 30~60s | 23G/223G 11% 실측 |
| | 카테고리 점유 | `dumpsys diskstats` | low | 5분 | App/Video/System Size |
| **네트워크** | 통신사/RAT | `dumpsys telephony.registry \| grep mServiceState` (기기内 grep) | med→low | 5~10s | 372KB → 기기内grep으로 ~1KB |
| | 신호 RSRP/level | `... \| grep mSignalStrength` | med→low | 5s | RSRP -100 level 3 실측 |
| | WiFi SSID/RSSI | `cmd wifi status` | low | 5s | WiFi off 시 안내 필요 |
| | RXTX 속도 | `/proc/net/dev` delta | low | 2~5s | |
| **화면/앱** | 켜짐/꺼짐 | `dumpsys power \| grep mWakefulness=` | low | 2~3s | Awake 실측 |
| | 밝기 | `settings get system screen_brightness` | low | 3s | 12, auto mode=1 실측 |
| | 포그라운드 앱 | `dumpsys activity activities \| grep ResumedActivity` | low | 2~3s | jupjup 실측 |
| **센서** | 센서 목록·제조사·속도 | `dumpsys sensorservice` | med | 연결 시/수동 | 39개 확인 |
| | 실시간 값 | sensorservice 스트림 | high | — | 2차 조사 후보 |
| **상태 감시 (기존)** | 설정 변경 (자동회전/화면방향) | SettingWatch (기존) | — | pollInterval | On/Off 없음 |
| | logcat 키워드 | LogcatWatch (기존) | — | 스트림 | 키워드 고정 |
| **전문가 (기본 OFF)** | batterystats·usagestats·netstats·notification | 해당 dumpsys | high | 수동 | 무거움 |

### 2-3. 폴링 원칙 (리서치 확정)
1. **ADB에는 푸시/구독 없음** → 폴링형이 기본, logcat events는 상태 전환 감지용 보조.
2. **무거운 dumpsys 상시 폴링 금지**: `meminfo`(3.3s)·`batterystats`(0.59s/162KB)·`usagestats`(959KB)·`notification`(499KB)·`jobscheduler`(1.5MB)·`package`(7.4MB).
3. **대형 출력은 기기 안에서 grep** 후 수신 (Wi-Fi ADB 필수).
4. **sysfs power_supply는 Permission denied** → dumpsys 우선.
5. **필드 존재 여부 가드**: Bsoh·ASOC·cycle·CoolingDevice 등 기기/OS별 부재 → optional + "지원 안 함".
6. **배터리는 폴링** (logcat `battery_level` 이벤트 버퍼에서 미확인).
7. 단위: temperature ×0.1°C, voltage mV, charge μAh, brightness 0~255 vs float 0~1 주의.

### 2-4. 실측 샘플 (파싱 테스트용 원본 발췌)
```
# dumpsys battery (핵심 라인)
level: 84
voltage: 4143
temperature: 423          # → 42.3°C
status: 4
mProtectBatteryMode: 1
mProtectionThreshold: 80
mSavedBatteryAsoc: [93]
mSavedBatteryUsage: [80739]   # 앞 3자리 → 807 cycle 추정 (비공식)
mSavedBatteryBsoh: 91         # 건강률 %

# dumpsys thermalservice
Thermal Status: 3
Temperature{mValue=53.0, mType=0, mName=AP, mStatus=0}
Temperature{mValue=44.3, mType=3, mName=SKIN, mStatus=3}
Temperature{mValue=42.3, mType=2, mName=BAT, mStatus=0}

# telephony (기기内 grep 대상)
mOperatorAlphaLong=KT, ... LTE ...
CellSignalStrengthLte: rssi=-67 rsrp=-100 rsrq=-13 ... level=3

# meminfo
MemTotal: 7394216 kB
MemAvailable: 2841964 kB

# loadavg
4.49 5.13 4.45 14/4457 3975
```

---

## 3. 기존 Outpost 코드 분석

### 3-1. DroidView 현재 구성
- 기기 카드 (배터리/온도/충전/상태) — **배터리·온도가 `-` 버그**
- 설정 변경 탐지 섹션 (고정 2대상: accelerometer_rotation, user_rotation)
- logcat 워치 섹션 (고정 키워드 2개)
- **감시 On/Off UI 없음, 카드 편집 없음, Toggle 사용 0건 (프로젝트 전체)**

### 3-2. 배터리 `-` 근본 원인 (버그 — P0 후보)
| 주체 | 동작 |
|------|------|
| DroidView | `inventory.devices`에서 `batteryLevel`/`batteryTempC` 읽음 |
| DeviceInventory | `adb devices -l`만 폴링, 배터리는 prev 보존만 (처음 nil) |
| DeviceMonitor | `dumpsys battery` 결과를 **`snapshots[serial]`에만 저장** |

→ `DeviceMonitor.snapshots` → `inventory.devices` **미연결. 합치는 코드 전체에 없음.**

**추가 결함:**
1. 충전 표시: `isCharging == true ? 예 : 아니오` → nil이어도 "아니오" (DroidView.swift:115)
2. `pollOne`의 `catch { return }` — 폴링 실패 무음 (DeviceMonitor.swift:54)
3. 콘솔 열기 버튼 이슈 **Outpost-4ag** (P1, in_progress) — 일시/재현 미확인

### 3-3. On/Off 현황
- DeviceInventory / DeviceMonitor / SettingWatch / LogcatWatch 전부 **사용자 토글 없음**
- SettingWatch에 내부 `@Published running` 골격만 존재
- 알림 대상 하드코딩: `.settingChanged/.batteryAlert/.deviceOffline`만 (ConsoleStore.swift:158-165)
- 설정 저장: `pollInterval`(유일 공유 모니터링 키), `outpost.*` 접두어 마이그레이션 관례

### 3-4. 디자인 시스템 재사용 가능 컴포넌트
| 컴포넌트 | 위치 | 용도 |
|----------|------|------|
| OPPage / OPSection / OPCard | Components.swift | 페이지 골격 |
| OPStatRow | Components.swift:76 | 라벨-값 행 |
| OPCardHeader (StatusDot + trailing) | Components.swift:135 | 카드 헤더 — **On/Off 스위치 trailing 자리** |
| OPBadge / OPEmptyState | Components.swift | 상태·빈상태 |
| StatusDot (.ok/.warn/.bad/.idle) | Theme.swift:194 | 글로우 도트 |
| StatusBarView / SparklineView | StatusViews.swift | **Sites 전용 색** — Droid용 재색상 필요 |
| 배터리 인라인 바 | DroidView.swift:116 | 재사용 컴포넌트 아님 — 분리 후보 |
| **Gauge / Swift Charts** | **없음** | 게이지·차트 신규 필요 |
| OPColor 상태색 | ok/warn/bad + droid 그린 | 3색 히트 함수화 후보 |

### 3-5. 토큰 (DESIGN.md)
- custom 관제탑: abyss/panel/ink, droid 그린 #33D973, ok/warn/bad
- 라이트 대비용 `*For(scheme)` / `*Light` 토큰 체계 존재
- 폰트: SF Rounded 제목 / SF Mono 숫자

---

## 4. TetherLens 패턴 (재사용 조사)

> 위치: `/Users/lee/Documents/Apps/TetherLens` — 핫스팟 테더링 누수 추적 메뉴바 앱
> **주의: Device Care 앱 아님.** 네트워크/CPU/MEM만. 배터리·디스크 미수집.

### 4-1. 메뉴바 UX
```
NSStatusItem + 커스텀 NSView (2줄 3열: ↑↓ 속도 · 속도/할당량/RSSI)
  ├ 좌클릭 → NSPopover (360pt, transient) — 속도·게이지·차트·Top3·프로필
  ├ 우클릭 → NSMenu (15항목 → 팝오버 라우팅)
  └ 별도 Window/NSPanel(플로팅)/Settings TabView 6탭
```

### 4-2. Outpost 이식 가치 패턴
| 패턴 | 내용 | Outpost 적용 |
|------|------|--------------|
| 좌/우클릭 분기 | 팝오버 vs 메뉴 | MenuBarExtra + 우클릭 훅 검토 (필요시 전환) |
| col3 동적 전환 | 상황에 따라 다른 지표 | 메뉴바 표시 지표 선택에 응용 |
| QoSGauge | 배경+전경+비율색+남은량 | 배터리/저장소/메모리 게이지 블록 |
| 3색 히트 함수 | usageRatio/cpuHeat 단일 함수 | 온도·배터리·신호 등급 통일 |
| Top3 랭킹 행 | 아이콘+이름+우측 수치 | CPU/RSS Top 프로세스 |
| 라벨-값 행 (탭=복사) | 좌 96pt 고정 | OPStatRow와 통합 |
| 간략/상세 2모드 | `@AppStorage` | 팝오버 요약↔상세 |
| acquire/release | 팝오버 열림에만 비싼 수집 | DroidMetricsHub 가중 폴링 |
| 슬립/저전력 가드 | willSleep → 전 타이머 정지 | 동일 적용 |
| 타이머 tolerance 10% | 상주 규칙 | 기존도 준수 중 |
| 알림 쿨다운 상태머신 | 임계 Set + 1회 발송 | 발열·건강 알림 |
| Settings 3단계 전파 | Toggle → Manager → NotificationCenter | 카드 On/Off 전파 |
| NSPanel 플로팅 | borderless + 드래그 + 위치 저장 | 킬러기능 후보 (P3) |

### 4-3. TetherLens에 없는 것 (Outpost에서 신규)
- Android 배터리·저장소·발열·센서 수집기 전부 (ADB 기반이라 맥 IOKit 아님)
- Device Care 종합 점수

---

## 5. UI 레퍼런스 & 스타일 방향 (미결정)

### 5-1. 후보 2안
| | A. Inware식 미니멀 | B. DevCheck식 데이터덕후 |
|---|---|---|
| 컨셉 | 큰 게이지 3~4개, 여백, Material 감성 | 사이드바 탭 + 실시간 그래프·코어 게이지·센서 |
| 적합 | 메뉴바/팝오버, 일상 점검 | 콘솔 상세, 하드웨어 탐구 |
| 복잡도 | P1~P2 빠름 | P2~P3 장기 |

### 5-2. 하이브리드 초안 (채택 아님 — 검토 중)
- 메뉴바·팝오버 = A (Inware식 "완벽해요 + 3게이지")
- 콘솔 Droid 상세 = B 점진 (Overview/CPU/Battery 사이드바)
- 기존 StatusBar/Sparkline 재색상 사용, 게이지·히스토리 신규

### 5-3. UX 층위 초안
```
메뉴바 라벨          ← 핵심 1~2 수치 (선택 가능)
  ├ 좌클릭: 팝오버    ← Device Care 요약 + 카드 On/Off + 콘솔 열기
  └ 콘솔 Droid 상세    ← 카드 그리드/탭 + 기존 감시 이벤트
```

팝오버 예시 (미확정):
```
SM_S901N · 완벽
🔋 배터리  84% ████░  보호 80% · 건강 91%
💾 저장소  11% █░░░░  40.7GB/223GB
🧠 메모리  61% ███░░  4.5GB/7.4GB
📶 KT LTE  level 3 · SKIN 44°C
[카드 On/Off] [콘솔 열기]
```

---

## 6. 카드 On/Off 설계 초안 (미확정)

| 카드 | 기본 | 주기 | 비고 |
|------|------|------|------|
| 종합 상태 (완벽/주의/위험 1줄) | ON·고정 | 5s | 점수 규칙 미정 |
| 배터리 | ON | 15s | 버그 수정 선결 |
| 발열 (Thermal+AP/SKIN/BAT) | ON | 5s | |
| 저장소 | ON | 60s | |
| 메모리 | ON | 5s | |
| CPU | ON | 3~5s | |
| 네트워크 (통신사·RSRP) | ON | 5s | |
| 화면/포그라운드 앱 | ON | 3s | |
| 설정 변경 탐지 (기존) | ON | pollInterval | 대상 편집 없음 |
| logcat 워치 (기존) | ON | 스트림 | 키워드 고정 |
| GPU/센서 실시간/전문가 | OFF | 수동 | P3 |

- 저장 키 후보: `outpost.droid.card.<id>` (outpost.* 관례)
- OFF = 수집 중단 + UI 숨김
- 메뉴바 표시 지표 = ON 카드 중 1개 (**값 미정**)

### 아키텍처 초안
```
DeviceInventory (기기 목록)          ← 유지
DroidMetricsHub (신규)              ← 카드별 collector 통합
  ├ Battery/Thermal/Mem/Storage/Cpu/Net/Screen collectors
  ├ SettingWatch / LogcatWatch      ← running 토글 연결
  └ @Published cards                ← UI·메뉴바 공용
HistoryRecorder (GRDB)              ← 타임라인 (P2)
ConsoleStore                        ← 배터리 미연결 수정 포함
```

---

## 7. 선결 버그 & 이슈

| 이슈 | 내용 | bd |
|------|------|-----|
| 배터리/온도 `-` | DeviceMonitor.snapshots ↔ inventory 미연결 + 충전 nil 왜곡 + catch 무음 | 신규 생성 필요 (P0) |
| 콘솔 열기 버튼 | 일시/재현 미확인 | **Outpost-4ag** (P1, in_progress, claimed) |

---

## 8. 단계별 방향 (초안 — 확정 아님)

| 단계 | 내용 | 상태 |
|------|------|------|
| P0 | 배터리 `-` 수정 + 종합·3게이지 콘솔 표시 | 초안 |
| P1 | 카드 On/Off + 팝오버 Device Care 요약 + 메뉴바 지표 | 초안 |
| P2 | 발열·CPU·네트워크·화면 카드 + 타임라인 + 알림 임계 | 초안 |
| P3 | 콘솔 사이드바 탭(DevCheck식) + 센서/GPU + 플로팅 위젯 | 초안 |

---

## 9. 열린 질문 (최종 계획 전 해결 필요)

1. **스타일**: 하이브리드 vs Inware 미니멀 단일 vs DevCheck 데이터덕후 단일?
2. **메뉴바 기본 표시값**: `🔋84%·42°` / `📶KT level3` / 종합점수?
3. **범위**: P0+P1 먼저 출시선인가?
4. **미러링 공존**: scrcpy 동시 구동 사용자 전제 — Outpost 미러링 넣지 않는 기존 정책 유지?
5. **종합 점수 규칙**: 어떤 지표로 완벽/주의/위험을 나눌지 (Thermal Status? 배터리? 가중치?)
6. **감시 이벤트(설정변경·logcat)** 위치: Device Care 카드 아래 별도 섹션 유지?
7. **안드로이드 추가 조사 항목**: 실시간 센서 스트림? GPU 점유율? 알림/블루투스? (사용자 확인 후)
8. **목업 채택 범위**: §11 8카드 전부? 아니면 팝오버용 축약(3~4게이지)+콘솔용 전체?

---

## 10. 관련 파일 인덱스

| 문서/코드 | 경로 |
|-----------|------|
| 본 조사 | `docs/research/RESEARCH_droid_devicecare.md` |
| **iStat 목업 HTML** | `docs/research/Istat-Menus-Android-Dashboard.html` |
| 디자인 토큰 | `docs/DESIGN.md` |
| 프로젝트 규칙 | `AGENTS.local.md` |
| Droid UI | `Sources/Outpost/Views/DroidView.swift` |
| 배터리 버그 | `Sources/Outpost/Droid/DeviceMonitor.swift`, `DeviceInventory.swift` |
| ADB 파싱 | `Sources/Outpost/Droid/AdbClient.swift` |
| 스토어·알림 | `Sources/Outpost/App/ConsoleStore.swift` |
| 메뉴바 진입 | `Sources/Outpost/App/OutpostApp.swift`, `Views/PopoverView.swift` |
| 컴포넌트 | `Sources/Outpost/DesignSystem/Components.swift` |
| TetherLens | `/Users/lee/Documents/Apps/TetherLens` (읽기 전용 참고) |

---

## 11. iStat Menus Android Dashboard 목업 분석

> 원본: `Istat-Menus-Android-Dashboard.html` (Downloads → research 복사)
> 출처 추정: Meta AI / React Artifact (번들 title=`React Artifact`, Google Fonts Inter, Tailwind CDN 파생)
> **성격: 정적 목업 — 하드코더 더미 데이터, 실제 ADB 연동 없음.** UI·정보 구조 레퍼런스로만 사용.

### 11-1. 전체 레이아웃 (스크린샷 + 번들 대조)

```
[맥 메뉴바 시뮬레이션]
  좌: Finder File Edit View Window Help
  우: CPU 24% | MEM 60% | BAT 87% | [배터리아이콘] 87° | NET ◌ | Tue 9:41 AM

[앱 창 — 다크 대시보드]
  헤더: ●●●  P8 | Pixel 8 Pro • adb:192.168.0.12:5555
         Connected • Snapdragon 8 Gen 3
         우측: [● Dumpsys • 47ms] [⌘R Refresh]

  본문: grid 2열 (lg:grid-cols-2), gap-4
    1. CPU          2. GPU
    3. MEMORY       4. BATTERY
    5. NETWORK      6. STORAGE
    7. THERMAL      8. SENSORS

  푸터: ● ADB connected via USB • dumpsys thermalservice • batterystats • meminfo • gfxinfo
        iStat for Android v2.4.1 • 47ms poll • 60fps UI
```

- 폰트: **Inter** (UI) + **ui-monospace/SFMono** 숫자·라벨 (`E` 상수)
- 배경: `#0a0a0b`, 카드: `#242427/90` → hover `#27272b`
- 카드: `rounded-2xl`, 헤더 아이콘: 8×8 그라데이션 chip (`rounded-[9px]`)
- 반응형: `grid-cols-1 → lg:grid-cols-2`, 모바일 헤더 일부 `hidden md:flex`
- 차트: SVG path (Recharts 아님), `gpuGrad` linearGradient 등 3개
- 애니메이션: `pulseDot` keyframes (연결 도트)

### 11-2. 카드 상세 (번들 데이터 원본)

#### ① CPU — 인디고 chip
| 항목 | 목업 값 |
|------|---------|
| 서브 | `Kryo • 8 cores` |
| Pill | `schedutil` (governor), `42°C` (오렌지 경고톤) |
| 코어 행 ×8 | `{id, freq GHz, max GHz, use %}` |
| | C0 2.91/3.0 84% · C1 2.88/3.0 72% · C2 2.74/3.0 61% · C3 1.12/2.4 24% |
| | C4 1.95/2.4 38% · C5 1.88/2.4 31% · C6 1.02/1.8 12% · C7 1.24/1.8 18% |
| 하단 | `LOAD AVG 1.24 0.98 0.87` + 스파크라인 + 우측 `24%` |
| 진행바 | 코어별 게이지 (현재/max 비율 + use% 텍스트) |

#### ② GPU — 틸 chip
| 항목 | 목업 값 |
|------|---------|
| 서브 | `Adreno 750 • OpenGL ES 3.2` |
| Pill | `670 MHz` |
| 게이지 | **링 34% UTIL** (중앙 큰 숫자) |
| 타일 | `FREQUENCY 670MHz` / `VULKAN 1.3.2` |
| 차트 | 미니 area + `12 samples / sec` |
| 캡션 | `Renderer: Adreno (TM) 750 • Driver 615.50 • 2 active contexts` |

#### ③ MEMORY — 퍼플 chip
| 항목 | 목업 값 |
|------|---------|
| 서브 | `12 GB LPDDR5X • 8533 MT/s` (우측 `7.2/12GB`) |
| 바 | 그라데이션 full-width (fuchsia→violet→indigo) + amber 구간 = 압력 |
| 하단 | `PRESSURE • moderate` / `SWAP 1.2 GB • ZRAM 2.8 GB` |
| Top RSS ×4 | gms 842MB 62% · system_server 521MB 38% · chrome 412MB 30% · surfaceflinger 298MB 22% |
| | 행: 이름 + 미니 바 + `w-56 right` 용량 |

#### ④ BATTERY — 앰버 chip
| 항목 | 목업 값 |
|------|---------|
| 서브 | `USB-C PD • 27W • Optimizing` |
| 헤더 우 | 배터리 아이콘 + `87%` |
| **6타일 (3×2)** | `HEALTH 94% Good` · `TEMP 33.2°C Normal` · `VOLTAGE 4.12V (4.40 max)` |
| | `CYCLES 127 (94% cap)` · `CURRENT 1.42A Charging` · `TYPE Li-Po 5050mAh` |
| 하단 | `Charge history 6h` area 차트(amber) + `0.82× full cycles today • est 1d 4h left` |

#### ⑤ NETWORK — 스카이 chip
| 항목 | 목업 값 |
|------|---------|
| 서브 | `Wi-Fi 5GHz • -42 dBm • 192.168.0.12` |
| Pill | `802.11ax • 1200Mbps` |
| 차트 | UP/DOWN 이중 area 웨이브 (indigo/cyan 계열) |
| 수치 | `UP 2.4 MB/s` · `DOWN 5.8 MB/s` (각각 컬러 도트 pill) |
| 하단 | `IPv4 192.168.0.12/24` • `IPv6 fe80::a8d1…` • `SSID PixelLab_5G` |

#### ⑥ STORAGE — 짙은 칩
| 항목 | 목업 값 |
|------|---------|
| 서브 | `UFS 4.0 • 128GB • f2fs` (우측 `81/128GB`) |
| 차트 | **세로 히스토그램** (디스크 I/O 틱) |
| 2×타일 | `READ 412 MB/s` + 스파크라인 / `WRITE 286 MB/s` + 스파크라인 |
| Pill | `/data 63% • 81GB` · `/system 11.2GB RO` |

#### ⑦ THERMAL — 레드 chip
| 항목 | 목업 값 |
|------|---------|
| 서브 | `thermalservice • 8 zones` |
| Pill | `No throttling • 37°C avg` (emerald — 정상) |
| 존 목록 (하드코딩 8개) | `cpu0-3 42.1°C` green · `cpu4-7 38.4°C` green · `gpu 44.8°C` **yellow** · `battery 33.2°C` green |
| | `skin 35.6°C` · `modem 46.2°C` **yellow** · `charge-ic 39.1°C` · `npu 36.8°C` |
| 행 구조 | 도트(그린/앰버 글로우) + 존명 + 미니 바 + 온도 |

#### ⑧ SENSORS — 시안 chip
| 항목 | 목업 값 |
|------|---------|
| 서브 | `9-axis • 200Hz` |
| Pill | `LIVE` |
| 시각 | 126px 라이더/그리드 + 중앙 점 (pulseDot 애니) |
| 번들 텍스트 | `X: 0.21g Y: -0.08g Z: 9.81g` · `GYRO 0.02 rad/s` · `MAG 42.1 µT` · `LIGHT 128 lx` |

### 11-3. 메뉴바 라벨 (목업 예시)
```
CPU 24%   MEM 60%   BAT 87%   [ batt ] 87°   NET ◌   Tue 9:41 AM
```
- 아이콘 글리프: `◫` `◍` 등 텍스트 심볼 (SF Symbols 아님)
- 온도는 **배터리 온도로 보임** (87°는 °C 오타/포맷 임계 검토 — 실제는 `87%`와 `87°` 병기)

### 11-4. 디자인 토큰 (목업 → Outpost 매핑)

| 목업 | 값 | Outpost 대응 |
|------|-----|--------------|
| 배경 | `#0a0a0b` | abyss `#0D1220` (유사 다크) |
| 카드 | `#242427` / hover `#27272b` | panel `#171E31` / panelHi `#212945` |
| 본문 텍스트 | white/90 → /25 | ink → inkDim 계열 |
| 성공 | emerald-400 `#34d399` | ok `#33D973` (droid) |
| 경고 | amber-400 `#fbbf24` | warn (jobs 앰버) |
| 위험/red chip | red-500/20 | bad `#FF4D52` |
| CPU chip | indigo/violet | **신규 or droid 액센트 재조정** |
| GPU chip | teal/emerald | 구분 필요 |
| Battery chip | amber/orange | jobs 액센트와 혼동 주의 |
| Network chip | sky/blue | sites `#4D99FF` |
| Sensor chip | cyan | notify와 구분 |
| 숫자 폰트 | SF Mono 계열 | `OPFont.number` 일치 ✅ |
| 제목 | Inter semibold | OPFont.title (SF Rounded) — **차이** |
| Pill | white/6 bg + border, 10px | OPBadge 계열로 통일 가능 |
| 카드 헤더 | 8×8 그라데이션 아이콘 + 12px title + 10px sub | OPCardHeader + 신규 icon chip |
| 코너 | card 12~16px, pill full, 타일 10px | OPSpace.radius 12 유지 |

### 11-5. 목업 ↔ SM_S901N 실측 매핑 (수행 가능성)

| 목업 필드 | ADB 출처 | SM_S901N 실측 | 난이도 |
|-----------|----------|---------------|--------|
| 코어 freq/max/use% | `cpufreq` + `/proc/stat` delta | clkr는 OK, **use%는 delta 계산 필요** | med |
| governor | `scaling_governor` | `walt` (schedutil 아님 — 기기 다름) | low |
| Load 3값 | `/proc/loadavg` | 4.49 5.13 4.45 ✅ | low |
| CPU 온도 pill | thermalservice AP | 53°C ✅ | low |
| GPU 모델/ES | SurfaceFlinger GLES | Adreno 730 ✅ (목업은 750) | low |
| GPU 클럭/UTIL/Vulkan | kgsl sysfs·dumpsys | **부분 (gpuclk denied 일부)** | med~high |
| Mem total/used | meminfo | 7394216 / 사용중 ✅ | low |
| Pressure·ZRAM | meminfo Swap* | SwapTotal 존재 ✅ | low |
| Top RSS | `ps -o RSS` | jupjup 697MB 등 ✅ | low |
| LPDDR·MT/s | getprop/hw | 미확인 — 보조/생략 가능 | med |
| BAT level | dumpsys battery | 84% ✅ | low |
| BAT temp | temperature ÷10 | 42.3°C ✅ | low |
| Voltage | voltage | 4143 mV ✅ | low |
| Current A | current now | μA → A 변환 ✅ | low |
| Health % | **Bsoh 91** (삼성) | 91% ✅ (목업 94와 유사 층) | low |
| Cycles | Usage 앞자리 추정 | 807 (비공식) / cycle_count 0 | **med·불확실** |
| Type·mAh | technology·cc | Li-ion, μAh ✅ partial | low |
| Charge history | 충이력 샘플링 | GRDB 타임라인 신규 | med (P2) |
| Wi-Fi SSID/RSSI | cmd wifi | **Wi-Fi off** → LTE 대체 카드 필요 | low |
| UP/DOWN MB/s | `/proc/net/dev` delta | ✅ | low |
| IPv4/IPv6 | `ip addr`/connectivity | ✅ | low |
| Storage used | df /data | 11% 실측 ✅ | low |
| READ/WRITE MB/s | diskstats·delta | 부분·주기 한정 | med |
| Thermal zones ×8 | thermalservice | **AP/BAT/SKIN/USB 등 실측 — 목업 zone명( modem/npu)은 기기별 다름** | low~med |
| No throttling/avg | Thermal Status 0~6 | **Status 3 = 주의 존재** (목업 "No throttling"과 다름 — 상태 문구 체계 필요) | low |
| Sensors LIVE xyz | sensorservice | 목록 39개 ✅ / 실시간 스트림 별도 | med~high |
| `47ms poll` | — | 목업 푸터 — Outpost엔 실제 poll 로그 표시 가능 | low |
| 메뉴바 CPU/MEM/BAT/°/NET | 위 전체 종합 | 메뉴바 라벨 = ON 카드 요약 | 구현 주제 |

### 11-6. Outpost 적용 시 차이·주의

1. **기기는 Pixel 8 Pro 더미** — 실기기 SM_S901N은 Adreno 730·walt·LTE·Bsoh 필드로 카피 문구 달라짐.
2. **Wi-Fi 목업 vs 실측 LTE off** — Network 카드는 Wi-Fi/LTE 듀얼 모드 필요.
3. **Thermal "No throttling"** — Thermal Status ≥2부터 경고 문구 분기 (우리 기기 Status 3).
4. **전류·사이클·mAh·GPU util·디스크 R/W·센서 실시간** — 100% 달성 보장 없음 → optional·"—" 폴백.
5. **메뉴바 5항목(CPU/MEM/BAT/온도/NET)** — TetherLens식 다중 컬럼 OR 사용자 선택 1~2값 (Outpost는 MenuBarExtra 단순 라벨 유지 가능).
6. **미러링/제어 없음** — 순수 상태 대시보드 (기존 정책 유지 시 scrcpy 공존).
7. **스티일 판정 신호** — 본 목업 = **데이터덕후(DevCheck계) 2열 풀카드**. 팝오버 340pt에는 축약본 별도 필요.
8. **콘솔 vs 팝오버 정보량 분리** — 8카드 전체는 콘솔 전용, 팝오버는 상단 3~4 요약이 타당.

### 11-7. 목업에서 바로 가져갈 수 있는 구조 체크리스트

- [x] 맥 메뉴바 상단 지표 리더블 표시 (CPU/MEM/BAT/온도/NET)
- [x] 기기 헤더: 모델 + adb 주소 + 연결 도트 + SoC + poll 배지 + 새로고침
- [x] 8카드 2열 그리드 + 카드별 액센트 아이콘 chip
- [x] 코어별 freq 게이지 행 + Load 스파크라인
- [x] 배터리 6타일(HEALTH/TEMP/VOLTAGE/CYCLES/CURRENT/TYPE) + 충이력 차트
- [x] 메모리 그라데이션 바 + PRESSURE + Top RSS
- [x] 네트워크 UP/DOWN area + SSID/IP pill
- [x] 스토리지 히스토그램 + R/W 타일 + 마운트 pill
- [x] 서멀 존 리스트(도트+미니바) + throttling 배지
- [x] 센서 LIVE 패널
- [x] 푸터: 수집 명령어 노출 + 버전 + poll 주기

### 11-8. 목업에 없는 것 (Outpost 고유 유지)

- 설정 변경 탐정 / logcat 워치 이벤트 (외부 조작 감시)
- Sites·Jobs·Notify 연동 (사이트/하트비트/ntfy)
- Apple 모듈
- 게이트 온보딩, 다국어, 테마 3종
- GRDB 이력/타임라인 (목업은 정적 sparkline)

---

## 12. 목업 분석 후 열린 질문 추가

9. **메뉴바**: 목업 5항목 전체 vs 선택 1~2값 vs 현재 StatusDot+title 유지 중 무엇?
10. **Network 카드**: Wi-Fi 대신 LTE(RSRP·통신사) 기본? Wi-Fi off 시 안내?
11. **Battery 6타일**: HEALTH·CYCLES(불확실) 표시 정책 — 실측값 vs “지원 안 함”?
12. **GPU 카드**: SM_S901N에서 util/클럭 제한이 있음 — 카드 축소(모델+ES버전만) or 제외?

---

## 13. 이관 색인

- 2026-09-23: 본 문서 + 목업 2종 + Skill Pack을 **RelayConsole** 프로젝트로 복사 이관.
- 최종 계획: `RelayConsole/docs/plans/PLAN_v0.1_relayconsole.md`
- 원본 Outpost 레포는 문서 보존용으로 유지.
