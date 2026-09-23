# Outpost - MiMo V2.6 Flash Skill Pack
## 외부 관제 콘솔 / iStat Menus for Android 전면 교체 스펙

이 문서를 MiMo V2.6 Flash에 그대로 붙여넣으면 메뉴바 v2 + 메인 Droid v2 UI를 뽑을 수 있음.

---

### 1. 프로젝트 개요
- 앱 이름: **Outpost · 외부 관제 콘솔**
- 컨셉: 맥에서 폰을 만지지 않고 모든 기기를 관제하는 Mission Control
- 핵심 교체: 기존 메뉴바의 텍스트 로그 리스트 (발열 주의 / 기기 연결됨 5줄)를 iStat Menus 스타일 대시보드로 전면 교체
- 타겟: macOS 14+ SwiftUI, MenuBarExtra

### 2. 정보 구조 (IA)
- Sidebar: Droid(선택됨), Apple, Sites, Jobs, Notify
- Droid 탭 = **메인 교체 대상**
  - 기존: SM_S901N 카드 (배터리 - / 온도 - / 충전 아니오 / 상태 device) + 설정 변경 탐지(0) + logcat 위치(0)
  - 신규: iStat 풀 대시보드
- MenuBar Popover = **전면 교체 대상**
  - 기존: Outpost / SM_S901N ...5555 / 최신 이벤트 리스트 (발열 주의 40.1°C, 42.3°C)
  - 신규: Compact iStat 대시보드

### 3. 디자인 시스템 (Design Tokens)
- Background: #0f111a (popover), #151821 (window), #1c1f2a (card)
- Border: rgba(255,255,255,0.08) / 1px
- Radius: 16px (card), 12px (banner), 20px (window)
- Font: SF Pro Display (UI), SF Mono (숫자)
- Green: #22c55e (connected), Orange: #f59e0b (발열 주의), Red: #ef4444 (42.3°C 이상)
- Shadow: 0 20px 80px rgba(0,0,0,0.6)
- Icon: SF Symbols

### 4. 데이터 소스 (MiMo가 UI에 넣을 목업 데이터 파싱 규칙)
```
adb shell dumpsys battery -> level, temperature(0.1°C 단위), voltage, health
adb shell dumpsys thermalservice -> skin, cpu, gpu, battery thermal
adb shell dumpsys cpuinfo -> load, per-process
adb shell dumpsys meminfo -> PSS, top consumers
adb shell dumpsys diskstats -> free/total
adb shell dumpsys notification -> 최신 이벤트
logcat 키워드: accelerometer_rotation, wm_user_rotation_changed, thermal
```

### 5. MenuBar v2 스펙 (image_04d830.png 교체)
- 크기: 360w x auto, rounded-2xl, dark
- Top: 
  - ● Outpost (green dot 10px)
  - SM_S901N ...5555 + 87% battery icon
- Alert Banner (기존 "발열 주의" 텍스트를 대체):
  - background: rgba(245,158,11,0.15), border orange
  - Text: "⚠ 발열 주의 42.3°C · 쓰로틀링 감지" + mini sparkline (2.3° 상승)
- iStat Grid Compact (4 cards, vertical stack):
  1. CPU: 8 cores horizontal bars (P cores 3.0GHz, E 2.0GHz), usage 34%, temp 42°C, tiny sparkline
  2. Memory/Storage: side-by-side - 7.2/12GB pressure bar, 81/128GB bar
  3. Battery: large - 40.1°C big number, 87%, health 94%, cycle 127, line chart 1h
  4. Network: Wi-Fi -42dBm, 5GHz, up 2.4MB/s down wave graph
- Timeline: "최신 이벤트 (5)" dots collapsed, not 5 rows
- Bottom: [콘솔 열기] primary #3b82f6 / [디버그] secondary #2a2a30

### 6. Main Window Droid v2 스펙 (image_a4a178.png 교체)
- Window: macOS traffic lights, title "Outpost · 외부 관제 콘솔", sidebar 220px #2a2a2e
- Sidebar selected: Droid (blue #3b82f6)
- Header: "Droid - SM_S901N • 87% • 33.2°C • device - :5555" + green connected dot + [Scrcpy로 열기] button
- Grid: 2 columns, 6 cards (gap 16):
  - CPU, GPU (Donut 34% + Adreno 740), Memory, Battery (gauge + history), Network (wave), Thermal+Storage
- Footer rows: 기존 "설정 변경 탐지 (0) - 감지된 변경 없음 — 자동회전·화면방향 감시 중" + "logcat 위치 (0) - 키워드 적중 없음" 유지 (muted #6b7280)

### 7. 인터랙션 플로우
1. MenuBar 아이콘 클릭 -> Compact iStat popover
2. SM_S901N row 클릭 -> Battery 상세 확장
3. Alert Banner 클릭 -> Main Window Droid Thermal 탭으로 이동
4. [콘솔 열기] -> Main Window open, Droid tab = Full iStat dashboard
5. [Scrcpy로 열기] -> `scrcpy --serial SM_S901N` 실행

### 8. MiMo V2.6 Flash에게 주는 최종 프롬프트 (복붙)

```
You are a macOS SwiftUI expert using MiMo V2.6 Flash omnimodal.

Task: Fully replace Outpost menubar and Droid tab with iStat Menus for Android style.

Reference images:
- /mnt/data/image_04d830.png = BEFORE menubar (text log list)
- /mnt/data/image_a4a178.png = BEFORE main Droid tab (simple card)
- Use previously generated iStat dashboard as AFTER target.

Requirements:
- SwiftUI MenuBarExtra, .windowStyle(.hiddenTitleBar), vibrancy
- No print button, no web style
- Dark premium, SF Mono numbers
- Use Design Tokens from Skill Pack section 3
- Implement Data Source section 4 as mock structs with realistic values
- MenuBar v2 must match section 5, Main Droid v2 must match section 6
- Interaction flow section 7

Output:
1. MenuBarPopoverView.swift
2. DroidDashboardView.swift
3. OutpostDesignTokens.swift

Keep it buildable in Xcode 15.
```

### 9. 체크리스트 (MiMo가 잘했는지 확인)
- [ ] 메뉴바가 360px 다크 팝오버인가?
- [ ] "발열 주의 42.3°C"가 배너로 승격됐는가?
- [ ] CPU 8코어 바가 있는가?
- [ ] Battery에 온도 그래프가 있는가?
- [ ] ...5555 포맷 유지하는가?
- [ ] [콘솔 열기]/[디버그] 버튼이 있는가?

---
Made for MiMo V2.6 Flash - efficiency model (310B total, 15B active) optimized for visual + coding.
