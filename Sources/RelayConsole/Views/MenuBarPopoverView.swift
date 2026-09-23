import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store: ConsoleStore
    var openConsole: () -> Void
    var openDebug: () -> Void = {}

    @State private var showDeviceDetail = false
    @State private var showEvents = false

    private var devices: [DeviceSnapshot] { store.inventory.devices }
    private var device: DeviceSnapshot? { store.selectedDevice }
    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }
    private var multiDevice: Bool { devices.count > 1 }

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
                        if showDeviceDetail {
                            deviceExpandSection
                        }
                        if let d = device, d.isThermalAlert {
                            thermalBanner(device: d)
                        }
                        cards
                        deviceDetailSection
                        eventsSection
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
                if let d = device, let level = d.batteryLevel {
                    Text("\(level)%")
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.inkDim)
                }
                Text("0.3.0")
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
                } else {
                    Text(L10n.string("droid.empty.noDevice"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: 12) {
            cardFull(
                L10n.string("droid.card.cpu.title"),
                cpuValue,
                showBar: device?.cpuUsePercent,
                spark: metrics?.cpuHistory,
                sparkColor: OPColor.cta
            )
            if let cores = device?.coreFreqsMHz, !cores.isEmpty {
                coreMiniBars(freqs: cores, maxes: device?.coreMaxMHz ?? [], uses: device?.coreUsePercents ?? [])
            }
            HStack(spacing: 12) {
                cardMini(L10n.string("droid.card.memory.title"), memoryValue)
                cardMini(L10n.string("droid.card.storage.title"), storageValue)
            }
            if let top = device?.topProcesses, !top.isEmpty {
                topRssRows(top)
            }
            cardFull(
                L10n.string("droid.card.battery.title"),
                batteryValue,
                sub: batterySubline,
                spark: metrics?.levelHistory,
                sparkColor: OPColor.ok
            )
            batteryTiles
            networkUpRow
            networkDownRow
            cardFull(
                L10n.string("droid.card.network.title"),
                networkValue,
                sub: networkSubline,
                spark: metrics?.netHistory,
                sparkColor: OPColor.cta
            )
            cardFull(
                L10n.string("droid.card.thermal.title"),
                thermalValue,
                spark: metrics?.tempHistory,
                sparkColor: OPColor.thermal,
                isThermal: true
            )
            thermalZoneRows
        }
    }

    private func coreMiniBars(freqs: [Double], maxes: [Double], uses: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(freqs.enumerated()), id: \.offset) { i, freq in
                HStack(spacing: 6) {
                    Text("C\(i)")
                        .font(OPFont.number(8))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 16, alignment: .leading)
                    GeometryReader { geo in
                        let maxF = i < maxes.count && maxes[i] > 0 ? maxes[i] : max(freq, 1)
                        let ratio = min(1, max(0, freq / maxF))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OPColor.cta.opacity(0.7))
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 5)
                    Text(String(format: "%.2f", freq / 1000.0))
                        .font(OPFont.number(8))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 28, alignment: .trailing)
                    if i < uses.count {
                        Text(String(format: "%.0f%%", uses[i]))
                            .font(OPFont.number(8))
                            .foregroundStyle(OPColor.inkDim)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
            if let g = device?.cpuGovernor {
                Text(g)
                    .font(OPFont.number(8))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0x1C1F2A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func topRssRows(_ top: [ProcessRSS]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(top.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 6) {
                    Text(p.name)
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.ink.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(String(format: "%.0f MB", p.rssMB))
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
        }
        .padding(.horizontal, OPSpace.sm)
        .padding(.vertical, 4)
    }

    private var batteryTiles: some View {
        let d = device
        let cells: [(String, String)] = [
            (L10n.string("droid.battery.health"), d?.batteryHealthPct.map { "\($0)%" } ?? L10n.na),
            (L10n.string("droid.battery.voltage"), d?.voltageMV.map { String(format: "%.2fV", Double($0) / 1000) } ?? L10n.na),
            (L10n.string("droid.battery.cycles"), d?.cycleEstimate.map(String.init) ?? L10n.na),
            (L10n.string("droid.battery.current"), L10n.na),
            (L10n.string("droid.battery.type"), L10n.na),
            (L10n.string("menubar.device.detail"), (d?.isProtectionMode == true ? "ON" : L10n.na))
        ]
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 4),
            GridItem(.flexible(), spacing: 4),
            GridItem(.flexible(), spacing: 4)
        ], spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(spacing: 1) {
                    Text(cell.0)
                        .font(OPFont.number(7))
                        .foregroundStyle(OPColor.inkDim.opacity(0.7))
                        .lineLimit(1)
                    Text(cell.1)
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    private var networkUpRow: some View {
        HStack(spacing: 6) {
            Circle().fill(OPColor.cta).frame(width: 5, height: 5)
            Text(L10n.string("droid.card.network.up"))
                .font(OPFont.body(9))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            Text(device?.netUpMBps.map { String(format: "%.1f MB/s", $0) } ?? L10n.na)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
        }
    }

    private var networkDownRow: some View {
        HStack(spacing: 6) {
            Circle().fill(OPColor.thermalSoft).frame(width: 5, height: 5)
            Text(L10n.string("droid.card.network.down"))
                .font(OPFont.body(9))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            Text(device?.netDownMBps.map { String(format: "%.1f MB/s", $0) } ?? L10n.na)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.ink)
        }
    }

    private var thermalZoneRows: some View {
        Group {
            if let zones = device?.thermalZones, !zones.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(zones.prefix(6).enumerated()), id: \.offset) { _, z in
                        HStack(spacing: 6) {
                            Text(z.name)
                                .font(OPFont.number(9))
                                .foregroundStyle(OPColor.inkDim)
                                .frame(width: 56, alignment: .leading)
                            GeometryReader { geo in
                                let ratio = min(1, max(0, z.tempC / 80.0))
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.06))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(z.tempC >= 45 ? OPColor.thermal : OPColor.ok.opacity(0.7))
                                        .frame(width: geo.size.width * ratio)
                                }
                            }
                            .frame(height: 4)
                            Text(String(format: "%.1f°", z.tempC))
                                .font(OPFont.number(9))
                                .foregroundStyle(OPColor.ink)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Device detail (legacy path — multi uses expand section)

    private var deviceDetailSection: some View { EmptyView() }

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

    // MARK: - Events (접힘 기본 · 점3)

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
                if store.recentEvents.isEmpty {
                    Text(L10n.string("menubar.events.empty"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(store.recentEvents.prefix(5).enumerated()), id: \.offset) { _, e in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(OPColor.cta.opacity(0.7))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(e)
                                    .font(OPFont.body(11))
                                    .foregroundStyle(OPColor.ink)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.leading, 2)
                }
            }
        }
    }

    // MARK: - Footer (fixed)

    private var footer: some View {
        HStack(spacing: OPSpace.sm) {
            OPPrimaryButton(title: L10n.string("menubar.button.openConsole"), action: openConsole)
            OPSecondaryButton(title: L10n.string("menubar.button.debug"), action: openDebug)
            Spacer()
            SettingsLink {
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
        }
    }

    // MARK: - Values

    private var cpuValue: String {
        guard let d = device, let use = d.cpuUsePercent else { return L10n.na }
        var parts = ["\(L10n.string("menubar.cpu.8core"))", String(format: "%.0f%%", use)]
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.0f°C", t))
        }
        if let l = d.load1 {
            parts.append(String(format: "load %.2f", l))
        }
        return parts.joined(separator: " ")
    }

    private var memoryValue: String {
        guard let d = device,
              let used = d.memoryUsedGB,
              let total = d.memoryTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        var v = String(format: "%.1f/%.0f", used, total)
        if let label = d.memPressureLabel {
            v += " · " + L10n.format("droid.card.memory.pressure", label)
        }
        return v
    }

    private var storageValue: String {
        guard let d = device,
              let used = d.storageUsedGB,
              let total = d.storageTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        return String(format: "%.0f/%.0f", used, total)
    }

    private var batteryValue: String {
        guard let d = device, let level = d.batteryLevel else { return L10n.na }
        var parts = ["\(level)%"]
        if let t = d.batteryTempC {
            parts.append(String(format: "%.0f°C", t))
        }
        if d.isCharging == true {
            parts.append(L10n.string("droid.card.battery.charging"))
        }
        return parts.joined(separator: " ")
    }

    private var batterySubline: String? {
        guard let d = device else { return nil }
        var parts: [String] = []
        if let h = d.batteryHealthPct { parts.append("H \(h)%") }
        if let v = d.voltageMV {
            parts.append(String(format: "%.2fV", Double(v) / 1000.0))
        }
        if let c = d.cycleEstimate {
            parts.append(L10n.format("menubar.battery.cycle", c))
        }
        if d.isProtectionMode == true {
            var p = L10n.string("droid.card.battery.protection")
            if let th = d.protectionThresholdPct { p += " \(th)%" }
            parts.append(p)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var networkValue: String {
        guard let d = device else { return L10n.na }
        let up = d.netUpMBps.map { String(format: "↑%.1f", $0) } ?? "↑\(L10n.na)"
        let down = d.netDownMBps.map { String(format: "↓%.1f", $0) } ?? "↓\(L10n.na)"
        return "\(up) \(down) MB/s"
    }

    private var networkSubline: String? {
        guard let d = device else { return nil }
        var parts: [String] = []
        if let ssid = d.wifiSsid {
            parts.append(ssid)
            if let rssi = d.wifiRssi { parts.append("\(rssi) dBm") }
        } else if d.networkType == "Wi-Fi" {
            parts.append(L10n.string("droid.card.network.wifiOff"))
        } else if let op = d.signalOperator {
            parts.append(op)
            if let rsrp = d.rsrp { parts.append("RSRP \(rsrp)") }
        } else if let t = d.networkType {
            parts.append(t)
        }
        if let ip = d.ipV4 { parts.append(ip) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var thermalValue: String {
        guard let d = device else { return L10n.na }
        var parts: [String] = []
        if let s = d.thermalStatus { parts.append("Status \(s)") }
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.1f°C", t))
        }
        return parts.isEmpty ? L10n.na : parts.joined(separator: " ")
    }

    // MARK: - Card chrome

    private func cardFull(
        _ title: String,
        _ value: String,
        sub: String? = nil,
        showBar: Double? = nil,
        spark: [Double]? = nil,
        sparkColor: Color = OPColor.cta,
        isThermal: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OPFont.body(10))
                .foregroundStyle(isThermal ? OPColor.thermal : OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(OPFont.number(13))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
            if let sub {
                Text(sub)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
            }
            if let use = showBar {
                ProgressView(value: use, total: 100)
                    .progressViewStyle(.linear)
                    .tint(isThermal ? OPColor.thermal : OPColor.cta)
                    .frame(height: 3)
            }
            OPSparkline(
                points: spark ?? [],
                color: sparkColor,
                height: 14
            )
            .frame(height: 14)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0x1C1F2A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func cardMini(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(OPFont.number(13))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.md)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0x1C1F2A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
