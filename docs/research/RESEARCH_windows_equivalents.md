# RESEARCH_windows_equivalents.md — Windows에서 Relay Console에 해당하는 앱은 무엇인가
> 생성일: 2026-10-17 | 근거: `RESEARCH_competitive_v2.md` §F2·F3의 Windows 심화 조사
> 질문: **macOS 메뉴바 "기기 관제" 앱(Relay Console: ADB 기반 안드로이드 폰 CPU·발열·메모리·네트워크·배터리·헬스 카드 + 5분 스파크라인, 감시 18종, 앱별 네트워크 귀속, 파일 브라우저, logcat, 프로세스, 스크린샷, scrcpy, 인시던트 번들, ntfy/Slack, MCP 서버)과 같은 일을 Windows에서 하는 앱은 무엇인가?**
> 원칙: 모든 주장에 URL. 확인 불가 항목은 **미검증** 표기.

---

## 0. 결론 요약 (TL;DR)

1. **정확한 Windows 대응물은 없다.** 트레이(알림 영역)에 상주하면서 **여러 대의 안드로이드 기기**의 **CPU/발열/메모리/배터리/네트워크 텔레메트리를 차트+이력으로** 보여주고 **임계 알림까지** 하는 Windows 앱은 이번 조사에서 **발견되지 않았다**(§10).
2. 가장 가까운 조합은 **"미러링 + ADB 툴박스"(QtScrcpy, Adb-DECK, ADB AppControl) + "단일기기 텔레메트리 대시보드"(JankMark, holo, DroidGauge)** 이며, **알림(alerting) + 텔레메트리**를 동시에 가진 사실상 유일한 상용 제품은 **AirDroid Business(클라우드 MDM, 웹/데스크톱 콘솔)** 다(§5, §9).
3. Windows "폰 연동"의 기본값은 **Microsoft Phone Link**지만, 텔레메트리라고 부를 수 있는 것은 **배터리 %, Wi‑Fi/모바일 데이터 상태, 연결 상태**뿐이다. **CPU·발열·메모리·앱별 트래픽·logcat은 없다**(§1).
4. macOS 쪽 직접 경쟁자(맥 전용)는 **AndroidDeviceManager(메뉴바), ADB Studio, Droidective** 이며, **Droidective(62★)는 예고가 아니라 Windows/Linux 베타를 실제 배포 중**이다(§9·§14). 즉 "맥에서 되는 걸 Windows에서" 하려는 수요는 대부분 **미충족 상태**다.

---

## 1. Microsoft Phone Link (구 "Your Phone")
- 벤더/플랫폼: Microsoft / Windows 10(2022-10 업데이트+)·Windows 11 전용. macOS·iPadOS 미지원.
- 가격: **무료**(Windows에 기본 포함).
- 최신 상태: Windows 11에 기본 탑재, Start 메뉴 "모바일 장치" 패널 통합(Phone Link 1.25032.82.0 기준). 2026-08-21 리뷰에서 Cross Device Resume·앱 확장 뷰 등 기능 확장 지속.
- 핵심 기능(공식):
  - 알림 미러링·해제·고정, SMS/그룹 대화, 연락처, 통화(PC 스피커/마이크), 사진(최근 2,000장), "현재 재생 중" 미디어 제어, 방해 금지, Instant Hotspot, 클립보드 공유, 파일 드래그앤드롭.
  - **배터리 %, Bluetooth 상태, 현재 Wi‑Fi 네트워크, 모바일 데이터 네트워크/강도 표시.**
  - **폰 화면(Phone screen)**: **Link to Windows가 사전 설치된 특정 기기만**(Surface Duo, Galaxy S9 이상 다수, HONOR Magic4/6, OnePlus, OPPO, Realme, ROG Phone 8, vivo 등). 같은 Wi‑Fi 필요, GPU DirectX11.
  - **앱(Apps)**: 삼성·HONOR·OPPO·ASUS 등 **선별 기기 + Link to Windows 사전 설치**가 전제(Android 10+). Pixel 등은 미지원(사용자 제보).
  - iPhone: iOS 16+(설정 페이지 기준)·BLE 필요. 알림/메시지(읽기·답장 제한)/통화/연락처/배터리·연결 상태/파일 전송. **화면 미러링·앱 스트리밍 없음**. Microsoft 계정 필요(Start 메뉴 모바일 장치 기능).
  - 요구: Android 10+ 권장(최소 8.0), 폰·PC 동일 Wi‑Fi(Android), Microsoft 계정.
