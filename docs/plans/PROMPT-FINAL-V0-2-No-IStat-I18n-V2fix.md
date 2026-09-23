# FINAL PROMPT v0.2 - Relay Console (No iStat, KO/EN i18n, Red Glitch Fix)

Bundle: com.borasarang.relayconsole / macOS 26.0 / App: Relay Console / MenuBar: RELAY

## Source
PLAN_v0.1_relayconsole.md FINAL + RESEARCH + SKILLPACK + BrandKit (AppIcon 1024 + MenuBar_Black_Template_22)

## Critical Rules (Must)
- bundleId com.borasarang.relayconsole ONLY. relay.* keys ONLY. outpost.* 0건. Outpost 라벨 0건.
- iStat / iStats / iStat Menus 문구 0건. Relay 고유 네이밍만.
- 6 cards ONLY: CPU MEMORY BATTERY NETWORK THERMAL STORAGE. GPU 제외.
- Scrcpy 버튼 없음. openWindow(id:"console") only.
- Thread: AdbClient static parser / DeviceMonitor actor bg (5s/10-15s) / DeviceInventory @MainActor Observable (UI는 inventory.devices만 읽음 P0-a) / DroidMetrics ring 60=5분
- Tokens: card #1c1f2a r16, popBG #0f111a, cta #2f6bff, thermal #ff8c32/#ffb86a, border white 8%, SF Mono. 2표면 .preferredColorScheme(.dark) 강제. Light 없음.
- Prohibitions: print 버튼 금지, .borderedProminent 기본 금지, 웹 링크 금지, dumpsys meminfo 상시 금지, …5555 masking.

## HOTFIX v2 - Red Scanline (image_795cd0.png) - SOLID BACKGROUND ONLY
Current bug: red/green horizontal lines on whole screen. Root cause: Liquid Glass / Material in macOS 26 Tahoe.
Fix: Remove ALL materials.

Grep MUST be 0:
- .ultraThinMaterial .thinMaterial .regularMaterial .thickMaterial .bar
- .glassEffect .visualEffect .backgroundStyle

Replace with SOLID.

App.swift:
```
@main struct RelayConsoleApp: App {
  init() { NSApp.appearance = NSAppearance(named: .darkAqua) }
  var body: some Scene {
    MenuBarExtra("Relay", image: "MenuBar") {
      ZStack { Color(hex: 0x0F111A).ignoresSafeArea(); MenuBarPopoverView() }
        .frame(width: 360).preferredColorScheme(.dark).background(Color(hex: 0x0F111A))
    }.menuBarExtraStyle(.window).windowResizability(.contentSize)
    WindowGroup(id: "console") {
      ZStack { Color(hex: 0x0F111A).ignoresSafeArea(); DroidDashboardView() }
        .preferredColorScheme(.dark).background(Color(hex: 0x0F111A))
    }.windowStyle(.hiddenTitleBar).defaultSize(width: 900, height: 700)
  }
}
```

Card:
```
RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x1C1F2A))
.overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
```

No .background(.material), no .glass, no blur, no opacity on card fill.

Asset: MenuBar Render As Template, Black_Template_22 only.

## i18n KO/EN
File: Resources/Localizable.xcstrings, source ko, localizations ko,en, CFBundleLocalizations ko,en
All Text via key: Text("menubar.alert.thermal") etc. Hardcoded 한글 0건.

Keys:
relay.menubar.label=RELAY (no translate)
menubar.status.connected=연결됨/Connected, disconnected=연결 끊김/Disconnected
menubar.alert.thermal=발열 주의 %@°C/Thermal Warning %@°C, throttling=스로틀링/Throttling
menubar.cpu.8core=CPU 8코어/CPU 8-Core
menubar.button.openConsole=◧ 콘솔 열기/◧ Open Console, debug=디버그/Debug
menubar.events.recent=최신 이벤트 (%d)/Recent Events (%d)
droid.header.title=Relay Console · 외부 관제 콘솔/Relay Console · External Console
droid.card.cpu/memory/battery/network/thermal/storage.title
droid.footer.settingsChanged=설정 변경 탐지 (%d)/Settings Changed (%d)
droid.footer.logcatHits=logcat 적중 (%d)/logcat Hits (%d)
droid.empty.noDevice=연결된 기기 없음/No Device Connected
common.na=—

LineLimit 1 + truncation for EN.

## Surface A Popover 360x≤560 Compact Monitor
Header RELAY ver [batt %] / SM_S901N …5555 ●연결됨 + expand
Alert ≥40°C or Status≥2: ⚠ 발열 주의 42.3°C [스로틀링] + spark orange
Grid: CPU 8코어 mini bar, MEMORY 7.2/12 + STORAGE 81/128, BATTERY big % + V/H/Cycle + spark, NETWORK up/down + LTE/Wi-Fi
Footer recent events 5 collapsed, buttons [◧ 콘솔 열기] cta + [디버그] secondary + [⚙]
Background SOLID #0f111a, NO rainbow/red.

## Surface B Dashboard 2col gap16
Header ● SM_S901N · 87% · 42.3°C · device · …5555
6 cards #1c1f2a r16: CPU mini bar+use%+temp+load spark, MEMORY bar+pressure+Top RSS, BATTERY big%+temp+spark+V/H/charging, NETWORK spark+LTE/Wi-Fi, THERMAL badge 0~6+zone mini bar orange, STORAGE bar+remain
Footer: 설정 변경 탐지 (n) + logcat (n) mono panel

## Parsers
parseThermal parseLoadAvg parseMemInfo parseCpuCores parseProcStat parseDf parseNetDev parseBatteryEx optional + — fallback

## DoD v0.2
- [ ] bundleId com.borasarang.relayconsole, RELAY label, relay.* only, Outpost 0, iStat 0
- [ ] AppIcon + MenuBar Black Template Template
- [ ] Popover 360 SOLID #0f111a, card #1c1f2a r16, SF Mono, red/green/rainbow 0 (image_02b893 + image_795cd0 fixed)
- [ ] grep Material 0, grep glassEffect 0
- [ ] CPU 8코어 mini bar, Battery - 없음 nil=—, …5555
- [ ] Scrcpy 없음, print 0, borderedProminent 기본 0
- [ ] Localizable.xcstrings ko/en 100%, 한글 하드코딩 0, ko/en 전환 깨짐 0
- [ ] swift test + SM_S901N 실기 + 팝오버/콘솔 캡처 정상
