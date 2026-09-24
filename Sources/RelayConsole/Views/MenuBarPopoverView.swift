import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @ObservedObject var store: ConsoleStore
    var openConsole: () -> Void
    var openDebug: () -> Void = {}
    var openSettings: () -> Void = {}
    var openProcesses: () -> Void = {}
    var openLogs: () -> Void = {}

    @State private var showDeviceDetail = false
    @State private var showEvents = false
    @State private var showQuitConfirm = false
    /// 상단 감시 배너 TTL — 해제/충전 등 일회성 이벤트는 5분 후 자동 제거
    @State private var now = Date()
    @AppStorage("relay.menubarMetrics") private var menubarMetrics = true
    @AppStorage("relay.briefing.enabled") private var briefingEnabled = true

    /// 상단 배너 유지 시간 (초)
    private let topBannerTTL: TimeInterval = 300

    private var devices: [DeviceSnapshot] { store.inventory.devices }
    private var device: DeviceSnapshot? { store.selectedDevice }
    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }
    private var multiDevice: Bool { devices.count > 1 }
    /// 최신 5분 내 이벤트만 상단 배너 — 오래된 건 이력(최신 이벤트)에만 남김
    private var freshWatchEvent: WatchEvent? {
        store.recentWatchEvents.first { now.timeIntervalSince($0.at) < topBannerTTL }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            VStack(spacing: 0) {
                headerBlock
                    .padding(.horizontal, OPSpace.lg)
                    .padding(.top, OPSpace.lg)
                    .padding(.bottom, OPSpace.sm)
                    .background(Color(hex: 0x0F111A))

                Divider().overlay(OPColor.border)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 감시 이벤트 상단 배너 — 5분 TTL (해제·충전 등 일회성 자동 제거)
                        if let ev = freshWatchEvent {
                            watchEventBanner(ev)
                        }
                        if let d = device, d.isThermalAlert {
                            thermalBanner(device: d)
                        }
                        // 미해결 warning+ → 후속 조치 가이드
                        if !store.activeRemediationEvents.isEmpty {
                            remediationGuide(store.activeRemediationEvents)
                        }
                        // Sites 요약 (PLAN_sites_v1_1) — 기기 없어도 노출
                        if !store.sites.isEmpty {
                            sitesSection
                        }
                        if device == nil {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else if showDeviceDetail {
                            deviceExpandSection
                            cards
                            eventsSection
                        } else {
                            eventsSection
                            Spacer(minLength: 24)
                            detailHint
                            Spacer(minLength: 24)
                        }
                    }
                    .padding(OPSpace.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().overlay(OPColor.border)

                footer
                    .padding(.horizontal, OPSpace.lg)
                    .padding(.vertical, OPSpace.md)
                    .background(Color(hex: 0x0F111A))
            }
        }
        .frame(width: 360, height: 560)
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
        .onAppear {
            // LSUIElement — 팝오버 열림 시 앱 활성화 누락 → 다른 창이 뒤로 내려감
            WindowFocus.menuBarPopoverDidOpen()
        }
        .onDisappear {
            WindowFocus.menuBarPopoverDidClose()
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { t in
            now = t
        }
    }

    // MARK: - Header (fixed)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(state: device?.isOnline == true ? .ok : (device == nil ? .idle : .bad))
                Text(L10n.string("menubar.label"))
                    .font(OPFont.title(13))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if menubarMetrics && !devices.isEmpty {
                    Text("\(devices.filter(\.isOnline).count)/\(devices.count)")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                }
                if let d = device, let level = d.batteryLevel {
                    Text("\(level)%")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                if let d = device, let chip = DroidCards.healthChip(d) {
                    Text(chip.0)
                        .font(OPFont.number(11))
                        .foregroundStyle(chip.1)
                }
                Text("1.12.0")
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }

            HStack(spacing: 8) {
                if let d = device {
                    // 기기 이름 (deviceName > model)
                    Text(d.displayName)
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // 연결 종류: USB | IP:5555
                    connectionBadge(d)
                    StatusDot(state: d.isOnline ? .ok : .bad)
                    Text(d.isOnline
                        ? L10n.string("menubar.status.connected")
                        : L10n.string("menubar.status.disconnected"))
                        .font(OPFont.body(11))
                        .foregroundStyle(d.isOnline ? OPColor.ok : OPColor.bad)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ScrcpyHeaderButton(serial: d.serial)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDeviceDetail.toggle()
                        }
                    } label: {
                        Image(systemName: showDeviceDetail ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(OPColor.inkDim)
                            .frame(width: 20, height: 16)
                            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(multiDevice
                        ? L10n.string("menubar.device.list")
                        : L10n.string("menubar.device.detail"))
                }
            }

            if briefingEnabled {
                briefingLine
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 아침 브리핑 한 줄 — sites·jobs·폰·critical (PLAN_briefing · S1)
    private var briefingLine: some View {
        let snap = store.makeBriefing(now: now)
        let color: Color = {
            switch snap.tone {
            case .bad: return OPColor.bad
            case .warn: return OPColor.warn
            case .ok: return OPColor.ok
            }
        }()
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(L10n.format(
                "briefing.line",
                snap.upSites,
                snap.totalSites,
                snap.overdueJobs,
                snap.onlinePhones,
                snap.totalPhones,
                snap.activeCriticals
            ))
            .font(OPFont.number(10))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }

    private func connectionBadge(_ d: DeviceSnapshot) -> some View {
        Text(d.connectionLabel ?? L10n.na)
            .font(OPFont.number(9))
            .foregroundStyle(d.connectionKind == .network ? OPColor.cta : OPColor.inkDim)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(OPColor.card, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(OPColor.border, lineWidth: 1)
            )
    }

    // MARK: - Device list / detail expand

    /// 헤더 ⌄ 펼침 — 다중: 기기 목록 / 단일: 상세 3줄
    private var deviceExpandSection: some View {
        Group {
            if multiDevice {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("menubar.device.list"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                    ForEach(devices, id: \.serial) { d in
                        deviceRow(d)
                    }
                }
                .padding(OPSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(OPColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(OPColor.border, lineWidth: 1)
                )
            } else if let d = device {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("menubar.device.detail"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                    detailRow(L10n.string("menubar.device.model"), d.model.isEmpty ? L10n.na : d.model)
                    detailRow(
                        L10n.string("menubar.device.android"),
                        [d.androidVersion, d.sdkInt.map { "SDK \($0)" } ?? nil]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                            .isEmpty ? L10n.na
                            : [d.androidVersion, d.sdkInt.map { "SDK \($0)" } ?? nil]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                    )
                    detailRow(L10n.string("menubar.device.adb"), adbValue(d))
                }
                .padding(OPSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(OPColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(OPColor.border, lineWidth: 1)
                )
            }
        }
    }

    /// 기기 행 클릭 → 선택 + 콘솔 대시보드 (PLAN_v0.3)
    private func deviceRow(_ d: DeviceSnapshot) -> some View {
        let isSelected = d.serial == store.selectedSerial
        return Button {
            store.select(d.serial)
            openConsole()
        } label: {
            HStack(spacing: 8) {
                StatusDot(state: d.isOnline ? (isSelected ? .ok : .ok) : .bad)
                Text(d.displayName)
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(d.connectionLabel ?? L10n.na)
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let level = d.batteryLevel {
                    Text("\(level)%")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                if let t = d.deviceTempC ?? d.batteryTempC {
                    Text(String(format: "%.0f°", t))
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.thermal)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(OPColor.cta)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? OPColor.cta.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func adbValue(_ d: DeviceSnapshot) -> String {
        d.connectionKind == .network ? (d.connectionLabel ?? d.serial) : AdbClient.shortId(d.serial)
    }

    // MARK: - Watch event banner (상단 — thermalBanner와 동일 스타일)

    private func watchEventBanner(_ e: WatchEvent) -> some View {
        let accent: Color = e.isClear
            ? OPColor.ok
            : (e.severity == .critical ? OPColor.bad : (e.severity == .warning ? OPColor.warn : OPColor.cta))
        return HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(e.isClear ? "✓ " + e.title : "● " + e.title)
                .font(OPFont.body(11))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
            if !e.detail.isEmpty {
                Text(e.detail)
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Text(timeLabel(e.at))
                .font(OPFont.number(9))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { showEvents = true }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    // MARK: - Thermal banner

    private func thermalBanner(device d: DeviceSnapshot) -> some View {
        HStack(spacing: 6) {
            let temp = d.deviceTempC ?? d.batteryTempC
            Text("⚠ " + L10n.format(
                "menubar.alert.thermal",
                temp.map { String(format: "%.1f", $0) } ?? L10n.na
            ))
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.thermal)
                .lineLimit(1)
                .truncationMode(.tail)
            if let s = d.thermalStatus, s >= 2 {
                Text("[\(L10n.string("menubar.alert.throttling"))]")
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.thermalSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            OPSparkline(
                points: metrics?.tempHistory ?? [],
                color: OPColor.thermal,
                height: 14
            )
            .frame(width: 72, height: 14)
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OPColor.thermal.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OPColor.thermal.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { openConsole() }
    }

    // MARK: - Remediation guide (미해결 경고 → 후속 조치 체크리스트)

    private func remediationGuide(_ events: [WatchEvent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OPColor.warn)
                Text(L10n.string("remediation.title"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.warn)
            }
            ForEach(Array(Set(events.map(\.kind)).sorted(by: { $0.rawValue < $1.rawValue })), id: \.rawValue) { kind in
                VStack(alignment: .leading, spacing: 3) {
                    Text(remediationHeader(kind))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                    ForEach(remediationSteps(kind), id: \.self) { step in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(OPFont.body(11))
                                .foregroundStyle(OPColor.inkDim)
                            Text(step)
                                .font(OPFont.body(11))
                                .foregroundStyle(OPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OPColor.warn.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OPColor.warn.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { openConsole() }
    }

    private func remediationHeader(_ kind: WatchKind) -> String {
        switch kind {
        case .throttling: return L10n.string("remediation.throttling")
        case .protectionChanged: return L10n.string("remediation.protection")
        case .batteryThreshold: return L10n.string("remediation.battery")
        case .lowPowerChanged: return L10n.string("remediation.lowPower")
        case .psiPressure: return L10n.string("remediation.psi")
        case .loadSpike: return L10n.string("remediation.load")
        case .memoryLow: return L10n.string("remediation.memory")
        case .bsohDrop: return L10n.string("remediation.bsoh")
        case .signalDrop: return L10n.string("remediation.signal")
        case .anr: return L10n.string("remediation.anr")
        case .crash: return L10n.string("remediation.crash")
        default: return L10n.string("remediation.title")
        }
    }

    private func remediationSteps(_ kind: WatchKind) -> [String] {
        switch kind {
        case .throttling:
            return [
                L10n.string("remediation.throttle.1"),
                L10n.string("remediation.throttle.2"),
                L10n.string("remediation.throttle.3"),
                L10n.string("remediation.throttle.4"),
                L10n.string("remediation.throttle.5")
            ]
        case .protectionChanged:
            return [
                L10n.string("remediation.protection.1"),
                L10n.string("remediation.protection.2")
            ]
        case .batteryThreshold:
            return [
                L10n.string("remediation.battery.1"),
                L10n.string("remediation.battery.2"),
                L10n.string("remediation.battery.3")
            ]
        case .lowPowerChanged:
            return [
                L10n.string("remediation.lowPower.1"),
                L10n.string("remediation.lowPower.2")
            ]
        case .psiPressure:
            return [
                L10n.string("remediation.psi.1"),
                L10n.string("remediation.psi.2")
            ]
        case .loadSpike:
            return [
                L10n.string("remediation.load.1"),
                L10n.string("remediation.load.2")
            ]
        case .memoryLow:
            return [
                L10n.string("remediation.memory.1"),
                L10n.string("remediation.memory.2")
            ]
        case .bsohDrop:
            return [
                L10n.string("remediation.bsoh.1"),
                L10n.string("remediation.bsoh.2")
            ]
        case .signalDrop:
            return [
                L10n.string("remediation.signal.1"),
                L10n.string("remediation.signal.2")
            ]
        case .anr:
            return [
                L10n.string("remediation.anr.1"),
                L10n.string("remediation.anr.2"),
                L10n.string("remediation.anr.3")
            ]
        case .crash:
            return [
                L10n.string("remediation.crash.1"),
                L10n.string("remediation.crash.2"),
                L10n.string("remediation.crash.3")
            ]
        default:
            return []
        }
    }

    // MARK: - Detail hint (접힘 — 빈 영역 중앙, 탭하면 펼침)

    private var detailHint: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                showDeviceDetail = true
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(OPColor.inkDim.opacity(0.7))
                Text(L10n.string("menubar.device.detailHint"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    Text(L10n.string("menubar.device.detail"))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.cta)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(OPColor.cta)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSpace.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards (dashboard 동일 형식 — DroidCards 공유)

    private var cards: some View {
        VStack(spacing: 12) {
            // 플로팅 그래프 진입 (PLAN_floating_graphs)
            HStack {
                Spacer()
                Button {
                    FloatingGraphController.shared.toggle()
                } label: {
                    Label(
                        L10n.string("float.toggle"),
                        systemImage: "chart.xyaxis.line"
                    )
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.cta)
                    .frame(height: 28)
                    .padding(.horizontal, 10)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(OPColor.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(L10n.string("float.toggle.help"))
            }
            if store.cardCpu {
                DroidCards.cpu(device: device, metrics: metrics)
            }
            if store.cardGpu {
                DroidCards.gpu(device: device, metrics: metrics)
            }
            if store.cardMemory {
                DroidCards.memory(device: device, metrics: metrics) {
                    openProcesses()
                }
            }
            if store.cardSensors {
                DroidCards.sensors(device: device, metrics: metrics)
            }
            if store.cardBattery {
                DroidCards.battery(device: device, metrics: metrics)
            }
            if store.cardNetwork {
                DroidCards.network(device: device, metrics: metrics)
            }
            if store.cardThermal {
                DroidCards.thermal(device: device, metrics: metrics)
            }
            if store.cardStorage {
                DroidCards.storage(device: device, metrics: metrics)
            }
            if store.cardHealth {
                DroidCards.health(device: device)
            }
            if !store.cardCpu && !store.cardGpu && !store.cardMemory && !store.cardSensors
                && !store.cardBattery && !store.cardNetwork && !store.cardThermal && !store.cardStorage
                && !store.cardHealth {
                Text(L10n.string("cards.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Empty (연결된 기기 없음)

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("droid.empty.noDevice"))
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
            Text(L10n.string("droid.empty.noDeviceBody"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("droid.empty.noDeviceHint"))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, OPSpace.xl)
    }

    // MARK: - Detail rows

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
            Spacer(minLength: 8)
            Text(value)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Sites (PLAN_sites_v1_1 — UptimeRobot식 요약 · 7일 바)

    private var sitesSection: some View {
        let sites = store.sites.filter(\.enabled)
        let upCount = sites.filter { $0.effectiveUp() == true }.count
        let downCount = sites.filter { $0.effectiveUp() == false }.count
        let summaryColor: Color = downCount > 0 ? OPColor.bad : (upCount > 0 ? OPColor.ok : OPColor.inkDim)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(L10n.string("sidebar.sites"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
                Spacer()
                Text(L10n.format("sites.menubar.summary", upCount, downCount))
                    .font(OPFont.number(10))
                    .foregroundStyle(summaryColor)
            }
            ForEach(sites.prefix(5)) { site in
                siteMiniRow(site)
            }
            if sites.count > 5 {
                Text(L10n.format("sites.menubar.more", sites.count - 5))
                    .font(OPFont.body(9))
                    .foregroundStyle(OPColor.inkDim)
            }
            // Jobs overdue 한 줄 (모델 유지 · 폭오버에서만 합쳐 표시)
            let overdueJobs = store.jobs.filter { $0.enabled && $0.isOverdue() == true }
            if !overdueJobs.isEmpty {
                HStack(spacing: 6) {
                    StatusDot(state: .bad)
                    Text(L10n.format("jobs.menubar.overdue", overdueJobs.count))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.bad)
                    Spacer()
                }
            }
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
    }

    private func siteMiniRow(_ site: Site) -> some View {
        let up = site.effectiveUp()
        let state: StatusState = {
            switch up {
            case .some(true): return .ok
            case .some(false): return .bad
            case nil: return .idle
            }
        }()
        return HStack(spacing: 6) {
            StatusDot(state: state)
            Text(site.name)
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let up, let since = site.stateSince() {
                let dur = SitesView.relativeDuration(now.timeIntervalSince(since))
                Text(up
                    ? L10n.format("sites.state.up.for", dur)
                    : L10n.format("sites.state.down.for", dur))
                    .font(OPFont.number(9))
                    .foregroundStyle(up ? OPColor.inkDim : OPColor.bad)
            } else if let ms = site.history.last?.latencyMs, site.history.last?.ok == true {
                Text("\(ms)ms")
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
            }
            // 7일 미니 바
            HStack(spacing: 1) {
                ForEach(Array(site.dayBars(days: 7, now: now).enumerated()), id: \.offset) { _, b in
                    Rectangle()
                        .fill(miniBarColor(b.status))
                        .frame(width: 4, height: 8)
                }
            }
        }
    }

    private func miniBarColor(_ status: DayBarStatus) -> Color {
        switch status {
        case .up: return OPColor.ok.opacity(0.85)
        case .partial: return OPColor.warn.opacity(0.9)
        case .down: return OPColor.bad
        case .unknown: return OPColor.inkDim.opacity(0.18)
        }
    }

    // MARK: - Events (접힘 기본 · �점3)

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showEvents.toggle()
                }
            } label: {
                HStack {
                    Text(L10n.format("menubar.events.recent", min(store.recentEvents.count, 5)))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                    Spacer()
                    Image(systemName: showEvents ? "chevron.up" : "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
            .buttonStyle(.plain)

            if showEvents {
                if store.recentWatchEvents.isEmpty && store.recentEvents.isEmpty {
                    Text(L10n.string("menubar.events.empty"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                } else {
                    let fallback = store.recentEvents.prefix(5).map {
                        WatchRow(title: $0, detail: "", severity: .info, isClear: false)
                    }
                    let events = store.recentWatchEvents.isEmpty
                        ? fallback
                        : store.recentWatchEvents.prefix(5).map {
                            WatchRow(
                                title: $0.title,
                                detail: $0.detail,
                                severity: $0.severity,
                                isClear: $0.isClear
                            )
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(watchDotColor(e.severity).opacity(e.isClear ? 0.35 : 0.9))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.title)
                                        .font(OPFont.body(11))
                                        .foregroundStyle(
                                            e.severity == .critical
                                                ? OPColor.bad
                                                : (e.severity == .warning ? OPColor.warn : OPColor.ink)
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    if !e.detail.isEmpty {
                                        Text(e.detail)
                                            .font(OPFont.body(10))
                                            .foregroundStyle(OPColor.inkDim)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.leading, 2)
                }
            } else if let latest = store.recentWatchEvents.first {
                // 접힘 시 최신 1건만 — 주입 직후 육안 확인용
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(watchDotColor(latest.severity).opacity(latest.isClear ? 0.35 : 0.9))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(latest.title)
                            .font(OPFont.body(11))
                            .foregroundStyle(
                                latest.severity == .critical
                                    ? OPColor.bad
                                    : (latest.severity == .warning ? OPColor.warn : OPColor.ink)
                            )
                            .lineLimit(1)
                        if !latest.detail.isEmpty {
                            Text(latest.detail)
                                .font(OPFont.body(10))
                                .foregroundStyle(OPColor.inkDim)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 2)
            } else {
                Text(L10n.string("menubar.events.empty"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
            }
        }
    }

    private func watchDotColor(_ severity: WatchSeverity) -> Color {
        switch severity {
        case .critical: return OPColor.bad
        case .warning: return OPColor.warn
        case .info: return OPColor.cta
        }
    }

    private struct WatchRow: Equatable {
        let title: String
        let detail: String
        let severity: WatchSeverity
        let isClear: Bool
    }

    // MARK: - Footer (fixed)

    private var footer: some View {
        HStack(spacing: OPSpace.sm) {
            if device != nil {
                OPPrimaryButton(title: L10n.string("menubar.button.openConsole"), action: openConsole)
                OPSecondaryButton(title: L10n.string("droid.logs.button"), action: openLogs)
            }
            OPSecondaryButton(title: L10n.string("menubar.button.debug"), action: openDebug)
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(OPColor.inkDim)
                    .frame(width: 32, height: 32)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(OPColor.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.string("settings.section.general"))

            Button {
                showQuitConfirm = true
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OPColor.inkDim)
                    .frame(width: 32, height: 32)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(OPColor.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.string("menubar.button.quit"))
            .alert(
                L10n.string("menubar.quit.title"),
                isPresented: $showQuitConfirm
            ) {
                Button(L10n.string("menubar.quit.cancel"), role: .cancel) {}
                Button(L10n.string("menubar.quit.confirm"), role: .destructive) {
                    NSApp.terminate(nil)
                }
            } message: {
                Text(L10n.string("menubar.quit.body"))
            }
        }
    }
}