- **텔레메트리 검증 결론**: CPU·GPU·메모리·발열(thermal)·스로틀링·앱별 네트워크 귀속·logcat·프로세스 목록 **없음**. 공식 기능 목록에 배터리/연결 상태까지만 존재(위 URL). 즉 대시보드가 아니라 "연결 편의" 제품.
- 출처: [What's new(Phone Link)](https://support.microsoft.com/en-us/windows/apps/phonelink/what-s-new-and-announcements-for-the-phone-link) · [지원 기기](https://support.microsoft.com/en-us/windows/apps/phonelink/supported-devices-for-phone-link-experiences) · [요구사항·설정](https://support.microsoft.com/en-us/windows/apps/phonelink/phone-link-requirements-and-setup) · [폰 화면 설정](https://support.microsoft.com/en-us/windows/apps/phonelink/setting-up-and-using-phone-screen-in-the-phone-link) · [Start 메뉴 모바일 장치](https://support.microsoft.com/en-us/windows/apps/phonelink/mobile-device-in-start-menu) · [동기화 안내(기능 목록)](https://www.microsoft.com/en-us/windows/sync-across-your-devices) · [CNET 2026-02-18](https://www.cnet.com/tech/computing/microsoft-phone-link-everything-you-need-to-know-android-iphone/) · [MakeUseOf 2026-08-21](https://www.makeuseof.com/windows-11-phone-link-is-better-than-ever/)

## 2. Intel Unison — **종료됨**
- 상태: **2026-01-01부로 지원 종료(EOL)**. 공식 사이트 첫 화면이 종료 공지로 대체됨. 일반 사용자 대상 서비스는 **2025-06-30 중단**(Dell 안내 인용, 2025-06 말), Lenovo Aura Edition만 2025년 말까지 한시 지원 후 전면 종료. Intel은 2025-06부터 제품 생산 중단, 다운로드 불가, 지원 채널 종료.
- 대체: Lenovo Aura 기기는 **Lenovo Smart Connect**로 이관. 일반적으로는 **Phone Link**가 가장 근접한 대체(단, 파일 전송/텔레메트리 범위는 축소).
- 시사점: "폰-PC 연동" 카테고리의 빅테크 제품 1개가 사라짐 → Windows에서 이 영역의 서드파티(예: AirDroid) 수요가 커졌다는 분석 다수.
- 출처: [unison.intel.com 종료 공지](https://unison.intel.com/) · [Intel 지원 문서(2026-01-05 갱신)](https://www.intel.com/content/www/us/en/support/articles/000102120.html) · [Windows Central 2025-07-03](https://www.windowscentral.com/software-apps/intel-unison-for-windows-11-shuts-down-encourages-users-to-switch-to-another-multi-device-experience) · [gHacks 2025-07-04](https://www.ghacks.net/2025/07/04/intel-unison-is-dead-here-are-some-alternatives-you-can-switch-to/) · [usefwd 대안 정리(6/30 종료·Dell 안내)](https://usefwd.io/blog/intel-unison-alternatives/) · [Lenovo KB](https://iknow.lenovo.com.cn/detail/437287)
- **미검증**: 4.0.0 최종 버전 번호, iPhone 기능의 최종 상태.

## 3. MyPhoneExplorer (FJ Software) — **2026년에도 현역**
- 플랫폼: **데스크톱은 Windows 전용**(Windows 11/10/8/7). Android 클라이언트 앱 필요.
- 버전/날짜: 데스크톱 **2.3 (2025-10-27)**, Chocolatey 패키지 2.3.0 갱신 2026-04-22. Android 클라이언트 **4.12 (2026-06-09 갱신)**, Play 스토어 설치 640만+.
- 가격: **프리웨어(기부제)**, 유료 티어 없음.
- 기능: SMS 다운로드/백업/발송, 통화 목록, 연락처·일정·메모 동기화(Outlook/Thunderbird/Lotus Notes/Windows Contacts…, 2.3에서 **Microsoft 클라우드 동기화 신규**), 풀 파일 매니저·자동 파일 동기화·백업 마법사, **설치 앱 관리(실행/설치/삭제/PC로 추출)**, 폰 화면 제어(접근성 서비스)·스크린샷, PC 키보드 입력, 바코드/NFC 스캔(2.3), **연결: Wi‑Fi / USB / Bluetooth**, **전부 로컬(외부 서버 없음)**, Thunderbird 애드온 5.2(2026-06-18).
- 없는 것: **CPU·발열·메모리·네트워크 텔레메트리, 차트, 임계 알림, 다중기기 플릿 관제, MCP 없음.** ADB 직접 제어보다는 클라이언트 앱 기반.
- 출처: [fjsoft 버전 목록(2.3, 2025-10-27)](https://fjsoft.at/en/Versions/) · [fjsoft 기능/다운로드](https://www.fjsoft.at/) · [Play 스토어 클라이언트](https://play.google.com/store/apps/details?hl=en_US&id=com.fjsoft.myphoneexplorer.client) · [AppBrain 4.12](https://www.appbrain.com/app/myphoneexplorer-client/com.fjsoft.myphoneexplorer.client) · [Chocolatey 2.3.0](https://community.chocolatey.org/packages/myphoneexplorer) · [Thunderbird 애드온 5.2](https://services.addons.thunderbird.net/En-uS/thunderbird/addon/myphoneexplorer/)

## 4. Samsung 계열 — 사실상 정리됨
| 제품 | 상태 | 근거 |
|---|---|---|
| **SideSync** | **2019-10-15 서비스 종료**(Samsung Flow로 대체) | [SamMobile 2019-09-11](https://www.sammobile.com/news/sidesync-is-officially-shutting-down-replaced-by-samsung-flow), [PhoneArena](https://www.phonearena.com/news/Samsung-SideSync-app-discontinued_id118895) |
| **Samsung Flow** | **Windows 11 비호환**(공식 트러블슈팅: "not compatible with Windows 11"), 대신 Link to Windows 권장. 기능: 알림/문자 확인·답장, 파일·폴더 전송, 화면 미러링, 핫스팟 공유, 최대 여러 기기 등록(동시 1대) | [Samsung TSG10013301](https://www.samsung.com/us/support/troubleshoot/TSG10013301/), [Samsung Flow 안내](https://www.samsung.com/us/support/owners/app/samsung-flow/) |
| **DeX for PC** | **One UI 7 이상 기기에서 미지원**(S25 시리즈 포함). USB 연결·전체화면 등 일부 기능은 Link to Windows로 대체 불가. "DeX는 외부 디스플레이 직접 연결로 초점 이동" | [Samsung ANS10002880](https://www.samsung.com/us/support/answer/ANS10002880/), [Samsung HK 공지](https://www.samsung.com/hk_en/support/apps-services/changes-to-the-way-you-connect-samsung-galaxy-mobile-devices-to-pcs/), [Samsung Members 답변 2026-01-12](https://r2.community.samsung.com/t5/Galaxy-S/SAMSUNG-DEX-NEW-VERSION/td-p/21391021) |
| **DeX for Mac** | **2022-01 지원 종료**(기설치분만 동작, 다운로드 불가) | [Samsung ANS10002880](https://www.samsung.com/us/support/answer/ANS10002880/) |

- 결론: "Samsung으로 Windows에서 폰을 관제"는 **Link to Windows(=Phone Link)로 흡수**되었고, **텔레메트리는 여전히 없음**.

## 5. AirDroid (Sand Studio, 싱가포르)
- 플랫폼: Windows/macOS 데스크톱 클라이언트 + **웹 브라우저 콘솔** + Android 앱. (개인용 / Business MDM / Cast / Remote Support / Parental Control로 분화)
- 가격(2026-10 확인):
  - AirDroid Personal **$3.99부터**(파일 전송·원격 제어·원격 카메라·SMS·통화·알림 관리), Cast **$2.49부터**, Remote Support(Personal) **$2.49부터**, Parental Control **$9.99부터**.
  - **AirDroid Business: Basic $12 / Standard $21 / Enterprise $33 (기기당·연/미만)**, 온프레미스 별도 견적. Remote Support(Business) Basic ~$199/년, Standard $599/년.
- 기능: 파일 전송/관리, 안드로이드 원격 제어, 알림·SMS·통화 PC 연동, 원격 카메라, 스크린 미러링(Cast), 다른 네트워크 간 원격(AirCast, 시간 과금).
- **Business MDM의 "Monitor & Alerts"(§9와 §10의 핵심)**:
  - 대시보드: 기기 화면 스크린샷, 원격 카메라, **셀룰러/Wi‑Fi 데이터 사용량(기기·앱 단위)**, **기기 상태·헬스(온라인/오프라인, 스토리지, 배터리 온도 등)**.
  - 알림 항목: **셀룰러 데이터 사용량, 온라인/오프라인, 배터리 용량, 배터리 온도, 스토리지, 기기 움직임, HDMI, 키오스크 상태, 화면 잠금, 앱 실행 상태, 앱 셀룰러 데이터 사용, 배터리 충전 상태, 포그라운드 앱, Biz Daemon 권한, SIM 장착/제거** + 알림 트리거 시 **자동 워크플로**(재부팅, 화면 끄기, 구성 파일 전환, 공장 초기화, 그룹 이동 등) + **데이터 사용 리포트(주/월, 기기·앱별)**.
  - 필요 조건: 폰에 **Biz Daemon** 설치, **AirDroid 계정**, **인터넷**(원격/클라우드).
- 없는 것(우리 앱 관점): **트레이 상주 아님(웹 콘솔)**, **클라우드 경유(로컬 전용 아님)**, CPU/스로틀링/PSI/ANR·크래시 감시 같은 안드로이드 심층 텔레메트리·logcat·프로세스 목록·scrcpy·인시던트 번들 없음, 유료·기기당 과금.
- 출처: [AirDroid 요금제](https://www.airdroid.com/pricing/) · [Business Monitor & Alerts](https://www.airdroid.com/business/remote-monitor-android/) · [알림·SMS 관리](https://www.airdroid.com/personal/sms-notification-call-on-pc/) · [XDA: 원격(다른 네트워크)은 유료, 로컬 무선은 제한 적음](https://www.xda-developers.com/intel-unison-shutting-down-using-this-app-instead/)

## 6. Vysor (ClockworkMod / Vysor, Inc.)
- 플랫폼: Windows 10/11, macOS, Linux, **브라우저(WebUSB ADB)**. iOS는 네이티브 앱만.
- 가격: Free(기본 미러링/제어/스크린샷 — 무제한·워터마크 없음), **Pro $2.50/월 · $10/년 · $40 라이프타임**, Enterprise **$2/활성 사용자·월(최소 5명)**.
- 버전/날짜: 2026-08-08 기준 라이브 웹앱 **5.0.72**, vysor.org 표기 5.0.7(2026-02). iOS 앱스토어 최종 2022-05-22.
- 기능: 미러링·제어(마우스/키보드), 스크린샷, HD 미러링, 전체화면, **무선(Pro)**, **Vysor Share(원격 화면·ADB 공유 링크)**, 드래그앤드롭 파일 전송, **Pro는 인터페이스 내에서 실행 중 프로세스·ADB 로그 조회**.
- **알림 미러링**: koush/vysor.io README의 **3.2.x 체인지로그 "Vysor Notification Mirroring"**(안드로이드 알림을 데스크톱으로 미러링)으로 도입됨. 단 Pro 전용 여부·2026년 현행 유지 여부는 **미검증**(현행 요금표에는 알림이 명시되지 않음).
- 없는 것: **텔레메트리 차트/이력/임계 알림 없음**(프로세스·ADB 로그는 Pro에서 "조회" 수준), 앱별 네트워크 귀속 없음, 다중기기 플릿 관제 없음, logcat 뷰어 없음(ADB 로그 확인은 있음).
- 출처: [vysor.io](https://www.vysor.io/) · [vysor.org 요금/Pro](https://vysor.org/pricing/) · [vysor.org FAQ](https://vysor.org/faq/) · [rottenwifi FAQ(5.0.72, 2026-08-08)](https://rottenwifi.com/vysor-faqs/) · [koush/vysor.io 3.2.x 알림 미러링](https://github.com/koush/vysor.io/) · [vysor.pro features(Pro: 프로세스·ADB 로그)](https://vysor.pro/features.html)

## 7. QtScrcpy와 Windows용 scrcpy GUI 래퍼 — **미러링만, 모니터링 없음**
| 앱 | 벤더/라이선스 | 플랫폼 | 최신 | 핵심 | 없는 것 |
|---|---|---|---|---|---|
| **QtScrcpy** | barry-ran / Apache-2.0, 무료 | Win/mac/Linux | **v4.2.1 (2026-08-13)** | 실시간 화면·키보드/마우스 제어, **다중기기·그룹 제어**, 녹화/스크린샷, APK 드래그 설치, 파일 전송, 클립보드 양방향, 커스텀 키맵(게임), 오디오(sndcpy), 커스텀 ADB 명령 | **텔레메트리·차트·이력·알림·앱별 트래픽·logcat 뷰어 없음.** 저자 유료 배치 도구 QuickMirror(무료 10화면까지) 별도 |
| **scrcpy buddy** | Codertainment / Apache-2.0, 무료(Microsoft Store) | Win/Linux/macOS | **v1.0.6 (2026-03-04)** | Fluent UI, 다중 scrcpy 실행, ADB 기기 관리(USB↔네트워크 전환), 프로필, 콘솔 로그, 앱 선택 | 텔레메트리·알림 없음(애초에 scrcpy 래퍼) |
| **Scrcpy GUI(GeorgeEnglezos)** | MIT, 무료 | Win/mac/Linux | **v1.7.5 (2026-06-27)** | 명령 빌더, 다중기기, 무선 설정, **실행 중 scrcpy 프로세스 감시**, 즐겨찾기, App Drawer(헬퍼 APK) | 텔레메트리·기기 감시·알림 없음 |
| **Scrcpy GUI(simonaking)** | MIT(2.4.2+) | Win/mac/Linux | 2.4 스테이블 | scrcpy 4.1/adb 번들, Android 11+ `adb pair`, 멀티기기, 진단 | 텔레메트리·알림 없음 |
| **nexuls/scrcpy-gui** | MIT, 무료 | Win/Linux | 신규(2026-03 생성) | Wails(Go+React), 세션 로그, 번들 런타임 | 텔레메트리·알림 없음 |
| **guiscrcpy** | srevinsaju / GPL-3.0 | Win/Linux | **아카이브됨(2023-12-29 이후 개발 중단)** | scrcpy 플러그형 GUI | 텔레메트리 없음 + **유지보수 종료** |
- **FluentADB = 앱이 아니라 C#/.NET용 ADB SDK**(GUI 아님) → 이 항목은 "해당 없음". 출처: [meroving/FluentAdb](https://github.com/meroving/FluentAdb)
- 출처: [QtScrcpy](https://github.com/barry-ran/QtScrcpy) · [scrcpy_buddy](https://github.com/Codertainment/scrcpy_buddy) · [Scrcpy-GUI](https://github.com/GeorgeEnglezos/Scrcpy-GUI) · [simonaking Scrcpy GUI](https://simonaking.com/scrcpy-gui/) · [nexuls/scrcpy-gui](https://github.com/nexuls/scrcpy-gui) · [guiscrcpy(archived)](https://github.com/srevinsaju/guiscrcpy) · 릴리스 날짜는 각 저장소 `releases.atom` 확인

## 8. 상용 미러링 스위트 — **텔레메트리·알림 없음**(AirDroid Business 제외)
| 앱 | 벤더 | 플랫폼 | 가격(2026-10 확인) | 특징 | 없는 것 |
|---|---|---|---|---|---|
| **ApowerMirror** | Apowersoft | Win/mac/iOS/Android/TV | 무료(10분 제한·워터마크) / **$19.95/월, $39.95/년, $69.95 라이프타임**(다른 출처는 $29.9/월·$69.9/년 → **가격 정보 상충, 미검증**) | 동시 4대 미러링, PC에서 안드로이드 제어, 파일/드래그, 녹화·주석·화이트보드, 게임 키맵, AirCast(다른 네트워크, 분당 과금) | 텔레메트리·차트·임계 알림·logcat 없음 |
| **MirrorGo** | Wondershare | Windows | **$19.95/월**, 분기 $9.97, 연 $3.32(프로모션 표기·할인 사이트) | 안드로이드 미러링·제어, 파일 전송, 클립보드, 게임 키보드, 녹화 | 동일 |
| **Total Control** | Sigma-RT | Windows 7~11 | Lite **무료(1~2대)**, Professional 유료(4/10/20/30/50대 티어) | WDM(기기별 창)·**MDCC(다중 제어 센터)**, 저지연, 대규모 디바이스 팜, 스크립트/API, 안드로이드 6~16 | 텔레메트리 차트·임계 알림 없음 |
| **Mobizen** | RSUPPORT | Windows/웹/Android | 무료 + **Premium 약 $4/월** | 화면 녹화·편집·라이브 스트리밍, 실시간 미러링, 원격 제어, 파일 전송, **알림 보기** | 텔레메트리·알림(감시) 없음 |
| **LetsView** | 아파소프트 계열 | Win/mac/iOS/Android/TV | Basic 무료(로컬 무제한, SD·워터마크) / **Pro $7.99/월**(FHD 60fps·기기 제어·확장), **원격은 별도 분당 과금** | 미러링, 확장(2nd 모니터), 원격 미러링, 화이트보드·녹화 | 동일 |
| **TeamViewer (QuickSupport/Host + Universal add-on)** | TeamViewer | Win/mac/Android | 개인 무료, **데스크톱→모바일은 구독 + MDS 애드온 필요** | 안드로이드 원격 제어(제조사 전용/Universal 애드온, Android 7+), 파일 전송, 채팅, 기기 정보 조회, Wi‑Fi 설정 푸시, 앱 목록, 진단 정보 | 텔레메트리 추이·차트·임계 알림 없음 |
- 참고: TeamViewer 개인 무료는 "상업적 사용" 판정 시 30초 제한·10분 단절 사례 다수(Play 리뷰). 출처: [TeamViewer QuickSupport](https://www.teamviewer.com/en-us/solutions/use-cases/quicksupport/) · [Universal add-on](https://www.teamviewer.com/en-us/global/support/knowledge-base/teamviewer-classic/mobile/android/universal-add-on-for-android/) · [원격 제어(attended)](https://www.teamviewer.com/en/global/support/knowledge-base/teamviewer-classic/mobile/android/remote-control-an-android-device-via-attended-access/)
- 출처(가격): [ApowerMirror 요약](https://www.itechguides.com/products/apowermirror/) · [미러링 앱 비교 2026](https://mirrorscreen.tv/reviews/5-best-screen-mirroring-apps-2026) · [MirrorGo 가격](https://www.colormango.com/product/wondershare-mirrorgo_150544.html) · [Total Control](https://www.sigma-rt.com/en/tc/) · [Mobizen 리뷰](https://tekpon.com/software/mobizen/reviews/) · [LetsView 요금](https://letsview.com/pricing) · [LetsView 2026 리뷰](https://mirrorscreen.tv/reviews/letsview-review-2026-whats-free-whats-paid-and-is-it-worth-it)

## 9. "ADB 기반 Windows 다중기기 모니터링 + 텔레메트리" 도구 — 있는 것과 없는 것

**(a) 플릿/다중기기 — 텔레메트리 없음**
- **DeviceFarmer(STF)**: 웹 기반 원격 디버깅 팜. **"On Windows you're on your own" — 공식 Windows 설치 지원 없음**(Cygwin도 미검증). 기기 인벤토리에서 **배터리 레벨·헬스를 추적**하지만 사용자용 트레이/차트/알림 콘솔은 아님. 최신 릴리스 **v3.7.9 (2026-07-08)**, 유지보수 위주.
- **ADB AppControl**(Windows 7~11): 앱 관리·디블로트·권한·파일 전송·scrcpy 제어·logcat·기기 정보 패널(배터리·스토리지·네트워크). **버전 1.8.6, 2025-07-15 갱신**, **Extended 약 $7 일회(1 PC)**. **텔레메트리 추이/차트/임계 알림 없음.**
- **Panda(Some3C)**: Windows/macOS, **최대 1,000대**, 실시간 썸네일 대시보드 + "기기 상태·성능 메트릭", 동기 입력, 자동화, 기기 그룹/공유. **처음 40대 무료**, 이후 유료 구독. **차트 이력·임계 알림·앱별 트래픽 없음(미검증 포함)**.
- **MPhone(snackboycoder)**: Qt 기반 플릿 콘솔(디바이스 풀/캔버스/진단/배치 스크립트/헬스체크/keepalive 에이전트), Windows x64 설치본. **단, 저장소가 현재 404(비공개/삭제 추정) → 배포·유지 상태 미검증.**
- **Adb-DECK(yuhnin-m)**: **Win/mac/Linux** GUI. 13개 정보 섹션(CPU/RAM·배터리·네트워크·셀룰러·모뎀·보안…), **실시간 프로세스 + CPU/메모리 라이브 그래프**, 알림 인스펙터(이력/스냅샷). **임계 알림·장기 차트·앱별 트래픽 없음**(로드맵 "Network traffic inspector" 예정).
- **ADBOSS(pepperonas)**: PySide6, **v0.2.0 (2026-03-01)**. 배터리 게이지(온도·전압·헬스), RAM/스토리지 바, 네트워크, logcat, 파일 브라우저, 셸, 입력 제어, BT HCI 분석. 5초 자동 갱신. **차트/이력/알림 없음.**
- **ADB Device Manager(Shrey113)**: Windows/Linux. ADB 모드(미러링·입력·APK·연락처/SMS/통화 추출) + App 모드(Wi-Fi 알림/전화/미디어), **시스템 트레이 통합**, 다중기기. **텔레메트리 없음.**
- **AndroLaunch**: macOS **및 Windows** 메뉴바형 ADB/Scrcpy 관리(QR 무선 페어링, 토글, 볼륨/밝기, APK 설치, 셸). **텔레메트리 없음.**

**(b) 단일기기 텔레메트리/프로파일링 — 트레이·알림 없음**
- **JankMark(AbiMangalan, Windows 전용, 클로즈드 소스 베타)**: **v0.2.1-beta (2026-06-20)**. ADB로 FPS·프레임타임·5%/1% 로우·jank%, **CPU/GPU/RAM + CPU/GPU/배터리 온도 개별 차트**, 전력/전압/전류, 클럭(스로틀 추적), 동기 크로스헤어, **세션 라이브러리 자동 저장**. 설치형, 무료(가격 미검증). **임계 알림·다중기기 동시 모니터링·앱별 네트워크·트레이 상주 없음.**
- **holo(measure-sh)**: **Windows 빌드 제공**(`holo-x86_64-pc-windows-msvc.zip`) TUI. **라이브 CPU/메모리/디스크/네트워크 스파크라인**, logcat, Perfetto 트레이스, 세션 이력, scrcpy 미러링, MCP 없음. **알림·트레이 없음, 한 번에 한 기기 중심.**
- **DroidGauge(RuizheGu0)**: **ADB만 사용하는 로컬 CLI**. CPU·PSS 메모리·jank·배터리·**발열(thermal)**·**앱별 네트워크 신호**, 오프라인 HTML 리포트(SVG 추이), **A/B 회귀 판정 + CI 게이트(exit 2)**. **실시간 알림/트레이 없음**(리포트·게이트 지향).
- **Droic(davistdaniel)**: Python Dash 대시보드, CPU/메모리/태스크 시각화, **SQLite 이력**, 앱 내 알림 이벤트. macOS/Linux 검증, Windows "동작 예상"(미검증).
- **adb_metrics(Dinip)**: CLI 수집기 + **InfluxDB + Grafana 대시보드**. CPU/메모리/**배터리 온도/열 센서** + **앱별 CPU/PSS**. **서버(Grafana) 필요**, Windows는 WSL/bash 언급.
- **MEGASUS PRO(shruhood)**: ADB 기반 터미널 운영 플랫폼(10개 모듈: 텔레메트리, 보안 감사, 감시, 자동화). **터미널 UI, 트레이/차트/알림 없음**(웹 대시보드 v1.1 예정).
- **Jaswanth776/android-device-monitor**: 웹 대시보드(localhost:3000), 배터리/메모리/카메라·마이크 사용/네트워크 트래픽/권한/프로세스/파일. **웹, 이력 차트·알림 없음.**
- **Relay(sxwik)**: **Windows Electron "Android 워크스테이션"**. 배터리 헬스(온도·충전·용량 분석), **퍼포먼스 모니터(CPU/RAM/스토리지/기기 온도)**, 알림 센터, **기기 타임라인(연결·업데이트·스토리지 변화)**, ADB 셸/Fastboot. **릴리스 없음(atom 비어 있음)·별점/유지보수 확인 불가 → 미검증.**
- **adb-tui(alanisme)**: **v0.1.0 (2026-03-11)**, Windows/Linux/macOS 바이너리. 11개 뷰(Devices/Info/Shell/Logcat/Files/Packages/Port/Input/Processes/Settings/**Performance**), **Performance 뷰 = 라이브 CPU·메모리·배터리·디스플레이**, **MCP 서버(120+ 툴)** 내장. **차트 이력·임계 알림·트레이 없음.** (우리 앱과 MCP·성능 뷰가 겹치는 가장 근접한 OSS)
- **Android Studio Profiler / Android Performance Analyzer(APA, Google)**: CPU·메모리·네트워크·에너지/전력 레일, **Windows에서 단독 실행형 프로파일러 존재 — macOS는 단독 프로파일러 미지원**. APA는 **Windows/macOS/Linux 데스크톱 앱(오픈 베타, 2026-05-19)**, CPU/GPU/메모리/전력 분석. **단, "debuggable/profileable 앱" 전제 + 상시 감시·알림·트레이 아님.**

**(c) macOS 전용(= "맥에서 되는 것"의 원류, Windows 대응 없음)**
- **AndroidDeviceManager(WhileEndless)**: **macOS 메뉴바** 앱, 10초 탐지, root/인증 표시, USB/Wi-Fi. (v1.2.1, 2025-07-25)
- **ADB Studio(Zaphkiel-Ivanovna)**: **macOS 14+ SwiftUI**, 무선 디버깅·mDNS 발견·포트포워드 프리셋·APK.
- **Droidective**: macOS 14+ Swift 6. **61개 툴, 무료·MIT, 메뉴바 extra 제공** + **Windows/Linux는 베타 채널(NSIS/MSI, Rust 네이티브 메뉴바)** — **재검증(§14): 62★ · 2026-10-17 푸시 · 같은 `main`에서 32개 뷰 중 29개 포팅**(미러·터미널 포함). Windows **정식판은 아님**. **이 생태계에서 가장 실질적인 경쟁자다.**

- 출처: [DeviceFarmer/stf](https://github.com/DeviceFarmer/stf) · [RobusTest(v3.7.9, 2026-07-08)](https://robustest.com/blog/why-device-labs-get-abandoned) · [ADB AppControl](https://adbappcontrol.com/en/pc/) · [ADB AppControl 구매](https://adbappcontrol.com/en/pc/buy/) · [Technastic($7)](https://technastic.com/adb-app-control-extended-android/) · [Panda](https://panda.some3c.com/) · [MPhone](https://github.com/snackboycoder/mphone) · [Adb-DECK](https://github.com/yuhnin-m/Adb-DECK) · [ADBOSS](https://github.com/pepperonas/adboss) · [ADB Device Manager](https://github.com/Shrey113/Adb-Device-Manager-2) · [AndroLaunch](https://github.com/aman-senpai/AndroLaunch) · [JankMark](https://github.com/AbiMangalan/JankMark) · [holo](https://github.com/measure-sh/holo) · [DroidGauge](https://github.com/RuizheGu0/droidgauge) · [Droic](https://github.com/davistdaniel/droic) · [adb_metrics](https://github.com/Dinip/adb_metrics) · [MEGASUS](https://github.com/shruhood/MEGASUS) · [android-device-monitor](https://github.com/Jaswanth776/android-device-monitor) · [sxwik/Relay](https://github.com/sxwik/Relay) · [adb-tui](https://github.com/alanisme/adb-tui) · [Android Studio 프로파일링](https://developer.android.com/studio/profile) · [단독 프로파일러(Win/Linux만, macOS 미지원)](https://developer.android.com/studio/profile/standalone-profiler) · [Power Profiler](https://developer.android.com/studio/profile/power-profiler) · [APA 발표 2026-05-19](https://developer.android.com/blog/posts/introducing-android-performance-analyzer-the-next-evolution-in-profiling-for-android) · [Droidective](https://github.com/Droidective/Droidective) · [AndroidDeviceManager(macOS)](https://github.com/WhileEndless/AndroidDeviceManager) · [adb-studio(macOS)](https://github.com/Zaphkiel-Ivanovna/adb-studio) · [CRTYPUBG/adb-studio(Windows-first, 0.1.0-dev)](https://github.com/CRTYPUBG/adb-studio)

## 10. **질문에 대한 명시적 답: 트레이(메뉴바) 상주형 다중기기 안드로이드 텔레메트리 콘솔 + 알림 — Windows에는 없다**

- **답: 없다(이번 조사에서 미발견).** 트레이 상주 + ADB + **다중기기** + **CPU/발열/메모리/네트워크/배터리 추이** + **임계 알림**을 한 앱으로 제공하는 Windows 제품은 확인되지 않았다.
- 트레이 상주형 후보(모두 요건 미달):
  - **BatteryBoi(blueheron786)**: Windows 트레이 아이콘 + 드래그 가능 폼으로 **안드로이드 배터리 %만** 표시(ADB 번들). 충전 중/80%↑/연결 끊김 상태 표시. **차트·이력·임계 알림·다중기기·다른 지표 없음.**
  - **ADB Device Manager(Shrey113)**: **시스템 트레이 통합**(C# 서비스) + 알림 동기화·통화·미디어, 다중기기. **텔레메트리 없음.**
  - **AndroLaunch**: Windows에서도 메뉴바형 ADB/Scrcpy 런처. **텔레메트리 없음.**
  - **BTChargeTrayWatcher**: **Windows 트레이 + ntfy.sh 푸시 알림**으로 Bluetooth 기기·노트북 배터리 임계 알림(장르 증명용 유사 사례, **안드로이드 아님**).
  - **VisoDyne Battery Monitor / JPITSG BluetoothBatteryMonitor / EasyBluetooth**: 트레이 배터리 아이콘·알림 계열(Bluetooth 주변기기용, **안드로이드 ADB 아님**).
  - **ThermalWatch / XStat / PowerSwitchOverlay / NodePilot**: 트레이·알림(ntfy 포함)을 갖췄지만 **감시 대상이 Windows PC 자신**(NodePilot은 반대 방향: PC를 폰에서 감시).
  - **JankMark / holo / DroidGauge / adb-tui / ADB AppControl / Adb-DECK**: 텔레메트리 또는 기기 관리는 있으나 **트레이 상주 아님·알림 없음**(adb-tui는 TUI, JankMark는 창형 대시보드).
  - **AirDroid Business**: **텔레메트리 + 임계 알림 + 자동 워크플로**를 갖춘 유일한 조합이지만 **웹/클라우드 콘솔 + Biz Daemon + 계정 + 인터넷 + 기기당 유료**(트레이 아님, 로컬 전용 아님).
- **시도한 검색어(투명성)**:
  1. `Windows tray app monitor Android phone battery temperature CPU alert system tray ADB`
  2. `tray icon Windows monitor Android phone battery temperature notification alert multiple devices app`
  3. `"system tray" OR "taskbar" Windows app monitoring Android devices ADB history charts notifications`
  4. `"device monitor" Windows app multiple Android phones dashboard telemetry charts alerts ADB local`
  5. `Android fleet monitoring Windows desktop app telemetry` (변형 포함)
  6. `scrcpy GUI wrapper Windows scrcpy-gui guiscrcpy Fluent adb 2026 maintained`
  7. `OpenSTF DeviceFarmer dead 2026 device farm Windows adb-tui multi-device monitoring`
  8. `Samsung DeX for PC discontinued / Samsung Flow status` / `Samsung SideSync discontinued`
  9. `Vysor notification mirroring limitations no telemetry CPU temperature`
  10. `Windows equivalent of macOS menu bar device monitor` 계열 변형(직접 표현 검색)
- **미검증**: Windows Store에 "전화 배터리 트레이 위젯"류 소형 앱이 다수 존재할 가능성(검색 결과에 나타난 것 외). 또한 사내/중국계 폐쇄 도구(예: 일부 폰팜 하드닝 툴)는 공개 검색으로 확인 불가.

## 11. 통합 비교 표

| # | 앱 | 벤더 | 플랫폼 | 가격 | 상태(최신) | 핵심 | 없는 것(=우리 앱 대비) |
|---|---|---|---|---|---|---|---|
| 1 | Phone Link | Microsoft | Win 10/11 | 무료 | 2026 현역(1.25032+) | 알림/문자/통화/사진/파일/앱스트리밍(선별기기)/배터리%·연결 | 텔레메트리·차트·알림·logcat·앱별 트래픽 |
| 2 | Intel Unison | Intel | Win | (종료) | **EOL 2026-01-01** | 파일/문자/통화/화면확장(과거) | 서비스 종료 |
| 3 | MyPhoneExplorer | FJ Software | **Win 전용** + Android 클라이언트 | 프리웨어 | **2.3(2025-10-27)/클라 4.12(2026-06-09)** | SMS·연락처·일정 동기화, 파일/백업, 앱 관리, 화면 제어, 로컬 전용 | 텔레메트리·차트·알림·플릿 |
| 4 | Samsung Flow / DeX for PC / SideSync | Samsung | Win | 무료 | **Flow: Win11 비호환 / DeX for PC: One UI7+ 미지원 / SideSync: 2019 종료** | 알림·문자·파일·미러링·핫스팟 | 텔레메트리, macOS(DeX for Mac 2022 종료) |
| 5 | AirDroid(Personal/Cast/Business) | Sand Studio | Win/mac/웹/Android | $2.49~$3.99/월~; Business $12–33/기기·년 | 현역(©2026) | 파일·원격제어·알림·카메라·미러링; **Business: 배터리 온도·용량·스토리지·데이터·앱 트래픽 알림+워크플로** | 트레이 아님, 클라우드·계정·유료, CPU/스로틀/ANR·logcat·scrcpy·인시던트 없음 |
| 6 | Vysor | ClockworkMod | Win/mac/Linux/Browser | Pro $2.5/월·$10/년·$40 LT | 5.0.72(2026-08) | 미러링·제어·파일, **Pro: 프로세스·ADB 로그 조회**, 알림 미러링(3.2.x~) | 텔레메트리 차트·이력·알림·플릿 |
| 7 | QtScrcpy | barry-ran | Win/mac/Linux | 무료(Apache-2.0) | **v4.2.1(2026-08-13)** | 미러링·그룹 제어·파일/APK·키맵·오디오 | 텔레메트리·알림 |
| 7b | scrcpy GUI 래퍼들(scrcpy buddy·Scrcpy-GUI·simonaking·nexuls·guiscrcpy†) | 각 오픈소스 | Win(+mac/Linux) | 무료 | v1.0.6 / v1.7.5 / 2.4 / 신규 / **archived** | GUI·다중기기·무선·프로세스 감시 | 텔레메트리·알림 |
| 8 | ApowerMirror | Apowersoft | Win/mac/iOS/Android/TV | $19.95/월~ (상충 다수) | 현역 | 4대 동시 미러링·제어·녹화·AirCast | 텔레메트리·알림 |
| 8b | MirrorGo | Wondershare | Win | $19.95/월 | 현역 | 미러링·제어·파일·게임 키보드 | 동일 |
| 8c | Total Control | Sigma-RT | Win 7~11 | Lite 무료(1–2대)/Pro 티어 | 현역(안드로이드 6~16) | WDM·MDCC 다중 제어·자동화 | 동일 |
| 8d | Mobizen | RSUPPORT | Win/웹/Android | ~$4/월 | 현역 | 녹화·스트리밍·미러링·알림 보기 | 동일 |
| 8e | LetsView | (Apowersoft계) | Win/mac/iOS/Android/TV | 무료/Pro $7.99/월(+원격 분당) | 현역(Android 1.5.27, 2026-06-05) | 미러링·확장·원격 | 동일 |
| 8f | TeamViewer(QS/Host+add-on) | TeamViewer | Win/mac/Android | 개인 무료, 데스크톱→모바일 구독+MDS | 현역(15.82.x) | 원격 제어·파일·진단 정보 | 텔레메트리 추이·알림 |
| 9 | DeviceFarmer STF | 커뮤니티 | Linux/mac(**Win 미지원**) | 무료(셀프호스팅) | v3.7.9(2026-07-08) | 웹 팜·인벤토리·배터리 레벨/헬스 | Windows 지원 없음·트레이/알림/차트 없음 |
| 9b | ADB AppControl | (개인) | **Win 7~11** | 무료 + Extended **~$7** | 1.8.6(2025-07-15) | 앱 관리·디블로트·logcat·기기정보·scrcpy | 텔레메트리 추이·알림 |
| 9c | Panda | Some3C | Win/mac | **40대까지 무료**, 이후 구독 | 현역(©2026) | 최대 1,000대·썸네일·동기 입력·자동화 | 차트 이력·임계 알림·앱별 트래픽 |
| 9d | Adb-DECK | yuhnin-m | Win/mac/Linux | 무료 | 현역 | 13섹션 정보·**CPU/메모리 라이브 그래프**·알림 인스펙터 | 임계 알림·장기 이력·앱별 트래픽 |
| 9e | ADBOSS | pepperonas | Win/mac/Linux | 무료(PySide6) | v0.2.0(2026-03-01) | 배터리(온도)·RAM/스토리지·logcat·파일·BT HCI | 차트·이력·알림 |
| 9f | **JankMark** | AbiMangalan | **Win 전용(클로즈드 베타)** | 무료(미검증) | **v0.2.1-beta(2026-06-20)** | FPS/프레임타임·CPU/GPU/RAM·**CPU/GPU/배터리 온도**·클럭·세션 라이브러리 | 알림·플릿·트레이·앱별 트래픽 |
| 9g | **holo** | measure-sh | **Win 빌드 OSS** | 무료 | 현역 | **라이브 CPU/메모리/디스크/네트워크 스파크라인**·logcat·세션 이력·Perfetto·scrcpy | 트레이·알림·동시 다기기 |
| 9h | **DroidGauge** | RuizheGu0 | 크로스플랫폼 CLI | 무료 | 현역 | CPU/메모리/jank/**발열**/배터리·**앱별 네트워크**·HTML 리포트·**A/B·CI 게이트** | 실시간 알림·트레이·차트 UI |
| 9i | **adb-tui** | alanisme | Win/Linux/mac | 무료 | v0.1.0(2026-03-11) | 11뷰(성능 뷰=CPU/메모리/배터리) + **MCP 서버** | 차트 이력·알림·트레이 |
| 9j | Android Studio Profiler / **APA** | Google | Win(단독)/전 OS(APA) | 무료 | APA 오픈베타(2026-05-19) | CPU/메모리/네트워크/전력레일 심층 | debuggable 앱 전제·상시감시/알림/트레이 아님 |
| 9k | sxwik/Relay | (개인) | Win(Electron) | 무료로 보임(미검증) | 릴리스 없음 → **미검증** | 퍼포먼스 모니터·배터리 온도·알림 센터·기기 타임라인 | 유지보수·알림 임계·신뢰도 **미검증** |
| 10 | **BatteryBoi** | blueheron786 | Win 트레이 | 무료 | 릴리스 피드 없음 | **트레이에 안드로이드 배터리 %**(ADB) | 배터리 외 전부(차트·알림·다기기) |
| — | AndroidDeviceManager / ADB Studio / Droidective(정식) | 각 개인 | **macOS 전용** | 무료 | 2025-07 / SwiftUI / macOS 14+ | 메뉴바·ADB GUI | Windows 없음(Droidective는 Win/Linux 베타 실제 배포) |

† archived = 유지보수 종료.

## 12. Relay Console 관점 시사점
1. **차별화가 유지된다.** Windows 진영은 ①미러링(QtScrcpy/Vysor/Apower) ②ADB 툴박스(ADB AppControl/Adb-DECK) ③단일기기 프로파일러(JankMark/holo/DroidGauge) ④클라우드 MDM(AirDroid Business/AirDroid Business·Panda)로 파편화되어 있고, **"트레이 상주 + 다기기 + 심층 텔레메트리 + 임계 알림 + 로컬 전용"** 을 한 앱으로 묶은 곳이 없다.
2. **최대 위협은 AirDroid Business**. 텔레메트리 알림(배터리 온도·용량·스토리지·데이터·앱 트래픽)과 자동 워크플로를 이미 상용화했다. 다만 클라우드·계정·기기당 과금이고 UI가 웹 콘솔이라 "설치 0·서버 0 로컬 전용" 포지션과 정면 충돌하지 않는다.
3. **기술 관찰**: adb-tui는 MCP 서버 + 성능 뷰를, DroidGauge는 임계·회귀 게이트를, holo는 스파크라인 + 세션 이력을 이미 OSS로 제공한다 → 우리 앱의 개별 요소는 각각 존재하나 **결합(트레이 상주·다기기·알림 폭·ntfy/Slack·인시던트 번들)** 이 없어 조합 자체가 차별점.
4. **인접 시장 신호**: Windows 트레이 + ntfy 푸시(BTChargeTrayWatcher, ThermalWatch) 같은 패턴은 이미 통용 → Relay Console의 ntfy/Slack 채널 전략은 Windows 사용자에게도 이해되는 UX다.

## 13. 미검증 목록(요약)
- Vysor 알림 미러링의 Pro 전용 여부·2026 현행 유지.
- ApowerMirror 가격(출처 간 $19.95/월 vs $29.9/월 상충), MirrorGo 프로모션 가격.
- JankMark 가격/유료화 여부(README상 클로즈드 소스, 가격 표기 없음).
- MPhone 저장소 공개 상태(404)·배포 상태.
- sxwik/Relay의 유지보수·신뢰도(릴리스/이슈 데이터 없음).
- Droic의 Windows 동작(문서상 "expected to work").
- STF의 Cygwin 설치 가능성(문서상 "never tried").
- AirDroid Personal 무료 로컬 모드의 정확한 한계(파일 크기/기능 제한).
- Windows Store 내 소형 "폰 배터리 트레이 위젯"류의 전수 조사 불가.

---

## 14. 재검증 (2026-10-17 · `gh api` PAT 인증 · 5,000/h)

1차 조사는 익명 GitHub API(시간당 60회)로 수집해 레이트리밋(403) 때문에 별 수를 재확인하지 못했다. 인증 토큰으로 전수 재조회한 결과는 아래와 같으며, **본 문서의 작은 프로젝트들은 실제로 대부분 취미 규모**임이 확인됐다(반대로 Phone Link·Sefirah·AirDroid 같은 큰 항목의 서술은 유지된다).

| 저장소 | 별 | 최근 푸시 | 라이선스 | 비고 |
|---|---|---|---|---|
| Shrey113/Adb-Device-Manager-2 | **634** | 2026-08-28 | Apache-2.0 | Windows 트레이 + ADB/scrcpy 이중 모드(알림·통화·미디어·Audio Cast) — **텔레메트리 없음** |
| aman-senpai/AndroLaunch | **88** | 2026-10-02 | AGPL-3.0 | macOS 메뉴바(+Win/Linux) · **QR 무선 페어링** · 양방향 클립보드 |
| measure-sh/holo | **92** | 2026-04-29 | MIT | 터미널 UI · 성능·로그·ANR 트레이스 |
| Droidective/Droidective | **62** | **2026-10-17** | MIT | Swift 6·SwiftUI · 61툴 · 크래시 브라우저 · 라이브 성능 차트 · MCP · **Win/Linux 베타(29/32 뷰)** |
| yuhnin-m/Adb-DECK | 25 | 2026-03-27 | 없음 | ADB UI + 모니터 패널 |
| alanisme/adb-tui | **20** | 2026-03-11 | Apache-2.0 | TUI + MCP 서버 — **"주목할 도구"로 보기엔 규모가 작다(1차 서술 정정)** |
| RuizheGu0/droidgauge | **8** | 2026-08-25 | MIT | 앱별 네트워크·발열 HTML 리포트 + CI 게이트(실시간·알림 없음) |
| AbiMangalan/JankMark | **1** | 2026-06-23 | 없음 | FPS·프레임타임·하드웨어 텔레메트리(Windows 베타) — 사실상 개인 프로젝트 |
| Bloby22/andtls | 4 | 2026-08-30 | MIT | Go TUI + scrcpy |
| RobusTest / Panda / MPhone | — | — | — | RobusTest 블로그는 유효, **MPhone 저장소는 404**(비공개·삭제), Panda는 별도 벤더 |

**결론(변경 없음)**: Windows에도, macOS에도 **"트레이·메뉴바 상주 + 다기기 + 심층 텔레메트리 + 임계 알림 + 로컬 전용"** 을 한 제품에서 제공하는 앱은 **여전히 발견되지 않았다.** 단 macOS에서는 Droidective가 가장 근접하며(도구 폭·크래시 브라우저·성능 차트·메뉴바 상주·MCP), **임계 감시와 알림 채널이 없다**는 점이 우리 방어선이다.

**출처(재검증)**: https://api.github.com/repos/Droidective/Droidective · https://api.github.com/repos/aman-senpai/AndroLaunch · https://api.github.com/repos/Shrey113/Adb-Device-Manager-2 · https://api.github.com/repos/alanisme/adb-tui · https://api.github.com/repos/AbiMangalan/JankMark · https://api.github.com/repos/measure-sh/holo · https://api.github.com/repos/RuizheGu0/droidgauge
