import SwiftUI

struct DebugPanelView: View {
    @ObservedObject private var logger = DebugLogger.shared
    @ObservedObject private var store = ConsoleStore.shared

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.string("ui.debug.title"))
                        .font(OPFont.title(14))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button(L10n.string("ui.debug.clear")) { logger.clear() }
                        .buttonStyle(.plain)
                }
                .padding(OPSpace.md)
                Divider().overlay(OPColor.border)

                // 합성 감시 이벤트 주입 — DoD 육안 검증 (release 미사용)
                VStack(alignment: .leading, spacing: OPSpace.sm) {
                    Text(L10n.string("ui.debug.inject.title"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                        spacing: 6
                    ) {
                        injectButton(L10n.string("ui.debug.inject.throttleEnter")) {
                            store.debugInjectSynthetic(
                                kind: .throttling,
                                severity: .critical,
                                title: L10n.string("event.throttling.enter"),
                                detail: "DEBUG · Status 3"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.throttleClear")) {
                            store.debugInjectSynthetic(
                                kind: .throttling,
                                severity: .info,
                                title: L10n.string("event.throttling.clear"),
                                detail: "DEBUG · Status 1",
                                isClear: true,
                                resetCooldown: false
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.chargeOn")) {
                            store.debugInjectSynthetic(
                                kind: .chargeChanged,
                                severity: .info,
                                title: L10n.string("event.charge.start"),
                                detail: "DEBUG"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.protectionOn")) {
                            store.debugInjectSynthetic(
                                kind: .protectionChanged,
                                severity: .warning,
                                title: L10n.string("event.protection.on"),
                                detail: "DEBUG"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.protectionOff")) {
                            store.debugInjectSynthetic(
                                kind: .protectionChanged,
                                severity: .info,
                                title: L10n.string("event.protection.off"),
                                detail: "DEBUG",
                                isClear: true,
                                resetCooldown: false
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.lowPowerOn")) {
                            store.debugInjectSynthetic(
                                kind: .lowPowerChanged,
                                severity: .info,
                                title: L10n.string("event.lowPower.on"),
                                detail: "DEBUG"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.battery20")) {
                            store.debugInjectSynthetic(
                                kind: .batteryThreshold,
                                severity: .info,
                                title: L10n.format("event.battery.low", "20"),
                                detail: "DEBUG · 20%"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.psi")) {
                            store.debugInjectSynthetic(
                                kind: .psiPressure,
                                severity: .warning,
                                title: L10n.string("event.psi.enter"),
                                detail: "DEBUG · avg10=6.2"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.psiClear")) {
                            store.debugInjectSynthetic(
                                kind: .psiPressure,
                                severity: .info,
                                title: L10n.string("event.psi.clear"),
                                detail: "DEBUG · avg10=2.1",
                                isClear: true,
                                resetCooldown: false
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.load")) {
                            store.debugInjectSynthetic(
                                kind: .loadSpike,
                                severity: .warning,
                                title: L10n.string("event.load.enter"),
                                detail: "DEBUG · load1=17.2/8"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.mem")) {
                            store.debugInjectSynthetic(
                                kind: .memoryLow,
                                severity: .warning,
                                title: L10n.string("event.memory.enter"),
                                detail: "DEBUG · 93%"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.bsoh")) {
                            store.debugInjectSynthetic(
                                kind: .bsohDrop,
                                severity: .warning,
                                title: L10n.string("event.bsoh.drop"),
                                detail: "DEBUG · 91% → 85%"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.rsrp")) {
                            store.debugInjectSynthetic(
                                kind: .signalDrop,
                                severity: .warning,
                                title: L10n.string("event.signal.drop"),
                                detail: "DEBUG · -100 → -108 dBm"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.recovery")) {
                            store.debugInjectSynthetic(
                                kind: .throttling,
                                severity: .info,
                                title: L10n.string("event.throttling.clear"),
                                detail: "DEBUG · recovery",
                                isClear: true,
                                resetCooldown: false
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.badgeOff")) {
                            store.debugClearCriticalBadge()
                        }
                        injectButton(L10n.string("ui.debug.inject.anr")) {
                            store.debugInjectSynthetic(
                                kind: .anr,
                                severity: .critical,
                                title: L10n.string("event.anr.enter"),
                                detail: "DEBUG · ANR in com.example"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.crash")) {
                            store.debugInjectSynthetic(
                                kind: .crash,
                                severity: .critical,
                                title: L10n.string("event.crash.enter"),
                                detail: "DEBUG · FATAL EXCEPTION"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.appleOn")) {
                            store.debugInjectAppleOnline()
                        }
                        injectButton(L10n.string("ui.debug.inject.appleOff")) {
                            store.debugInjectAppleOffline()
                        }
                        injectButton(L10n.string("ui.debug.inject.appleErr")) {
                            store.debugInjectAppleError(.appleConnectFailed)
                        }
                        injectButton(L10n.string("ui.debug.inject.appleTools")) {
                            store.debugInjectAppleError(.appleBinaryMissing)
                        }
                        injectButton(L10n.string("ui.debug.inject.appleClear")) {
                            store.debugClearApple()
                        }
                        injectButton(L10n.string("ui.debug.inject.alertCritical")) {
                            store.debugInjectSynthetic(
                                kind: .loadSpike,
                                severity: .critical,
                                title: L10n.string("event.load.enter"),
                                detail: "DEBUG · Alerts active"
                            )
                        }
                        injectButton(L10n.string("ui.debug.inject.alertMute")) {
                            let serial = store.selectedSerial ?? "DEBUG-SERIAL"
                            let event = WatchEvent(
                                kind: .psiPressure,
                                severity: .warning,
                                serial: serial,
                                title: L10n.string("event.psi.enter"),
                                detail: "DEBUG · will mute"
                            )
                            store.debugIngestWatchQuietly(event)
                            store.muteWatchEvent(id: event.id, until: .now.addingTimeInterval(3600))
                        }
                        injectButton(L10n.string("ui.debug.inject.alertClear")) {
                            store.debugInjectSynthetic(
                                kind: .loadSpike,
                                severity: .info,
                                title: L10n.string("event.load.clear"),
                                detail: "DEBUG · Alerts cleared",
                                isClear: true,
                                resetCooldown: false
                            )
                        }
                    }
                    Text(L10n.string("ui.debug.inject.hint"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(2)
                }
                .padding(OPSpace.md)
                Divider().overlay(OPColor.border)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logger.logs.reversed()) { entry in
                            Text("[\(entry.timestamp)] [\(entry.level.rawValue)] [\(entry.platform)] [\(entry.category)] \(entry.message)")
                                .font(OPFont.number(11))
                                .foregroundStyle(entry.level == .error ? OPColor.bad : OPColor.inkDim)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(OPSpace.sm)
                }
            }
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }

    private func injectButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OPFont.body(11))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
