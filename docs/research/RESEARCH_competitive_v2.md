# Relay Console 경쟁 앱 조사 · 비교 보고서 (v2)

> 조사일: **2026-10-17** · 모드: deep(병렬 수집 + 교차검증) · 출처: 57건 (모두 URL 명시)
> 대상 제품: **Relay Console 1.16.0** (macOS 26+ 메뉴바 상주 안드로이드·Apple 기기 관제탑)
> 이전 문서: 이 저장소 `docs/research/RESEARCH_competitive_v1.md` (2026-09-24) — 본 보고서가 **KDE Connect 축과 Windows 축을 신규로 추가**하고, Sites/Jobs 삭제 이후 포지션을 재정의한다.
> 미검증 항목은 본문에 **미검증**으로 표시했고 §6에 모아 두었다.
> 동반 문서: `docs/research/RESEARCH_windows_equivalents.md` (Windows 진영 심화 조사 — §F2·F3의 원자료)
> 배포본: `~/Documents/RelayConsole_Competitor_Research_20261017/` (같은 내용의 HTML·PDF)
> 재검증: 2026-10-17 `gh api`(PAT 인증 · 시간당 5,000회)로 저장소 **44개 전수 재확인** → **부록 B** (1차 조사가 과소평가한 경쟁자 2건·과대평가한 도구 4건 정정)

---

## 요약 (Executive Summary)

안드로이드 기기를 데스크톱에서 다루는 앱은 크게 네 무리로 나뉜다. **폰 통합 브리지**(KDE Connect, Microsoft Phone Link, Sefirah, CoveLink, MyPhoneExplorer), **미러링·제어 도구**(scrcpy와 그 GUI 래퍼, Vysor, AirDroid, 상용 미러링 스위트), **ADB 유틸·팜**(ADB AppControl, DeviceFarmer STF, adb-tui, Droidective), **폰측 도구**(PCAPdroid, NetGuard, DevCheck, Firebase Crashlytics)이다. 이 중 **지속 감시(텔레메트리 추이 + 임계 알림)** 를 하는 것은 기업용 MDM(AirDroid Business, Samsung Knox Asset Intelligence, Esper)뿐이며, 그것들은 전부 클라우드·계정·기기 등록을 요구한다 [20][21][54][55].

**KDE Connect는 사용자가 요청한 비교 대상이며, Relay Console과 목적이 겹치지 않는다.** 플러그인 32종(데스크톱)·24종(안드로이드)으로 알림 미러링, 클립보드, SMS, 원격 입력, 파일 전송, 가상 모니터까지 제공하지만, 폰의 CPU·발열·메모리·앱별 트래픽을 수집하지 않고 임계 알림도 없다 [2][3][4]. 같은 LAN이 필수이며 데스크톱·폰 양쪽에 앱 설치가 필요하다 [5][6]. 즉 **"폰을 편하게 쓰는 도구"이지 "폰을 지키는 도구"가 아니다.**

**Windows에는 트레이 상주형 다기기 안드로이드 텔레메트리 콘솔 + 임계 알림 앱이 존재하지 않는다.** 조사에서 확인된 트레이 상주 앱은 배터리 %만 보여주거나(BatteryBoi), 알림·통화만 동기화하거나(ADB Device Manager), 미러링 런처에 그친다(AndroLaunch). 개별 요소(스파크라인·앱별 트래픽·MCP·경보 게이트)는 오픈소스에 흩어져 있으나 **결합한 제품은 없다** [33][34][32][29].

Relay Console의 차별점은 **폰에 앱을 설치하지 않고(adb만) 다기기 텔레메트리 + 18종 감시 + 하나의 알림 폭(시스템·ntfy·Slack)** 을 서버 없이 제공한다는 점이다. 특히 **앱별 네트워크 귀속과 `adb(내부)` 트래픽 분리**는 조사한 어떤 제품에도 없다. 반대로 **알림 미러링·SMS·클립보드·폰 찾기·무선 페어링 편의**는 KDE Connect 계열이 앞선다. 권고는 §5에 정리했고, 최우선 3건은 ① Android 11+ 무선 디버깅 **QR 페어링**(재부팅 내구성) ② **폰 찾기·벨 등 즉시 조치 세트** ③ **scrcpy 옵션 노출 확대**다.

---

## 1. 서론

### 1.1 질문

사용자가 던진 질문은 네 갈래였다. (1) 이 앱과 비슷한 일을 하는 앱이 인터넷에 있는가, (2) 깃헙에도 있는가, (3) **윈도우 앱이 있는가**, (4) KDE Connect를 포함해 비교하고 우리 앱에 필요한 기능을 찾아라.

### 1.2 범위와 방법

