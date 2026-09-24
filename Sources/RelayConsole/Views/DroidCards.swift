import SwiftUI

/// Shared metric cards — Droid dashboard + menubar popover (same format)
enum DroidCards {
    static func shell(
        _ title: String,
        accent: Color = OPColor.inkDim,
        backgroundOpacity: Double = 1,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let bgAlpha = min(max(backgroundOpacity, 0), 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPFont.body(11))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.lg)
        // 배경·테두리만 투명도 반영 — 텍스트는 선명 유지 (TetherLens 동일)
        .background(
            OPColor.card.opacity(bgAlpha),
            in: RoundedRectangle(cornerRadius: OPSpace.radiusCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                .stroke(OPColor.border.opacity(0.5 * bgAlpha), lineWidth: 1)
        )
    }

    // MARK: - CPU

    static func cpu(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        backgroundOpacity: Double = 1
    ) -> some View {
        shell(
            L10n.string("droid.card.cpu.title"),
            accent: OPColor.inkDim,
            backgroundOpacity: backgroundOpacity
        ) {
            Text(cpuValue(device))
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            if let use = device?.cpuUsePercent {
                ProgressView(value: use, total: 100)
                    .progressViewStyle(.linear)
                    .tint(OPColor.cta)
                    .frame(height: 4)
            }
            if let freqs = device?.coreFreqsMHz, !freqs.isEmpty {
                coreBars(freqs: freqs, maxes: device?.coreMaxMHz ?? [], uses: device?.coreUsePercents ?? [])
            }
            if let g = device?.cpuGovernor {
                Text(g)
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
            OPSparkline(points: metrics?.cpuHistory ?? [], color: OPColor.cta, height: 24)
                .frame(height: 24)
        }
    }

    static func coreBars(freqs: [Double], maxes: [Double], uses: [Double]) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(freqs.enumerated()), id: \.offset) { i, freq in
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let maxF = i < maxes.count && maxes[i] > 0 ? maxes[i] : max(freq, 1)
                        let ratio = CGFloat(min(1, max(0, freq / maxF)))
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .fill(OPColor.cta.opacity(0.75))
                                .frame(height: max(3, geo.size.height * ratio))
                        }
                    }
                    .frame(height: 28)
                    Text("C\(i)")
                        .font(OPFont.number(7))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
        }
        .frame(height: 40)
    }

    // MARK: - GPU

    static func gpu(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        backgroundOpacity: Double = 1
    ) -> some View {
        shell(
            L10n.string("droid.card.gpu.title"),
            backgroundOpacity: backgroundOpacity
        ) {
            Text(gpuValue(device))
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            if let renderer = device?.gpuRenderer {
                Text(renderer)
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let es = device?.gpuEsVersion {
                Text(L10n.format("droid.card.gpu.es", es))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
            }
            if let busy = device?.gpuUtilPercent {
                ProgressView(value: busy, total: 100)
                    .progressViewStyle(.linear)
                    .tint(OPColor.cta)
                    .frame(height: 4)
            }
            OPSparkline(points: metrics?.gpuHistory ?? [], color: OPColor.cta, height: 24)
                .frame(height: 24)
        }
    }

    // MARK: - Memory

    static func memory(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        backgroundOpacity: Double = 1,
        onMore: (() -> Void)? = nil
    ) -> some View {
        shell(
            L10n.string("droid.card.memory.title"),
            backgroundOpacity: backgroundOpacity
        ) {
            Text(memoryValue(device))
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let used = device?.memoryUsedGB, let total = device?.memoryTotalGB, total > 0 {
                ProgressView(value: used, total: total)
                    .progressViewStyle(.linear)
                    .tint(pressureColor(device))
                    .frame(height: 4)
                if let label = device?.memPressureLabel {
                    Text(L10n.format("droid.card.memory.pressure", label))
                        .font(OPFont.number(10))
                        .foregroundStyle(pressureColor(device))
                }
            }
            if let top = device?.topProcesses, !top.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.offset) { _, p in
                        HStack {
                            Text(p.name)
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.ink.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if let cpu = cpuPercent(for: p.name, in: device) {
                                Text(String(format: "%.1f%%", cpu))
                                    .font(OPFont.number(10))
                                    .foregroundStyle(OPColor.cta)
                            }
                            Text(String(format: "%.0f MB", p.rssMB))
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.inkDim)
                        }
                    }
                }
            }
            if let onMore, device?.processList?.isEmpty == false {
                Button(action: onMore) {
                    Text(L10n.string("droid.process.more"))
                        .font(OPFont.body(11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(OPColor.cta)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private static func cpuPercent(for name: String, in device: DeviceSnapshot?) -> Double? {
        device?.processList?.first { $0.name == name }?.cpuPercent
    }

    // MARK: - Sensors

    static func sensors(device: DeviceSnapshot?, metrics: DroidMetrics?) -> some View {
        shell(L10n.string("droid.card.sensors.title")) {
            Text(sensorsValue(device))
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
            if let active = device?.sensorActiveNames, !active.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(active.enumerated()), id: \.offset) { i, name in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(OPColor.ok)
                                .frame(width: 5, height: 5)
                            Text(name)
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            if let periods = device?.sensorActivePeriodsMs,
                               periods.indices.contains(i),
                               let ms = periods[i] {
                                Text(periodLabel(ms))
                                    .font(OPFont.number(9))
                                    .foregroundStyle(OPColor.inkDim)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                Text(L10n.string("droid.card.sensors.none"))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
    }

    static func periodLabel(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.1fs", ms / 1000)
        }
        if ms >= 1 {
            return String(format: "%.0fms", ms)
        }
        return String(format: "%.1fms", ms)
    }

    // MARK: - Battery

    static func battery(device: DeviceSnapshot?, metrics: DroidMetrics?) -> some View {
        shell(L10n.string("droid.card.battery.title")) {
            Text(batteryValue(device))
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            batteryGrid(device)
            OPSparkline(points: metrics?.levelHistory ?? [], color: OPColor.ok, height: 24)
                .frame(height: 24)
        }
    }

    static func batteryGrid(_ d: DeviceSnapshot?) -> some View {
        let cells: [(String, String)] = [
            (L10n.string("droid.battery.health"), d?.batteryHealthPct.map { "\($0)%" } ?? L10n.na),
            (L10n.string("droid.battery.voltage"), d?.voltageMV.map { String(format: "%.2fV", Double($0) / 1000) } ?? L10n.na),
            (L10n.string("droid.battery.cycles"), d?.cycleEstimate.map(String.init) ?? L10n.na),
            (L10n.string("droid.battery.temp"), d?.batteryTempC.map { String(format: "%.1f°C", $0) } ?? L10n.na),
            (L10n.string("droid.battery.current"), L10n.na),
            (L10n.string("droid.battery.type"), L10n.na)
        ]
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ], spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(spacing: 2) {
                    Text(cell.0)
                        .font(OPFont.number(8))
                        .foregroundStyle(OPColor.inkDim.opacity(0.75))
                        .lineLimit(1)
                    Text(cell.1)
                        .font(OPFont.number(12))
                        .foregroundStyle(OPColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
    }

    // MARK: - Network

    static func network(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        backgroundOpacity: Double = 1
    ) -> some View {
        let up = device?.netUpMBps
        let down = device?.netDownMBps
        let upFmt = up.map { AdbClient.formatNetRate($0) }
        let downFmt = down.map { AdbClient.formatNetRate($0) }
        return shell(
            L10n.string("droid.card.network.title"),
            backgroundOpacity: backgroundOpacity
        ) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("droid.card.network.up"))
                        .font(OPFont.body(9))
                        .foregroundStyle(OPColor.inkDim)
                    Text(upFmt?.value ?? L10n.na)
                        .font(OPFont.number(16))
                        .foregroundStyle(OPColor.cta)
                    Text(upFmt?.unit ?? " ")
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.inkDim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.string("droid.card.network.down"))
                        .font(OPFont.body(9))
                        .foregroundStyle(OPColor.inkDim)
                    Text(downFmt?.value ?? L10n.na)
                        .font(OPFont.number(16))
                        .foregroundStyle(OPColor.thermalSoft)
                    Text(downFmt?.unit ?? " ")
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
            if let sub = networkSubline(device) {
                Text(sub)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            OPSparkline(points: metrics?.netHistory ?? [], color: OPColor.cta, height: 24)
                .frame(height: 24)
        }
    }

    // MARK: - Thermal

    static func thermal(device: DeviceSnapshot?, metrics: DroidMetrics?) -> some View {
        shell(L10n.string("droid.card.thermal.title"), accent: OPColor.thermal) {
            HStack(spacing: 8) {
                Text(thermalValue(device))
                    .font(OPFont.number(16))
                    .foregroundStyle(OPColor.thermal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let s = device?.thermalStatus {
                    Text("\(s)")
                        .font(OPFont.number(14))
                        .foregroundStyle(thermalStatusColor(s))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(thermalStatusColor(s).opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(thermalStatusColor(s).opacity(0.4), lineWidth: 1)
                        )
                }
            }
            if let zones = device?.thermalZones, !zones.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(zones.prefix(8).enumerated()), id: \.offset) { _, z in
                        HStack(spacing: 6) {
                            Text(z.name)
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.inkDim)
                                .frame(width: 64, alignment: .leading)
                            GeometryReader { geo in
                                let ratio = CGFloat(min(1, max(0, z.tempC / 80.0)))
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.06))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(z.tempC >= 45 ? OPColor.thermal : OPColor.ok.opacity(0.7))
                                        .frame(width: geo.size.width * ratio)
                                }
                            }
                            .frame(height: 5)
                            Text(String(format: "%.1f°C", z.tempC))
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.ink)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            OPSparkline(points: metrics?.tempHistory ?? [], color: OPColor.thermal, height: 24)
                .frame(height: 24)
        }
    }

    // MARK: - Storage

    static func storage(device: DeviceSnapshot?, metrics: DroidMetrics?) -> some View {
        shell(L10n.string("droid.card.storage.title")) {
            Text(storageValue(device))
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let used = device?.storageUsedGB, let total = device?.storageTotalGB, total > 0 {
                ProgressView(value: used, total: total)
                    .progressViewStyle(.linear)
                    .tint(OPColor.cta)
                    .frame(height: 4)
                let remain = total - used
                Text(L10n.format(
                    "droid.storage.remain",
                    String(format: "%.0f GB", remain)
                ))
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
            }
            diskRWRow(device)
            if let r = metrics?.diskReadHistory, !r.isEmpty,
               let w = metrics?.diskWriteHistory, !w.isEmpty {
                HStack(spacing: 8) {
                    OPSparkline(points: r, color: OPColor.cta, height: 16)
                    OPSparkline(points: w, color: OPColor.thermalSoft, height: 16)
                }
                .frame(height: 16)
            }
        }
    }

    static func diskRWRow(_ device: DeviceSnapshot?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("droid.storage.read"))
                    .font(OPFont.body(9))
                    .foregroundStyle(OPColor.inkDim)
                Text(device?.diskReadMBps.map { String(format: "%.2f", $0) } ?? L10n.na)
                    .font(OPFont.number(14))
                    .foregroundStyle(OPColor.cta)
                Text("MB/s")
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(L10n.string("droid.storage.write"))
                    .font(OPFont.body(9))
                    .foregroundStyle(OPColor.inkDim)
                Text(device?.diskWriteMBps.map { String(format: "%.2f", $0) } ?? L10n.na)
                    .font(OPFont.number(14))
                    .foregroundStyle(OPColor.thermalSoft)
                Text("MB/s")
                    .font(OPFont.number(9))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
    }

    // MARK: - Health

    static func health(device: DeviceSnapshot?) -> some View {
        shell(L10n.string("droid.card.health.title"), accent: OPColor.cta) {
            if let s = HealthScoreLogic.score(from: device ?? DeviceSnapshot()) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(s.total)")
                        .font(OPFont.number(28))
                        .foregroundStyle(bandColor(s.bandKey))
                        .contentTransition(.numericText())
                    Text(L10n.string(s.bandKey))
                        .font(OPFont.body(12))
                        .foregroundStyle(bandColor(s.bandKey))
                    Spacer()
                }
                ProgressView(value: Double(s.total), total: 100)
                    .progressViewStyle(.linear)
                    .tint(bandColor(s.bandKey))
                    .frame(height: 4)
                healthRow(label: L10n.string("settings.cards.battery"), value: s.battery)
                healthRow(label: L10n.string("settings.cards.thermal"), value: s.thermal)
                healthRow(label: L10n.string("health.throttle"), value: s.throttle)
            } else {
                Text(L10n.na)
                    .font(OPFont.number(16))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
    }

    private static func healthRow(label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 48, alignment: .leading)
            ProgressView(value: Double(value), total: 100)
                .progressViewStyle(.linear)
                .tint(bandColor(HealthScoreLogic.bandKey(total: value)))
            Text("\(value)")
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 24, alignment: .trailing)
        }
    }

    static func bandColor(_ bandKey: String) -> Color {
        switch bandKey {
        case "health.band.good": return OPColor.ok
        case "health.band.fair": return OPColor.warn
        default: return OPColor.bad
        }
    }

    static func healthChip(_ snapshot: DeviceSnapshot?) -> (String, Color)? {
        guard let s = HealthScoreLogic.score(from: snapshot ?? DeviceSnapshot()) else { return nil }
        return ("\(L10n.string("droid.header.health")) \(s.total)", bandColor(s.bandKey))
    }

    // MARK: - Values

    static func cpuValue(_ device: DeviceSnapshot?) -> String {
        guard let d = device, let use = d.cpuUsePercent else { return L10n.na }
        var parts = [String(format: "%.0f%%", use)]
        if let t = d.deviceTempC ?? d.batteryTempC {
            parts.append(String(format: "%.0f°C", t))
        }
        if let l = d.load1 {
            parts.append(String(format: "load %.2f", l))
        }
        if let l5 = d.load5, let l15 = d.load15 {
            parts.append(String(format: "· %.2f %.2f", l5, l15))
        }
        return parts.joined(separator: " · ")
    }

    static func gpuValue(_ device: DeviceSnapshot?) -> String {
        guard let d = device else { return L10n.na }
        var parts: [String] = []
        if let busy = d.gpuUtilPercent {
            parts.append(L10n.format("droid.card.gpu.util", String(format: "%.0f", busy)))
        }
        if let mhz = d.gpuFreqMHz {
            parts.append(L10n.format("droid.card.gpu.freq", String(format: "%.0f", mhz)))
        }
        return parts.isEmpty ? L10n.na : parts.joined(separator: " · ")
    }

    static func memoryValue(_ device: DeviceSnapshot?) -> String {
        guard let d = device,
              let used = d.memoryUsedGB,
              let total = d.memoryTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        return String(format: "%.1f / %.0f GB", used, total)
    }

    static func sensorsValue(_ device: DeviceSnapshot?) -> String {
        guard let d = device else { return L10n.na }
        let active = d.sensorActiveCount.map(String.init) ?? L10n.na
        let total = d.sensorTotalCount.map(String.init) ?? L10n.na
        return L10n.format("droid.card.sensors.count", active, total)
    }

    static func storageValue(_ device: DeviceSnapshot?) -> String {
        guard let d = device,
              let used = d.storageUsedGB,
              let total = d.storageTotalGB else { return "\(L10n.na) / \(L10n.na)" }
        return String(format: "%.0f / %.0f GB", used, total)
    }

    static func batteryValue(_ device: DeviceSnapshot?) -> String {
        guard let d = device, let level = d.batteryLevel else { return L10n.na }
        var parts = ["\(level)%"]
        if let t = d.batteryTempC {
            parts.append(String(format: "%.1f°C", t))
        }
        if d.isCharging == true {
            parts.append(L10n.string("droid.card.battery.charging"))
        }
        return parts.joined(separator: " ")
    }

    static func thermalValue(_ device: DeviceSnapshot?) -> String {
        guard let d = device else { return L10n.na }
        if let t = d.deviceTempC ?? d.batteryTempC {
            return String(format: "%.1f°C", t)
        }
        return L10n.na
    }

    static func networkSubline(_ device: DeviceSnapshot?) -> String? {
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
        }
        if let ip = d.ipV4 { parts.append(ip) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func pressureColor(_ device: DeviceSnapshot?) -> Color {
        switch device?.memPressureLabel {
        case "none", nil: return OPColor.cta
        case "low": return OPColor.ok
        case "moderate": return OPColor.thermalSoft
        default: return OPColor.thermal
        }
    }

    static func thermalStatusColor(_ s: Int) -> Color {
        if s <= 1 { return OPColor.ok }
        if s == 2 { return OPColor.thermalSoft }
        return OPColor.thermal
    }
}
