
# Relay Console (릴레이 콘솔) - External Device Monitor
풀네임: Relay Console
약칭: Relay / 릴레이
버전: 1.0 (Mac 26+ / macOS Tahoe)

## 1. 한 줄 소개
All your devices, one console.
맥은 콘솔일 뿐, 감시 대상은 전부 외부.

## 2. 프로젝트 토대 (Origin Story)
Outpost로 시작된 이 프로젝트는 안드로이드 하나를 보는 뷰어였다.
SM_S901N ...5555 포트에 연결된 폰 하나, 배터리 - / 온도 - / 발열 주의 40.1°C 로그.
근데 문제는 폰을 만지지 않고도 맥에서 다 하고 싶다는 욕심이었다.

그래서 컨셉을 뒤집었다.
맥이 주인이 아니라, 맥은 그냥 관제 콘솔(Consol)일 뿐이다.
진짜 주인은 외부에 있다 - Droid, Apple, Sites, Jobs, Notify.
외부에서 신호가 오면 맥으로 릴레이(Relay)되는 구조.

그래서 이름은 Relay Console.

## 3. 앱 스토어 설명글 (App Store Description - KO)
Relay Console - 외부 기기 관제 콘솔

맥에서 폰을 만지지 마세요.
Relay Console은 당신의 모든 외부 기기를 하나의 메뉴바에서 관제합니다.

[주요 기능]
- Droid: Android 배터리, 온도, 쓰로틀링, 메모리 압박을 iStat Menus 스타일 그래프로 실시간 모니터링. 설정 변경 탐지(accelerometer_rotation) 및 logcat 키워드 트래킹.
- Apple: iPhone, AirPods 배터리 및 상태 (예정)
- Sites & Jobs: 배포 상태 및 백그라운드 작업 큐 (예정)
- 메뉴바 팝오버: 클릭 한 번으로 CPU 8코어, GPU, 네트워크 물결 확인. 발열 주의 42.3°C 시 즉시 알림 배너.
- 원클릭 액션: Scrcpy로 열기, 파일 드랍, 강제 종료

Scrcpy 유저를 위한 세컨드 앱, iStat Menus를 쓰는 맥 유저를 위한 필수 앱.

Mac 26+ Tahoe Liquid Glass 디자인, 라이트/다크 모드 완벽 지원, 화이트 메뉴바 템플릿 아이콘.

## 4. 앱 스토어 설명글 (EN)
Relay Console - External Device Monitor

Your Mac is just a console. Everything outside is the target.

Stop touching your phone. Monitor all your external devices from one menubar.

Features:
- Droid: Real-time CPU 8-core, GPU, memory pressure, battery health with iStat Menus style graphs. Detect settings changes and logcat keywords (accelerometer_rotation, wm_user_rotation_changed)
- Thermal timeline: Catch throttling at 40.1°C / 42.3°C before it kills performance
- MenuBar Popover: Compact iStat dashboard with alert banners, not just log lists
- One-click: Open in Scrcpy, force-stop, pull files

Built for developers who live in Mac, but work on Android.

Supports macOS 26+ Liquid Glass, light/dark mode, white template menubar icon.

## 5. 붙이는 설명 (Why Relay Console?)
- Outpost -> Relay Station 진화: 전초기지에서 중계 기지로
- 대표 명사 문제 해결: Relay 단독은 20개 중복, Relay Console은 유니크
- 확장성: Relay Console for Android, for Apple 자연스럽게 확장
- 발음: 릴레이 (계주 릴레이) - 외부에서 맥으로 바통을 넘긴다

## 6. 아이콘 가이드
- AppIcon: #0f111a 배경에 두 개의 블루 글로우 도트와 점선 릴레이 + 시그널 파동. 외부에서 내부로 신호가 온다는 의미
- MenuBar: 화이트 템플릿 아이콘 (MenuBarIcons/Black_Template). 다크모드에서는 화이트로, 라이트모드에서는 블랙으로 자동 변환
- Active 상태: 초록 점 + 릴레이 심볼

## 7. 포함 파일
- AppIcons/AppIcon_*.png (16~1024)
- MenuBarIcons/MenuBar_Black_Template_*.png (템플릿 - Xcode에 Template으로 설정)
- MenuBarIcons/MenuBar_White_*.png (프리뷰용)