조사를 4개 축으로 분해하고 병렬로 수집했다. ① KDE Connect 제품군(데스크톱·안드로이드·iOS·GSConnect·Valent), ② Windows 진영(폰 통합 브리지 + 미러링 도구 + ADB 유틸), ③ GitHub 오픈소스 지형(저장소 API로 별 수·최근 푸시·라이선스·아카이브 여부), ④ 폰측 도구(앱별 트래픽·텔레메트리·크래시/ANR·무선 디버깅). 이후 핵심 수치를 교차검증했고(예: `shrimqy/Sefirah` 별 3,024 · GPL-3.0 · 최근 푸시 2026-10-17 · C# [25]), 검증하지 못한 값은 **미검증**으로 남겼다.

### 1.3 전제

비교 기준은 **Relay Console 1.16.0**의 현재 기능이다. 저장소 README와 소스 기준으로: 메뉴바 상주·배지, 팝오버(브리핑·발열 배너·권장 조치), 위젯 3종, 안드로이드 8카드(CPU·GPU·MEM·SENSORS·BATTERY·NETWORK·THERMAL·STORAGE) + 5분 스파크라인, 감시 18종(hysteresis·쿨다운), Alerts 3탭 + ack/mute/note, 외부 채널 ntfy·Slack, scrcpy 원클릭 미러링, 파일 탐색기, logcat 뷰어, 프로세스 목록, 앱 네트워크 허브, 인시던트 번들(ANR·크래시), Health Score, 로컬 MCP 서버(읽기 전용), 플러그인 SDK, Apple Phase1(libimobiledevice Trust). **Sites·Jobs(사이트·작업 감시)는 2026-10-05 제거**되어 포지션이 "기기 관제탑"으로 좁혀졌다 [자체].

### 1.4 용어

"관제"는 이 보고서에서 **지속 수집 + 추이 보존 + 임계 판정 + 알림 전달**을 모두 하는 것을 뜻한다. 단순히 화면을 보여주는 뷰어, 일회성 덤프 도구, 조작용 미러링은 관제가 아니다. 이 구분이 결론의 핵심이다.

---

## 2. 조사 결과

### F1. KDE Connect — 가장 성숙한 "폰↔데스크톱 통합"이지만, 관제 기능은 없다

KDE Connect는 KDE 커뮤니티가 만든 **LAN 기반 기기 간 통신 앱 + 플러그인 플랫폼**이다. 최신 데스크톱 릴리스는 26.08.2(2026-10-08)이고 저장소는 GitHub 미러 기준 별 4,061로 최근 푸시가 조사일(2026-10-17) 당일이다 [1][7]. 프로토콜은 버전 8이며 UDP 1716 브로드캐스트와 mDNS(`_kdeconnect._udp`)로 같은 서브넷의 기기를 찾는다 [4].

기능의 폭이 압도적이다. 데스크톱 쪽 플러그인 디렉터리에 **32개**, 안드로이드 쪽에 **24개** 플러그인이 있으며 [2][3], 사용자가 체감하는 대표 기능은 알림 동기화(폰 알림을 데스크톱에서 읽고 답장), 클립보드 양방향(텍스트만, 이미지 제외), 파일/URL/텍스트 송수신, SFTP로 폰 저장소 탐색, 원격 입력(폰을 트랙패드·키보드로), 프레젠테이션 리모컨, MPRIS 미디어 제어, SMS 읽기·전송, 연락처 단방향 동기화, 폰 찾기(벨), 핑, 배터리 %, 연결 상태 보고(신호 세기·망 유형), 원격 명령 실행, 원격 잠금, 화면보호기 억제, 통화 시 미디어 일시정지, 입력장치 공유(시너지류, 2024 MR), 드로잉 태블릿, 가상 모니터(다른 기기를 외부 디스플레이로)다 [2][5][13][14]. 안드로이드 앱은 1.36.0(2026-10-15, F-Droid)으로 여전히 활발하다 [8].

플랫폼 도달 범위도 넓다. 데스크톱은 리눅스·Windows·macOS를 지원하고, Windows는 Microsoft Store/Chocolatey/.exe로 배포되며 **트레이 아이콘으로 상주**한다 [6]. macOS는 정식 배포 페이지와 `brew install --cask kde-connect`, 나이틀리 DMG(ARM/Intel)를 안내하지만, 커뮤니티 위키는 C++ 데스크톱 빌드에 대해 "공식 릴리스가 아직 없다"고 적어 **문서 간 불일치**가 있다 [6][12]. 다만 App Store의 iOS 앱이 macOS 13+에서도 동작하도록 표기되어 있어 [9], macOS 사용자는 "폰측 앱과 같은 앱"을 데스크톱에서 쓸 수 있다. GSConnect는 KDE Connect 프로토콜의 GNOME 독립 구현으로 별 3,744 · v73(2026-09-23)이며 **리눅스 전용**이다 [10][56].

결정적인 한계는 **관제 부재**다. 프로토콜이 정의하는 기기 상태 패킷은 `battery`와 `connectivity_report`뿐이며 [4], CPU·발열·메모리·앱별 트래픽·PSI·스로틀링을 수집하는 플러그인은 데스크톱 32종·안드로이드 24종 목록 어디에도 없다 [2][3]. 크래시/ANR 수집, 시계열 보존, 임계 기반 알림도 없다 [5]. 또한 **인터넷을 넘지 못한다** — 공식 문서와 커뮤니티 답변이 "같은 네트워크에 있어야 한다"고 명시하고, NAT 너머는 WireGuard·ZeroTier·Tailscale 같은 오버레이가 필요하다 [5][6]. 폰측 앱 설치가 필수라는 점도 Relay Console과 반대 지점이다. 2025년에는 인증 우회 취약점 **CVE-2025-66270**(Critical, 2025-11-28 공개)이 나와 데스크톱 25.12, 안드로이드 1.34.4, iOS 0.5.4 이상으로 업데이트가 요구됐다 [11].

**결론**: KDE Connect는 Relay Console의 **대체재가 아니라 보완재**다. 같은 맥에서 둘을 함께 쓰면(알림·클립보드·SMS는 KDE Connect, 텔레메트리·감시·알림 폭은 Relay Console) 사용자 경험이 가장 좋아진다. macOS 사용자에게는 이 조합이 실질적인 최선이다.

### F2. Windows 진영 ① — "폰 통합 브리지"는 성숙했고, Relay Console과는 다른 일을 한다

Windows에서 폰과 PC를 잇는 대표 제품군을 정리하면 표 1과 같다. 이 무리의 공통점은 **알림·문자·통화·파일**이라는 "생활 통합"에 집중하고, **기기 건강 감시는 하지 않는다**는 것이다.

**표 1. Windows 폰 통합 브리지**

| 제품 | 플랫폼 | 가격 | 핵심 기능 | 감시/알림 | 출처 |
|---|---|---|---|---|---|
| Microsoft Phone Link | Win 10/11 | 무료 | 알림·SMS·통화·사진·파일·미디어, 선별 기기만 앱 스트리밍, 배터리%/BT/Wi-Fi 상태 | 없음(CPU·발열·앱별 트래픽·logcat 없음) | [15][16] |
| Intel Unison | Win | **EOL 2026-01-01** | (과거) 파일·문자·통화·화면 확장 | 서비스 종료 | [17] |
| **Sefirah** (오픈소스) | Win(+리눅스 초기) | 무료 GPL-3.0 | 알림 미러링·답장, SMS, 통화, 클립보드(모든 폰), 파일, scrcpy 기반 미러링, PC 원격 전원 | 없음 | [25][27] |
| CoveLink | Win/macOS/리눅스 | 리눅스 무료·Win/macOS $39 1회 | 다중 폰 알림·문자·통화·미디어·클립보드·파일, NaCl E2E, QR 페어링 | 없음 | [26] |
| MyPhoneExplorer | **Win 전용** + 폰 앱 | 프리웨어 | SMS·연락처·일정 동기화, 파일/백업, 앱 관리, 화면 제어, Bluetooth/Wi-Fi/USB, 완전 로컬 | 없음 | [18] |
| AirDroid Personal | Win/macOS/웹 | 유료 구독(가격 미검증) | 파일·원격 제어·알림·SMS·카메라·미러링 | 없음(클라우드 경유) | [20] |
| Samsung Flow / DeX for PC / SideSync | Win | 무료 | 알림·문자·파일·미러링 | 없음, **제품군 정리됨** | [19][57] |

주목할 것은 **Sefirah**다. Microsoft 계정과 기기 브랜드 제약 없이 동작하는 Phone Link 대안으로, 알림·클립보드를 모든 안드로이드 기기에서 지원하며 scrcpy로 화면 미러링까지 붙였다. 별 3,024(C#, GPL-3.0)로 2026-10-17에도 커밋이 올라오는 활발한 프로젝트이고 [25], 안드로이드 앱(Sefirah-Android, Kotlin)은 별 988이다 [25]. 미디어 리뷰들도 "Phone Link를 대체한다"고 평가한다 [27]. 그럼에도 **Sefirah 역시 텔레메트리·추이·임계 알림이 없다** — 알림과 파일을 옮기는 도구다.

Samsung 쪽은 오히려 축소됐다. Samsung Flow는 Windows 11에서 동작하지 않고 [57], DeX for PC는 One UI 7 이상으로 출시·업데이트된 기기에서 지원되지 않으며, DeX for Mac은 2022년 1월 종료됐다 [19]. 삼성은 대안으로 Link to Windows(Phone Link)를 안내한다 [19]. 이 공백을 Sefirah·KDE Connect·Phone Link가 나눠 갖는 구도다.

AirDroid는 Personal과 Business의 성격이 완전히 다르다. Personal은 브리지·원격 제어 도구지만, **Business는 배터리 온도·용량·스토리지·데이터 사용량·앱별 셀룰러 사용량까지 알림 트리거로 제공**한다 [21]. 즉 "기기 텔레메트리 + 임계 알림"을 상용으로 이미 파는 유일한 사례다. 다만 클라우드 콘솔, 계정, 폰의 Biz Daemon 설치, 기기당 과금이 전제이고 [20][21], CPU·스로틀·PSI·ANR 감시, logcat, 프로세스, 인시던트 번들은 없다. Relay Console의 "설치 0·서버 0"과는 정면으로 충돌하지 않는다.

### F3. Windows 진영 ② — 미러링·제어 도구는 넘치고, 감시 도구는 없다

미러링 계열은 scrcpy가 사실상 표준이다. scrcpy 5.x는 오디오 포워딩(Android 11+), 카메라 미러링(Android 12+), 가상 디스플레이, 화면 끈 채 미러링, 양방향 클립보드, OTG 모드, 게임패드, V4L2 웹캠 출력까지 지원하고 별 15만을 넘겼다 [24]. GUI 래퍼 생태계도 두껍다 — QtScrcpy(별 32,445, 다중 기기 그룹 제어·키맵) [23], escrcpy(별 12,094, Electron), scrcpy-gui(SimonAKing, 별 4,131), Scrcpy-GUI(Flutter, 별 1,7xx대), kil0bit-kb/scrcpy-gui(별 1,416), 그 밖에 scrcpy buddy·simonaking 등이며, guiscrcpy(별 3,053)는 **아카이브(2023-12 이후 중단)** 됐다 [41][42]. 상용은 Vysor(Pro $2.50/월·$40 라이프타임, Pro에서 프로세스·ADB 로그 조회) [22], AirDroid, ApowerMirror, MirrorGo, Total Control, Mobizen, LetsView, TeamViewer 조합 등이 있다.

**이 무리는 전부 "조작" 지향이라 관제가 없다.** 우리 앱이 이미 제공하는 감시·알림·추이·인시던트 기능은 어느 제품에도 없다. 반대로 미러링 품질·옵션 폭(오디오·카메라·가상 디스플레이·그룹 제어)은 이들이 앞선다([표 2]).

**표 2. 미러링·제어 계열의 관제 기능 유무**

| 제품 | 미러링·제어 | 오디오/카메라 | 다중 기기 | 텔레메트리 추이 | 임계 알림 |
|---|---|---|---|---|---|
| scrcpy 5.x [24] | O | O(11+/12+) | 창 여러 개 | X | X |
| QtScrcpy [23] | O | 부분 | **O(그룹 제어)** | X | X |
| escrcpy / scrcpy-gui 계열 | O | O | O | X | X |
| Vysor Pro [22] | O | 부분 | 부분 | X(프로세스·ADB 로그만) | X |
| AirDroid Business [21] | O | O | O | **O** | **O**(클라우드·유료) |
| **Relay Console** [자체] | O(scrcpy 위임) | 부분 | 감시만 | **O(8카드·5분 추이)** | **O(18종)** |

### F3.1 질문에 대한 명시적 답: Windows에 트레이 상주형 다기기 텔레메트리 콘솔 + 알림 앱은 없다

조사에서 확인된 Windows 트레이/태스크바 상주 후보는 모두 요건에 미달했다. BatteryBoi는 트레이에 **안드로이드 배터리 %만** 표시하고, Shrey113의 ADB Device Manager는 트레이 상주 + 알림·통화 동기화이지만 **텔레메트리가 없으며**, AndroLaunch는 메뉴바형 ADB/scrcpy 런처에 불과하다. 반대로 텔레메트리가 있는 JankMark(CPU/GPU/배터리 온도 개별 차트) [34], holo(CPU·메모리·디스크·네트워크 스파크라인 + logcat + 세션 이력) [33], DroidGauge(발열·앱별 네트워크 + HTML 리포트 + CI 회귀 게이트) [32], adb-tui(성능 뷰 + MCP 서버) [29], Adb-DECK(실시간 CPU/메모리 그래프 + 알림 인스펙터) [35], ADB AppControl(앱 관리·logcat·기기 정보) [36]는 **트레이 상주가 아니고 임계 알림도 없다**.

즉 요소는 다 있는데 결합이 없다. "트레이 상주 + 다중 기기 + 심층 텔레메트리 + 임계 알림 + 로컬 전용"을 한 앱에서 제공하는 Windows 제품은 **발견되지 않았다**. 이 결론은 스크린샷·웹 검색을 포함한 10개 이상 질의를 시도한 결과이며 [조사 방법 §8], Binaries 검색으로는 트레이+ntfy 패턴이 주변기기 배터리 감시(예: Bluetooth 기기 배터리 트레이 + ntfy 푸시)에만 존재함을 확인했다 — 즉 **패턴 자체는 사용자에게 익숙하지만 안드로이드 기기에 적용한 제품은 없다.**

**규모 정정(재검증)**: 이 절에서 거론한 도구 상당수는 취미 규모다 — `alanisme/adb-tui` **20★**(2026-03-11 이후 커밋 없음) · `AbiMangalan/JankMark` **1★** · `RuizheGu0/droidgauge` **8★** · `yuhnin-m/Adb-DECK` **25★** · `measure-sh/holo` **92★**. 1차 조사는 adb-tui(MCP 내장)를 "주목할 도구"로 다뤘지만 실제 위상은 작다. 반대로 Windows ADB 관리 도구 중 가장 큰 것은 `Shrey113/Adb-Device-Manager-2` **634★**(트레이 상주 + 알림·통화 동기화, 텔레메트리 없음)이다.

### F4. macOS·ADB 유틸 지형 — 같은 폼팩터는 실제로 있고, 둘은 무시할 수 없다

Relay Console과 **같은 폼팩터**(맥 메뉴바 또는 네이티브 앱 + ADB)는 실제로 존재하며, 재검증 결과 그중 둘은 무시할 수 없는 규모다(2026-10-17 `gh api` 실측).

| 프로젝트 | 별 | 최근 푸시 | 라이선스 | 성격 | 관제 |
|---|---|---|---|---|---|
| **aman-senpai/AndroLaunch** | **88** | 2026-10-02 | AGPL-3.0 | macOS 메뉴바(현재 Win/Linux 확장) · ADB+scrcpy · **QR 무선 페어링** · 양방향 클립보드 · Wi-Fi/BT/DND/회전 토글 · 볼륨·밝기 · 앱 설치/제거/데이터 삭제 · ADB 셸 | X |
| **Droidective/Droidective** | **62** | **2026-10-17** | MIT | 네이티브 macOS(Swift 6·SwiftUI) 커맨드 팔레트 · **61종 툴** · PTY 터미널 · 파일·앱 탐색기 · **크래시 브라우저(ANR 포함)** · **라이브 성능 차트** · 6대 미러 월 · **MCP 서버** · 메뉴바 상주 | X(경보·채널 없음) |
| Zaphkiel-Ivanovna/adb-studio | 25 | 2026-10-05 | MIT | 네이티브 macOS ADB 관리 GUI | X |
| yuhnin-m/Adb-DECK | 25 | 2026-03-27 | 없음 | 데스크톱 ADB UI(기기·앱·로그) + 모니터 패널 | X |
| Bloby22/andtls | 4 | 2026-08-30 | MIT | Go TUI, 기기별 배터리·RAM·CPU·온도 + scrcpy | X |
| WhileEndless/AndroidDeviceManager | 3 | 2025-07-27 | AGPL-3.0 | macOS 메뉴바 ADB(스크린샷·클립보드·셸·포트포워딩·Frida·파일/앱 관리·로그뷰어) | X |
| samkit/droid-scout | 3 | 2026-06-12 | Apache-2.0 | macOS 메뉴바 + logcat 스트림 파일 기록 | X |
| ztcxzc/adb-device-monitor | 0 | 2026-08-11 | 없음 | Electron, 27개 실시간 메트릭(배터리·RAM·CPU 온도·RSSI·RX/TX) + 미러링 + 파일브라우저 | X(알림 없음) |
| **DeviceFarmer/stf** | 4,605 | 2026-10-02 | NOASSERTION | 브라우저 기기 팜(인벤토리·배터리/헬스 추적·예약·REST API) | 일부(대시보드만, 경보 없음) |
| **Relay Console** [자체] | — | — | — | 메뉴바 관제탑 | **O** |

**정정 1 — Droidective**: 1차 조사는 "61종 툴 + 메뉴바"로만 적고 별 수를 비워 두었다. 재검증 결과 **우리와 같은 스택(Swift 6·SwiftUI)으로 오늘도 커밋되는 62★ 프로젝트**이며, 기능이 상당히 겹친다. `DeviceMonitor`(2초 폴 주기)로 기기를 감시하고, **크래시 브라우저**(Java·네이티브·RN·ANR을 필터 목록 + watch 모드 + Slack/Jira용 포맷팅), **라이브 성능 차트**(코어별 CPU·RAM·FPS·네트워크·프로세스별, 기록·JSON/CSV 내보내기), **메뉴바 상주**, **MCP 서버**, 6대 동시 미러 월, bugreport zip까지 갖췄다. v3.11.0으로 서명·공증·Sparkle 자동 업데이트되고, **Windows/Linux 베타가 같은 `main`에서 나온다**(32개 뷰 중 29개 포팅).

**정정 2 — AndroLaunch**: macOS 메뉴바 앱이면서 <b>QR 무선 페어링을 이미 구현</b>했고, 양방향 클립보드·빠른 토글·앱 관리·셸을 제공한다. 즉 §4.1 **G1(무선 페어링)은 "격차"가 아니라 "따라잡기"** 다.

그럼에도 **관제의 핵심 네 축은 여전히 비어 있다**: ① 임계 기반 감시 이벤트 + 쿨다운·ack·뮤트(모두 없음), ② 이벤트 이력의 영구 보존과 아침 브리핑(차트 기록은 있으나 **감시 판정·알림 이력**은 없음), ③ 외부 채널 전송(Droidective의 "Slack-ready"는 **포맷팅**이지 전송이 아니다), ④ **앱별 네트워크 귀속과 `adb(내부)` 분리**. 즉 경쟁 압력은 "도구의 완성도"에서 오고, 우리 방어선은 "지속 감시와 알림"에 있다. 다기기 팜의 유일한 성숙 오픈소스 STF는 macOS 앱이 아니라 서버+웹 구조이고 사용자 경보가 없다 [28].

### F5. GitHub 오픈소스 지형 — 미러링은 활발, 관제 결합은 공백

조사일 기준 저장소 API 실측값(stars·최근 푸시)을 표 3에 요약한다. 미러링·제어·자동화 계층은 매우 활발하지만, **ADB 텔레메트리 대시보드 + 경보 + 다기기 + 메뉴바 상주를 결합한 오픈소스는 없다.**

**표 3. 조사 시점(2026-10-17) GitHub 실측값**

| 저장소 | 별 | 최근 푸시 | 라이선스 | 아카이브 | 한 줄 |
|---|---|---|---|---|---|
| Genymobile/scrcpy [24] | 152,360 | 2026-10-14 | Apache-2.0 | N | 미러링 표준 |
| barry-ran/QtScrcpy [23] | 32,445 | 2026-10-15 | Apache-2.0 | N | Qt GUI + 그룹 제어 |
| viarotel-org/escrcpy [40] | 12,094 | 2026-10-10 | Apache-2.0 | N | Electron GUI |
| mobile-next/mobile-mcp [30] | 9,688 | 2026-10-15 | Apache-2.0 | N | iOS/Android 자동화 MCP |
| DeviceFarmer/stf [28] | 4,605 | 2026-10-02 | NOASSERTION | N | 브라우저 기기 팜 |
| SimonAKing/scrcpy-gui [42] | 4,131 | 2026-10-15 | MIT | N | scrcpy GUI |
| KDE/kdeconnect-kde [1] | 4,061 | 2026-10-17 | 다중 | N | KDE Connect |
| GSConnect [10] | 3,744 | 2026-10-02 | GPL-2.0 | N | GNOME 구현 |
| yume-chan/ya-webadb [39] | 3,249 | 2026-10-09 | MIT | N | 브라우저 ADB |
| **shrimqy/Sefirah** [25] | 3,024 | 2026-10-17 | GPL-3.0 | N | Phone Link 대안 |
| srevinsaju/guiscrcpy [41] | 3,053 | 2023-12-29 | GPL-3.0 | **Y** | 미러링 GUI(중단) |
| CursorTouch/Android-MCP [31] | 898 | 2026-10-16 | MIT | N | 안드로이드 MCP |
| ADB AppControl(배포 전용) [36] | 46 | 2026-09-27 | NOASSERTION | N | 클로즈드소스 ADB 툴 |

동시에 검색 API로 `netstats per-app traffic`, `android network usage per app`, `macos menu bar android device monitor`, `adb device monitor dashboard` 등을 조회한 결과 **ADB 기반 per-app 트래픽 도구는 나오지 않았고**(`netstats` 검색 0건), macOS 메뉴바 후보는 droid-scout 1건에 그쳤다. 검증 중 일부 질의가 API 레이트리밋(403)으로 실패해 완전한 전수 조사는 아니다(§6).

### F6. 폰측 도구 — 텔레메트리·앱별 트래픽·크래시는 폰에서 끝난다

폰에 들어가는 도구들은 Relay Console과 **같은 데이터를 다른 자리에서** 본다. 앱별 트래픽은 PCAPdroid(VPN 캡처, 루트 불필요, 앱별 연결 로그) [43], NetGuard(VPN 방화벽 + 앱별 사용량) [45], GlassWire Android(VPN 기반 폰 내 로컬 집계, 최신 업데이트 시점 미검증) [46]가 제공하지만, **셋 다 결과를 데스크톱 관제 앱으로 푸시하지 않는다** — 최선이 PCAPdroid의 PCAP-over-IP를 Wireshark로 스트리밍하는 수준이고, PCAPdroid에는 공식 데스크톱 앱이 없다 [43][44]. 폰 헬스 앱(DevCheck, Device Info HW, AccuBattery, Battery Guru)은 위젯·리포트가 전부 로컬이고 [조사 §4], 크래시/ANR은 Crashlytics·Sentry(SaaS), ACRA(self-host), Google Play Console로 흩어져 있다.

여기서 Relay Console의 접근이 왜 유효한지가 드러난다. **폰에 앱을 설치하지 않고 adb만으로** 앱별 rx/tx 귀속은 `dumpsys netstats detail`(uid·set·tag·버킷) [48], 크래시/ANR은 `dumpsys dropbox --print data_app_crash|data_app_anr`(셸 권한으로 루트 불필요), 배터리 개요는 `dumpsys batterystats`로 얻을 수 있다 [조사 §3]. 대신 **해상도 한계를 그대로 물려받는다** — netstats 폴 주기는 수 분 단위이고 버킷은 시간 단위라 실시간성이 떨어진다(이 한계가 이 저장소의 `PLAN_net_adb_clamp.md`에서 다룬 "합계 0.0" 회귀의 뿌리이기도 하다) [48]. 연결 단위(IP:port·SNI) 실시간 귀속이 필요하면 VPN 기반 폰 앱이 필요하고, 그건 VPN 슬롯 점유라는 비용을 낸다 [43][45]. `TrafficStats.getUidRxBytes`는 API 24+에서 호출 앱 자신 외 UID를 `UNSUPPORTED`로 반환하므로 서드파티 폰 앱이 전체 UID를 볼 수 없다는 점도, adb 경로가 유일하게 넓은 시야를 갖는 이유다 [47].

무선 연결은 별도의 경쟁 축이다. Android 11+ 무선 디버깅은 **USB 없이** QR 또는 6자리 코드로 페어링하고 재부팅 후에도 유지되지만, Android 10 이하의 `adb tcpip 5555`는 최초 USB 1회가 필요하고 **재부팅하면 풀린다** [49][50]. 무선 페어링 QR은 AOSP 문서에 형식(`WIFI:T:ADB;S:studio-xxxx;;`, `_adb-tls-pairing._tcp` mDNS, 연결 포트 랜덤, TLS)까지 공개돼 있어 구현 장벽이 낮다 [50]. 경쟁 도구(scrcpy-gui, ADB Studio 계열)가 이미 이 온보딩을 넣었고, Relay Console은 이 지점에서 뒤처져 있다(§4·§5 P1).

### F7. 두 개의 신규 경쟁 축 — 에이전트(MCP)와 기업용 MDM

**에이전트 축**이 새로 생겼다. mobile-next/mobile-mcp(별 9,688, 2026-10-15)는 LLM이 안드로이드·iOS를 조작하도록 접근성 트리 기반 제어·앱 설치·화면 녹화·GPS를 제공하고 [30], CursorTouch/Android-MCP(별 898) [31], adb-mcp 계열, 그리고 adb-tui가 MCP 서버(120+ 툴)를 내장한다 [29]. 이들은 **제어 자동화**에 집중하며 **텔레메트리 수집과 임계 알림이 없다**.

Relay Console은 반대편에서 MCP를 제공한다 — 로컬 전용, **읽기 전용**, 기기와 이벤트 스냅샷만 노출한다 [자체]. 즉 "에이전트가 폰을 조작한다"가 아니라 "에이전트가 관제 데이터를 읽고 진단한다"는 다른 가치다. 이 축은 아직 경쟁이 얕아 확장 여지가 크다(§5 P2-3).

**MDM 축**은 텔레메트리+알림을 이미 상품화했다. AirDroid Business [21], Samsung Knox Asset Intelligence(앱별 배터리·네트워크 이상 임계 알림) [54], Esper [55]가 대표적이며, 전부 기기 등록·클라우드·계정·과금을 요구한다. 개인 사용자가 자기 폰 1~3대를 감시하려고 MDM을 도입할 이유는 없다 — 이 지점이 Relay Console의 시장이다.

---

## 3. 종합 — 시장 지도와 Relay Console의 위치

조사 결과를 하나의 지도로 그리면 **네 개의 층**이 보인다.

| 층 | 하는 일 | 대표 | 대가는 | Relay Console 관계 |
|---|---|---|---|---|
| **L1 폰 통합 브리지** | 알림·문자·통화·클립보드·파일 | KDE Connect, Phone Link, Sefirah, CoveLink | 폰 앱 설치, 같은 LAN 또는 계정 | **겹치지 않음**(보완재) |
| **L2 미러링·제어** | 화면·입력·오디오·카메라 | scrcpy, QtScrcpy, Vysor, AirDroid | 관제 없음 | scrcpy에 위임(사용자 결정) |
| **L3 감시·알림** | 추이·임계·번들·채널 | **AirDroid Business**, Knox, Esper | 클라우드·계정·등록·과금 | **정면 경쟁**(우리는 로컬) |
| **L4 도구·팜** | APK·파일·셸·팜 운영 | ADB AppControl, STF, adb-tui | 상시 감시 아님 | 일부 흡수(파일·logcat) |

Relay Console은 **L3에서 로컬·무계정·무서버로 서는 유일한 제품**이며, L1·L2 기능을 최소한으로 흡수(scrcpy 위임, 파일 탐색기, logcat)해 "한 창에서 끝내는" 경험을 만든다. **Sites·Jobs 삭제 이후 포지션은 더 선명해졌다** — 이전에는 "폰·사이트·작업을 한 배지로"였지만, 지금은 **"폰을 지키는 메뉴바 관제탑"** 한 문장으로 좁혀졌고 이 문장에 대응하는 경쟁 제품이 실질적으로 없다.

동시에 이 조사는 **위협의 방향**을 알려준다. ① **가장 실질적인 위협은 Droidective다** — 같은 스택(Swift 6·SwiftUI)·같은 플랫폼(macOS)·오늘도 커밋되는 62★·61종 툴·크래시 브라우저·성능 차트·메뉴바 상주·MCP 서버·Win/Linux 베타까지 갖췄다. 여기에 임계 감시와 알림 채널만 붙으면 우리 포지션과 정면으로 겹친다. ② Sefirah류 오픈소스가 폰 통합을 무료·무계정으로 평준화하면 "폰 앱을 깔지 않는다"는 강점은 그 가치를 아는 사용자에게만 유효하다. ③ AirDroid Business가 가격을 낮추거나 로컬 모드를 내면 L3의 로컬 틈새가 줄어든다. ④ AndroLaunch가 이미 QR 페어링·클립보드를 갖췄으므로 **우리 P1-1은 선택이 아니라 필수**다. 반대로 **앱별 트래픽 귀속 + `adb(내부)` 분리 + 임계 감시 이력 + 채널 전송**의 4축 결합은 조사 범위에서 아무도 하지 않는다.

---

## 4. 기능 갭 분석 — 우리에게 없고 경쟁자에게 있는 것

### 4.1 없는 기능과 adb 실현 가능성 (근거 있는 항목만)

| # | 기능 | 제공자 | 우리 상태 | adb만으로 가능한가 | 판정 |
|---|---|---|---|---|---|
| G1 | **무선 디버깅 QR/코드 페어링**(Android 11+) | **AndroLaunch(88★·macOS 메뉴바)**·scrcpy-gui·ADB Studio·다수 | USB→`tcpip 5555` 방식, **재부팅 시 풀림** [49][50] | **가능**(`adb pair`, 프로토콜 공개) [49][50] | **P1 — 격차이자 필수 따라잡기** |
| G2 | **폰 찾기/벨 울리기** | KDE Connect, Phone Link, Sefirah | 없음 | 경로 존재하나 **미검증**(구현 스파이크 필요) | **P1 후보** |
| G3 | **오디오 포워딩**(11+)·**카메라 미러링**(12+)·**가상 디스플레이**·화면 끈 채 미러링 | scrcpy 5.x, QtScrcpy [24][23] | scrcpy 옵션 노출이 제한적 | **가능**(scrcpy 플래그 위임) | **P2 — 저비용 체감** |
| G4 | **동시 다중 기기 미러링·그룹 제어** | QtScrcpy(그룹 제어), escrcpy [23][40] | 감시는 다기기, 미러링 동시성 미검증 | 가능(scrcpy 다중 인스턴스) | P2~P3 |
| G5 | **알림 미러링 + 답장** | KDE Connect, Phone Link, Sefirah, CoveLink [5][15][25][26] | 없음 | **사실상 불가**(상시 알림 스트림은 폰측 앱 필요, 미검증) | **하지 않음** — KDE Connect 병행 권고 |
| G6 | **SMS 읽기/전송** | KDE Connect, Phone Link, Sefirah | 없음 | `content query` 경로 존재하나 **권한·기기별 미검증** | P3(스파이크 후 결정) |
| G7 | **클립보드 동기화** | KDE Connect(텍스트만), Sefirah, Phone Link | 없음 | 접근 경로 불안정(Android 10+ 제약) [5] | 하지 않음(KDE Connect 병행) |
| G8 | **폰 저장소 SFTP 마운트** | KDE Connect | 파일 탐색기(앱 내부) | 가능(이미 `sftp` 경로 사용) | P3 |
| G9 | **미디어 제어(MPRIS)** | KDE Connect [4] | 없음 | `cmd media_session` 계열 **미검증** | P3 |
| G10 | **앱 스트리밍**(개별 앱을 별도 창) | Phone Link(선별 기기), scrcpy 가상 디스플레이 [16][24] | 없음 | 가능(scrcpy `--new-display --start-app`) | P2(G3에 통합) |
| G11 | **다국어 확대** | KDE Connect 14개 언어 [9] | ko/en | 해당 없음(앱 작업) | P3 |
| G12 | **크로스플랫폼 데스크톱**(Win/Linux) | KDE Connect, CoveLink, Phone Link [6][26] | macOS 26+ 전용 | 해당 없음 | **하지 않음**(포지션 유지) |
| G13 | **클라우드/웹 콘솔·계정·팀** | AirDroid Business, Knox, Esper [21][54][55] | 없음(의도) | 해당 없음 | **하지 않음** |
| G14 | **iOS 심화** | KDE Connect iOS(제한적) [9] | Apple Phase1(배터리·스토리지) | libimobiledevice 한계 | 보류 유지(기기 확보 후) |

### 4.2 우리에게만 있는 것 (조사 범위 내 방어선)

| # | 기능 | 확인 결과 |
|---|---|---|
| M1 | **앱별 네트워크 귀속 + `adb(내부)` 트래픽 분리** | 조사한 어떤 제품에도 없음. DroidGauge(8★)가 앱별 네트워크를 HTML 리포트로 내지만 [32] 실시간·알림·adb 분리는 없음. Droidective의 성능 차트에도 **앱별 귀속은 없음**(코어별 CPU·프로세스별 사용량까지). 폰측 앱(PCAPdroid·NetGuard·GlassWire)은 로컬에 갇혀 있음 [43][45][46] |
| M2 | **18종 감시 + hysteresis + ack/mute/note** | 경쟁 제품은 임계 알림이 없거나(AirDroid Business 예외, 클라우드·유료) 단순 임계만 있음 [21] |
| M3 | **인시던트 번들(ANR·크래시 자동 캡처)** | **Droidective의 크래시 브라우저가 가장 근접**(ANR 포함·watch 모드·Slack/Jira 포맷팅)하나 **임계 자동 캡처·번들 묶음·번들 export는 없음**. ACRA/Crashlytics/Sentry는 SDK 삽입 또는 SaaS [51][52][53] |
| M4 | **로컬 읽기 전용 MCP 서버** | mobile-mcp 계열은 제어 자동화용 [30][31]. 텔레메트리·이벤트 MCP는 드묾 |
| M5 | **메뉴바 상주 + 위젯 + 브리핑 + Health Score** | 메뉴바 상주 자체는 AndroLaunch(88★)·Droidective(62★)·AndroidDeviceManager(3★)도 제공. **브리핑·위젯·Health Score·감시 이벤트 연동은 우리뿐** [37][38] |
| M8 | **임계 감시 + 이벤트 이력 + 채널 전송(3축 결합)** | Droidective(차트+크래시)와 AndroLaunch(토글+QR)를 합쳐도 이 3축은 성립하지 않음 → **§3 위협 ①에 대한 실질 방어선** |
| M6 | **ntfy·Slack 채널 + 시스템 알림 동일 필터** | KDE Connect/Phone Link/Sefirah/CoveLink 모두 외부 채널 없음 [5][15][25][26] |
| M7 | **Android + Apple 한 창** | KDE Connect는 iOS 제약(알림·SMS·가상 디스플레이 없음) [5][9] |

### 4.3 판정

**우리 앱에 "반드시 필요한데 없는" 기능은 G1(무선 페어링 내구성) 하나다.** 폰과 맥을 Wi-Fi로 붙여 놓고 폰을 재부팅하면 USB를 다시 꽂아야 한다는 제약은 관제 앱의 전제(상시 감시)를 직접 훼손하기 때문에, 기능 추가가 아니라 **신뢰성 결함**에 가깝다.

그 다음이 G2·G3다. 둘 다 "관제 → 조치"의 마지막 한 걸음을 채운다. 나머지(G5~G11)는 **경쟁 제품이 이미 잘하고 있고, 우리가 다시 만들면 포지션이 흐려지는 영역**이다. 사용자가 알림 미러링·클립보드·SMS를 원하면 KDE Connect를 함께 쓰는 것이 비용 대비 최선이며, macOS에서도 KDE Connect는 동작하므로 이 조합은 실제로 성립한다 [6][9].

---

## 5. 권고

### 5.1 P1 — 신뢰성과 "조치"의 완성 (근거가 명확한 2건)

**P1-1. Android 11+ 무선 디버깅 QR/6자리 코드 페어링 온보딩 (G1)**

- **왜**: 지금은 USB → `adb tcpip 5555` 방식이라 **폰을 재부팅하면 연결이 풀리고 USB를 다시 꽂아야 한다** [49][50]. 관제 앱의 전제는 "켜져 있으면 감시된다"인데 이 제약이 그 전제를 깨뜨린다. 기능 부족이 아니라 **신뢰성 결함**이다.
- **경쟁 상황(재검증)**: macOS 메뉴바 경쟁자 **AndroLaunch(88★)가 이미 QR 페어링을 제공**한다 → 격차 해소가 아니라 **따라잡기**이며, 뒤처질수록 "메뉴바 앱은 AndroLaunch, 관제는 Relay Console"로 사용자가 이원화된다.
- **어떻게**: `adb mdns services`로 `_adb-tls-pairing._tcp` 탐색 → 코드 입력 → `adb pair host:port code`. QR을 띄우려면 페어링 서비스 문자열을 폰 화면에 띄워야 하므로, 1차는 **6자리 코드 입력**이 현실적이고 QR은 2차.
- **난이도/효과**: 중 / 상. 기존 Wi-Fi 온보딩(`WifiOnboarding.swift`)이 이미 있으므로 "Android 11+면 새 경로, 그 이하면 기존 경로" 폴백 구조가 자연스럽다.

**P1-2. "지금 조치" 세트 — 폰 찾기(벨)·즉시 스크린샷·무음/진동 토글·앱 강제 종료 (G2)**

- **왜**: 경쟁 제품(KDE Connect·Phone Link·Sefirah·CoveLink)이 **모두** 제공하는데 우리에게만 없다. 감시 → 알림 → 조치의 마지막 한 걸음이며, "관제탑"이라는 포지션을 완성한다.
- **어떻게**: 폰 찾기는 광고되는 adb 경로가 여러 개라 **구현 경로를 먼저 실측(스파이크)해야 한다(미검증)**. 대신 스크린샷·미디어 볼륨·앱 강제 종료는 이미 쓰고 있는 adb 표면(`am`, `input`, `screencap`)으로 확실히 된다.
- **난이도/효과**: 하~중 / 중~상. P1-1 다음 순위지만 비용이 낮아 함께 진행해도 좋다.

### 5.2 P2 — 체감과 확장

| 순위 | 항목 | 내용 | 근거 |
|---|---|---|---|
| P2-1 | **scrcpy 옵션 노출 확대** | 오디오 포워딩(11+), 카메라 미러링(12+), 가상 디스플레이, 화면 끈 채 미러링, 개별 앱 스트리밍(`--new-display --start-app`) | G3·G10, scrcpy 5.x가 이미 제공 [24] |
| P2-2 | **MCP 도구 확장 (읽기 전용 유지)** | 앱별 트래픽 조회, 감시 이력/이벤트 조회, 진단 요약, 인시던트 번들 목록. "제어"가 아니라 "진단"으로 차별 | M4, mobile-mcp 계열과 다른 축 [30][31] |
| P2-3 | **인시던트 번들 강화** | `dumpsys dropbox` 경로 보강(누락된 ANR 회수), 번들 내보내기(JSON+이미지) | M3 [48] |
| P2-4 | **다중 동시 미러링** | 기기 2대 이상 동시 미러링/그룹 입력 | QtScrcpy가 제공 [23], effort 큼 |

### 5.3 P3 — 여유가 있을 때

앱별 트래픽 CSV/JSON 내보내기 · 배터리 건강 장기 추이(AccuBattery 영역과의 접점) · 다국어 확대 · 폰 저장소 SFTP 브라우저(G8) · SMS/미디어 제어(G6·G9)는 **권한이 허용되는 기기 한정 옵션**으로 스파이크 후 결정.

### 5.4 하지 말 것 (근거 있는 비권장)

1. **알림 미러링·클립보드·SMS의 전면 구현(G5·G7)** — adb만으로는 상시 알림 스트림을 얻기 어렵고(미검증), 이미 KDE Connect·Phone Link·Sefirah가 무료로 잘한다. 대신 **설정 화면과 README에 "KDE Connect 병행" 한 줄을 넣는 것**이 비용 대비 효과가 크다. macOS에서도 KDE Connect가 동작하므로 이 조합은 실제로 성립한다 [6][9].
2. **Windows/Linux 포팅(G12)** — KDE Connect·CoveLink·Phone Link·Sefirah가 이미 점유한 시장이고, 우리 강점(메뉴바 상주·macOS 통합·SwiftUI)이 그대로 무너진다. **macOS 26+ 요구도 이미 좁은 편**이라 플랫폼 확장보다 깊이가 낫다.
3. **클라우드/웹 콘솔·계정·팀 기능(G13)** — AirDroid Business·Knox·Esper의 영역이며, "데이터는 이 기기에서만"이라는 현재 약속과 충돌한다.
4. **미러링 자체 구현** — scrcpy 위임 유지(이미 내린 결정).

### 5.5 포지셔닝 문구 제안

- **KDE Connect 대비**: "KDE Connect는 폰을 **편하게** 만들고, Relay Console은 폰을 **지킵니다**."
- **Phone Link/MDM 대비**: "폰에 앱을 깔지 않고, 계정도 서버도 없이, 폰의 **속**을 봅니다."
- **ADB 유틸 대비**: "열어보는 도구가 아니라, 켜져 있는 동안 계속 보는 관제탑."

---

## 6. 한계와 미검증

| # | 항목 | 상태 |
|---|---|---|
| L1 | GitHub 별 수·최근 푸시 | ~~1차 수집값~~ → **2026-10-17 재검증 완료**: `gh api`(PAT 인증)로 저장소 44개 전수 조회(부록 B). 다만 별 수는 계속 변동하므로 수치는 조사 시점값 |
| L2 | Windows 트레이 상주 앱 부재 | **검색 기반 결론**(시도 질의는 §8). 전수 조사가 아니므로 "발견되지 않음"이 정확한 표현 |
| L3 | adb 실현 가능성 G2(폰 찾기)·G6(SMS)·G9(미디어 제어) | **구현 경로 미검증** — 스파이크 필요 |
| L4 | adb로 알림 미러링 가능성 | 상시 알림 스트림은 폰측 앱/특수 권한이 필요하다고 판단하나 **미검증** |
| L5 | AirDroid Personal 가격 | 페이지가 JS 렌더링이라 조사 시점 **확인 실패** |
| L6 | GlassWire Android 업데이트 상태 | 최신 업데이트 시점 **미검증** |
| L7 | KDE Connect macOS 지원 | 배포 페이지와 커뮤니티 위키가 서로 다름(**문서 간 불일치**) [6][12] |
| L8 | SideSync 종료 시점 | **미검증**(문서 근거 확보 실패) |
| L9 | 표 3 라이선스 표기(NOASSERTION 등) | GitHub 분류값 그대로 |

참고로 본 보고서의 **모든 URL은 2026-10-17에 HTTP 상태를 실측**했다(56건 중 Vysor 가격 페이지만 404여서 `vysor.io` 루트로 교체, 최종 전건 200).

---

## 부록 A. 기능 매트릭스 (제품 × 기능)

범례: **O** 있음 · **△** 부분/제한 · **X** 없음. 조사 범위 기준이며 미검증 항목은 §6 참조.

| 기능 | Relay Console | KDE Connect | Phone Link | Sefirah | AirDroid Business | scrcpy/QtScrcpy | STF/MDM |
|---|---|---|---|---|---|---|---|
| 알림 미러링 | X | O | O | O | O | X | X |
| SMS 읽기/전송 | X | O | O | O | △ | X | X |
| 클립보드 동기화 | X | O(텍스트) | O | O | △ | △ | X |
| 파일 전송 | O(탐색기) | O | O | O | O | O | △ |
| 화면 미러링 | O(scrcpy 위임) | △(가상 모니터) | △(선별 기기) | O(scrcpy) | O | O | O(웹) |
| 오디오/카메라 미러링 | △(플래그 노출 필요) | X | X | △ | O | O | X |
| 다중 기기 동시 | △(감시만) | O | △ | O | O | O(Qt 그룹) | O(팜) |
| 기기 텔레메트리(CPU·발열·MEM) | **O(8카드·5분 추이)** | X | △(배터리·연결만) | X | △(배터리·스토리지·데이터) | X | △ |
| 앱별 네트워크 귀속 | **O(+adb(내부) 분리)** | X | X | X | △(셀룰러 앱별) | X | X |
| 임계 알림·감시 | **O(18종·쿨다운·ack)** | X | X | X | O | X | △ |
| 이력 보존·추이 | O | X | X | X | △ | X | △ |
| 크래시/ANR 번들 | O | X | X | X | X | X | X |
| 폰에 앱 설치 불필요 | **O(adb만)** | X | X | X | X | O | O |
| 계정·클라우드 불필요 | O | O | △(MS 계정) | O | X | O | X |
| 메뉴바/트레이 상주 | **O(macOS)** | △(Windows 트레이) | X | X | X | X | X |
| AI/에이전트(MCP) | **O(읽기 전용)** | X | X | X | X | X(adb-tui 예외) | X |
| 외부 알림 채널(ntfy/Slack) | **O** | X | X | X | △(콘솔·이메일) | X | X |
| 무선 페어링 편의 | △(USB→`tcpip`) | O(QR) | O(QR) | O(QR) | O | △ | △ |

**읽는 법**: 3개의 굵은 축(앱별 네트워크 / 임계 알림 / 폰 앱 불필요 + 메뉴바 상주)이 비어 있는 열이 우리의 자리다. 반대로 알림·SMS·클립보드 열은 **이미 강자가 있어 다시 만들 이유가 없다**는 것이 이번 조사의 실질 결론이다.

---

## 부록 B. GitHub 저장소 재검증 (2026-10-17 · `gh api` PAT 인증 · 5,000/h)

1차 조사에서 익명 `curl`(시간당 60회)이 레이트리밋으로 막혀 재검증하지 못했던 항목을 인증 토큰으로 전수 재조회했다. **표 3의 주요 수치는 모두 일치**했고, 아래는 보고서에 등장하는 전체 저장소다.

| 저장소 | 별 | 최근 푸시 | 라이선스 | 아카이브 |
|---|---|---|---|---|
| `Genymobile/scrcpy` | 152361 | 2026-10-14 | Apache-2.0 | N |
| `barry-ran/QtScrcpy` | 32445 | 2026-10-15 | Apache-2.0 | N |
| `viarotel-org/escrcpy` | 12094 | 2026-10-10 | Apache-2.0 | N |
| `mobile-next/mobile-mcp` | 9688 | 2026-10-15 | Apache-2.0 | N |
| `ACRA/acra` | 6500 | 2026-10-15 | Apache-2.0 | N |
| `emanuele-f/PCAPdroid` | 4926 | 2026-09-26 | GPL-3.0 | N |
| `DeviceFarmer/stf` | 4605 | 2026-10-02 | NOASSERTION | N |
| `tomotoes/scrcpy-gui` | 4131 | 2026-10-15 | MIT | N |
| `SimonAKing/scrcpy-gui` | 4131 | 2026-10-15 | MIT | N |
| `KDE/kdeconnect-kde` | 4061 | 2026-10-17 | none | N |
| `GSConnect/gnome-shell-extension-gsconnect` | 3744 | 2026-10-02 | GPL-2.0 | N |
| `yume-chan/ya-webadb` | 3249 | 2026-10-09 | MIT | N |
| `srevinsaju/guiscrcpy` | 3053 | 2023-12-29 | GPL-3.0 | **Y** |
| `shrimqy/Sefirah` | 3024 | 2026-10-17 | GPL-3.0 | N |
| `koush/vysor.io` | 2030 | 2026-10-16 | none | N |
| `KDE/kdeconnect-android` | 1481 | 2026-10-17 | GPL-2.0 | N |
| `kil0bit-kb/scrcpy-gui` | 1416 | 2026-08-24 | MIT | N |
| `shrimqy/Sefirah-Android` | 988 | 2026-10-15 | GPL-3.0 | N |
| `CursorTouch/Android-MCP` | 898 | 2026-10-16 | MIT | N |
| `Shrey113/Adb-Device-Manager-2` | 634 | 2026-08-28 | Apache-2.0 | N |
| `GeorgeEnglezos/Scrcpy-GUI` | 502 | 2026-09-02 | AGPL-3.0 | N |
| `measure-sh/holo` | 92 | 2026-04-29 | MIT | N |
| `aman-senpai/AndroLaunch` | 88 | 2026-10-02 | AGPL-3.0 | N |
| `Droidective/Droidective` | 62 | 2026-10-17 | MIT | N |
| `Zaphkiel-Ivanovna/adb-studio` | 25 | 2026-10-05 | MIT | N |
| `yuhnin-m/Adb-DECK` | 25 | 2026-03-27 | none | N |
| `Codertainment/scrcpy_buddy` | 24 | 2026-08-23 | Apache-2.0 | N |
| `alanisme/adb-tui` | 20 | 2026-03-11 | Apache-2.0 | N |
| `meroving/FluentAdb` | 14 | 2016-09-24 | Apache-2.0 | N |
| `RuizheGu0/droidgauge` | 8 | 2026-08-25 | MIT | N |
| `Bloby22/andtls` | 4 | 2026-08-30 | MIT | N |
| `pepperonas/adboss` | 4 | 2026-08-21 | MIT | N |
| `CRTYPUBG/adb-studio` | 3 | 2026-08-10 | Apache-2.0 | N |
| `samkit/droid-scout` | 3 | 2026-06-12 | Apache-2.0 | N |
| `WhileEndless/AndroidDeviceManager` | 3 | 2025-07-27 | AGPL-3.0 | N |
| `sxwik/Relay` | 2 | 2026-06-23 | NOASSERTION | N |
| `davistdaniel/droic` | 2 | 2025-05-28 | MIT | N |
| `shruhood/MEGASUS` | 1 | 2026-07-01 | none | N |
| `AbiMangalan/JankMark` | 1 | 2026-06-23 | NOASSERTION | N |
| `Jaswanth776/android-device-monitor` | 1 | 2025-05-26 | none | N |
| `snackboycoder/mphone` | {"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}FAILED | - | - | N |
| `ztcxzc/adb-device-monitor` | 0 | 2026-08-11 | none | N |
| `nexuls/scrcpy-gui` | 0 | 2026-03-01 | MIT | N |
| `Dinip/adb_metrics` | 0 | 2025-05-24 | MIT | N |

**읽는 법(정량 결론)**

1. **미러링은 거대하고, 관제는 극소다** — 미러링 계열은 152,361★(scrcpy)·32,445★(QtScrcpy)·12,094★(escrcpy)인데, 감시·관제 계열은 92★(holo)·62★(Droidective)·25★(Adb-DECK)·8★(droidgauge)·1★(JankMark)이다. "관제"는 시장이 비어 있는 게 아니라 **아직 아무도 제대로 만들지 않았다**.
2. **에이전트 축은 이미 크다** — mobile-mcp 9,688★ → MCP는 실험 단계가 아니다. 우리 읽기 전용 텔레메트리 MCP의 차별점은 "제어"가 아니라 "진단·감시 문맥"이다.
3. **동일 스택 경쟁자가 존재한다** — Droidective(62★, Swift 6·SwiftUI, 2026-10-17 푸시)가 가장 가까운 위협이며, AndroLaunch(88★, macOS 메뉴바)가 P1-1(QR 페어링)을 이미 구현했다.
4. **폰측 도구는 성숙하다** — PCAPdroid 4,926★·ACRA 6,500★ → "폰에서 끝나는 도구"는 이미 강자가 있으므로 폰측 앱을 새로 만드는 방향은 비권장(§5.4).
5. `SimonAKing/scrcpy-gui`와 `tomotoes/scrcpy-gui`는 **같은 저장소**(리네임·리다이렉트, 동일 4,131★)이고, `snackboycoder/mphone`은 404(비공개·삭제), `sxwik/Relay`(2★)는 이름만 비슷한 무관 프로젝트다.

## 7. 참고문헌

**KDE Connect 계열**

[1] KDE Connect 데스크톱 저장소(GitHub 미러, 별 4,061) — https://github.com/KDE/kdeconnect-kde
[2] KDE Connect 데스크톱 플러그인 디렉터리(32종) — https://github.com/KDE/kdeconnect-kde/tree/master/plugins
[3] KDE Connect 안드로이드(플러그인 24종) — https://invent.kde.org/network/kdeconnect-android
[4] KDE Connect 프로토콜 문서(버전 8, battery·connectivity_report·clipboard·mousepad 등) — https://invent.kde.org/network/kdeconnect-meta/-/blob/master/protocol.md
[5] KDE UserBase — KDEConnect(기능·플랫폼 한계) — https://userbase.kde.org/KDEConnect/en
[6] KDE Connect 공식 배포 페이지(플랫폼·다운로드·같은 네트워크 요구) — https://kdeconnect.org/
[7] KDE 앱 페이지(릴리스 26.08.2, 2026-10-08) — https://apps.kde.org/kdeconnect/
[8] F-Droid — KDE Connect 안드로이드 1.36.0(2026-10-15) — https://f-droid.org/packages/org.kde.kdeconnect_tp/
[9] App Store — KDE Connect(iOS·macOS 0.5.7) — https://apps.apple.com/us/app/kde-connect/id1580245991
[10] GSConnect 저장소 API(별 3,744 · v73 2026-09-23) — https://api.github.com/repos/GSConnect/gnome-shell-extension-gsconnect
[11] KDE 보안 공지 — CVE-2025-66270(2025-11-28) — https://kde.org/info/security/advisory-20251128-1.txt
[12] KDE Community Wiki — KDEConnect(Windows 포팅·macOS 빌드 상태) — https://community.kde.org/KDEConnect
[13] 병합 요청 — 입력장치 공유(shareinputdevices) — https://invent.kde.org/network/kdeconnect-kde/-/merge_requests/698
[14] 병합 요청 — 가상 모니터(virtualmonitor) — https://invent.kde.org/network/kdeconnect-kde/-/merge_requests/427
[56] 그놈 확장 페이지 — GSConnect — https://extensions.gnome.org/extension/1319/gsconnect/

**Windows 진영 — 폰 통합 브리지**

[15] Microsoft — Phone Link 새로운 기능(기능 목록) — https://support.microsoft.com/en-us/windows/apps/phonelink/what-s-new-and-announcements-for-the-phone-link
[16] Microsoft — Phone Link 지원 기기(앱 스트리밍 대상 기기) — https://support.microsoft.com/en-us/windows/apps/phonelink/supported-devices-for-phone-link-experiences
[17] Intel — Unison 제품 지원 종료 공지(2026-01-01 종료) — https://www.intel.com/content/www/us/en/support/articles/000102120/intel-unison-app.html
[18] MyPhoneExplorer(Windows 전용 · 프리웨어) — https://fjsoft.at/en/
[19] Samsung 지원 — DeX for Mac 종료(2022-01)·DeX for PC One UI 7 이후 미지원 — https://www.samsung.com/us/support/answer/ANS10002880/
[57] Samsung 지원 — Samsung Flow는 Windows 11 비호환 — https://www.samsung.com/us/support/troubleshoot/TSG10013301/
[20] AirDroid 가격 — https://www.airdroid.com/pricing/
[21] AirDroid Business — 원격 모니터링·배터리/데이터 알림 — https://www.airdroid.com/business/remote-monitor-android/
[25] Sefirah — Phone Link / KDE Connect 대안(별 3,024 · GPL-3.0 · 푸시 2026-10-17, 안드로이드 앱 별 988) — https://github.com/shrimqy/Sefirah
[26] CoveLink — 다중 폰 브리지(Win/macOS 유료, 리눅스 무료) — https://covelink.tech/
[27] Android Police — Sefirah 평가 기사 — https://www.androidpolice.com/forget-phone-link-this-ad-free-open-source-app-beats-it-in-every-category/

**미러링·제어**

[22] Vysor 홈(가격 $2.50/월·$10/년·$40 라이프타임, iOS/Android, Vysor Share) — https://vysor.io/
[23] QtScrcpy(별 32,445 · 그룹 제어) — https://github.com/barry-ran/QtScrcpy
[24] scrcpy(별 152,360 · 오디오/카메라/가상 디스플레이) — https://github.com/Genymobile/scrcpy
[40] escrcpy(별 12,094) — https://github.com/viarotel-org/escrcpy
[41] guiscrcpy(아카이브, 2023-12 이후 중단) — https://github.com/srevinsaju/guiscrcpy
[42] scrcpy-gui(SimonAKing, 별 4,131) — https://github.com/SimonAKing/scrcpy-gui (동명 프로젝트 https://github.com/kil0bit-kb/scrcpy-gui)

**ADB 유틸·팜·진단 도구**

[28] DeviceFarmer/stf(브라우저 기기 팜, 별 4,605) — https://github.com/DeviceFarmer/stf
[29] adb-tui(성능 뷰 + MCP 서버 내장) — https://github.com/alanisme/adb-tui
[32] DroidGauge(발열·앱별 네트워크 + HTML 리포트 + CI 게이트) — https://github.com/RuizheGu0/droidgauge
[33] holo / measure-sh(스파크라인 + logcat + 세션 이력) — https://github.com/measure-sh/holo
[34] JankMark(CPU/GPU/배터리 온도 개별 차트) — https://github.com/AbiMangalan/JankMark
[35] Adb-DECK(실시간 CPU/메모리 그래프 + 알림 인스펙터) — https://github.com/yuhnin-m/Adb-DECK
[36] ADB AppControl(앱 관리·logcat·기기 정보) — https://adbappcontrol.com/en/pc/
[37] AndroidDeviceManager(macOS 메뉴바 ADB, 별 3) — https://github.com/WhileEndless/AndroidDeviceManager
[38] adb-studio(네이티브 macOS ADB GUI, 별 25) — https://github.com/Zaphkiel-Ivanovna/adb-studio
[39] ya-webadb / WebADB(브라우저 ADB, 별 3,249) — https://github.com/yume-chan/ya-webadb

**에이전트(MCP)**

[30] mobile-mcp(별 9,688) — https://github.com/mobile-next/mobile-mcp
[31] Android-MCP(별 898) — https://github.com/CursorTouch/Android-MCP

**폰측 도구·플랫폼 제약**

[43] PCAPdroid — 덤프 모드 문서(PCAP-over-IP 등) — https://emanuele-f.github.io/PCAPdroid/dump_modes.html
[44] PCAPdroid 저장소 — https://github.com/emanuele-f/PCAPdroid
[45] NetGuard — https://netguard.me/
[46] GlassWire for Android(Google Play) — https://play.google.com/store/apps/details?id=com.glasswire.android
[47] Android 개발자 문서 — TrafficStats(비호출 UID 조회 제약) — https://developer.android.com/reference/android/net/TrafficStats#getUidRxBytes(int)
[48] Android 개발자 문서 — dumpsys(netstats·dropbox·batterystats) — https://developer.android.com/tools/dumpsys
[49] Android 개발자 문서 — adb(Android 11+ 무선 디버깅) — https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11
[50] AOSP — adb 무선 디버깅 설계(adbd_wifi, QR 페어링 `WIFI:T:ADB;S:...;;`) — https://android.googlesource.com/platform/packages/modules/adb/+/HEAD/docs/dev/adb_wifi.md
[51] Firebase Crashlytics Android(ANR/크래시 수집) — https://firebase.google.com/docs/crashlytics/android/get-started
[52] ACRA(자체 호스팅 크래시 리포터) — https://github.com/ACRA/acra
[53] Sentry Android — https://docs.sentry.io/platforms/android/

**기업용 MDM(감시·알림 상용 사례)**

[54] Samsung Knox Asset Intelligence — 배터리·네트워크 이상 알림 대시보드 — https://docs.samsungknox.com/admin/knox-asset-intelligence/dashboard/overview/
[55] Esper — 기기 텔레메트리 — https://www.esper.io/features/device-telemetry

**자체 자료**

- Relay Console 저장소(README.md, docs/DECISIONS.md D1, docs/MANUAL_VERIFY.md, docs/plans/PLAN_net_adb_clamp.md, Sources/) = 본문 `[자체]`
- 이전 리서치: `docs/research/RESEARCH_competitive_v1.md`(2026-09-24)

---

## 8. 방법론 부록

### 8.1 수행 절차

1. **범위 분해** — 질문을 4축(KDE Connect / Windows / GitHub 오픈소스 / 폰측 도구)으로 나눴다.
2. **자체 인벤터리** — 저장소에서 현재 기능(카드 8종, 감시 18종, 채널, MCP, 파일·logcat·프로세스, 위젯·브리핑, Apple Phase1)과 삭제된 기능(Sites·Jobs, 2026-10-05)을 확인해 비교 기준을 고정했다.
3. **병렬 수집** — 4개 조사 에이전트로 축별 수집. 각자 URL을 요구했고, GitHub 수치는 `api.github.com/repos/...` 실제 응답값만 쓰도록 지시했다.
4. **교차검증** — 핵심 제품(Sefirah, Vysor, Intel Unison, Samsung DeX/Flow, KDE Connect 릴리스)을 독립적으로 다시 확인.
5. **URL 실측** — 참고문헌 56건에 대해 HTTP 상태를 일괄 확인(전건 200, Vysor 가격 페이지 404 → 루트로 교체).
6. **종합·비판** — 결론을 반박해 보는 단계로 "우리에게 정말 필요한가"를 G1~G14로 재판정하고, "하지 말 것"을 별도 절로 분리했다.

### 8.2 시도한 검색·질의(요약)

Windows 트레이 상주형 안드로이드 관제 앱 · Phone Link 대안 2026 · Intel Unison 종료 · MyPhoneExplorer 2026 · Samsung DeX/Flow 종료 · AirDroid Business 알림 · Vysor 가격 · QtScrcpy/scrcpy GUI 비교 · KDE Connect 플러그인 전체 목록 · KDE Connect Windows/macOS 지원 · GSConnect · Android 무선 디버깅 QR 페어링 · adb per-app netstats · dumpsys netstats/dropbox · PCAPdroid/NetGuard/GlassWire · Perfetto/Battery Historian · 크래시 리포팅(Crashlytics/ACRA/Sentry) · MCP 안드로이드(mobile-mcp, Android-MCP) · macOS 메뉴바 안드로이드 모니터 · ADB 기기 대시보드 · STF/DeviceFarmer · MDM(Knox Asset Intelligence, Esper).

### 8.3 이 보고서를 다시 볼 시점

- 경쟁 제품 릴리스(KDE Connect 분기 릴리스, Phone Link 기능 업데이트, Sefirah 1.0 등) · Relay Console P1 착수 시(§5) · 사용자가 "Windows에서도 쓰고 싶다"고 말할 때(§5.4-2 재검토).





