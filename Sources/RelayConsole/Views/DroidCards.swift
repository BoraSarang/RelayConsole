import SwiftUI

/// Shared metric cards — Droid dashboard + menubar popover (same format)
enum DroidCards {
    /// 카드 내부 차트 슬롯 높이 — 전 카드 동일 (그래프 리듬 통일)
    static let chartHeight: CGFloat = 24

    static func shell(
        _ title: String,
        accent: Color = OPColor.inkDim,
        backgroundOpacity: Double = 1,
        trailing: AnyView? = nil,
        fillsRow: Bool = false,
        stale: StaleInfo? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let bgAlpha = min(max(backgroundOpacity, 0), 1)
        let card = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(OPFont.body(11))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if let stale {
                    // 배너를 읽지 않아도 "이 값이 언제 것인지" 보이게 한다
                    Text(L10n.format("droid.card.stale", stale.at.formatted(date: .omitted, time: .shortened)))
                        .font(OPFont.number(9))
                        .foregroundStyle(OPColor.warn)
                        .lineLimit(1)
                } else {
                    trailing
                }
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSpace.lg)
        return Group {
            // 같은 Grid 행의 카드 바닥까지 배경·테두리 확장 → 행 높이 동기화 (콘솔 대시보드만)
            if fillsRow {
                card.frame(maxHeight: .infinity, alignment: .top)
            } else {
                card
            }
        }
        // 배경·테두리만 투명도 반영 — 텍스트는 선명 유지 (TetherLens 동일)
        .background(
            OPColor.card.opacity(bgAlpha),
            in: RoundedRectangle(cornerRadius: OPSpace.radiusCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                .stroke(OPColor.border.opacity(0.5 * bgAlpha), lineWidth: 1)
        )
        // 오프라인이면 **읽히되 "지금" 이 아닌 것**으로 보이게 (2026-09-28)
        .opacity(stale == nil ? 1 : 0.45)
        .accessibilityLabel(stale == nil ? "" : L10n.string("droid.card.stale.hint"))
    }

    /// "이 값은 언제 것인가" — 오프라인일 때만 존재한다
    struct StaleInfo: Equatable {
        var at: Date
    }

    /// 기기가 오프라인이면 "마지막 측정" 정보를 만든다 — **모르면 nil**
    ///
    /// `measuredAt` 이 nil 이면(한 번도 측정하지 못함) 표시하지 않는다.
    /// "언젠지 모르는 값" 을 "오래된 값" 처럼 말하면 그것도 **거짓말**이다.
    static func staleInfo(for device: DeviceSnapshot?, now: Date = .now) -> StaleInfo? {
        guard let device, !device.isOnline else { return nil }
        guard let at = device.measuredAt, now > at else { return nil }
        return StaleInfo(at: at)
    }

    // MARK: - CPU

    static func cpu(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        backgroundOpacity: Double = 1,
        fillsRow: Bool = false
    ) -> some View {
        shell(
            L10n.string("droid.card.cpu.title"),
            accent: OPColor.inkDim,
            backgroundOpacity: backgroundOpacity,
            fillsRow: fillsRow,
            stale: staleInfo(for: device)
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
            OPSparkline(points: metrics?.cpuHistory ?? [], color: OPColor.cta, height: chartHeight)
                .frame(height: chartHeight)
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
        backgroundOpacity: Double = 1,
        fillsRow: Bool = false
    ) -> some View {
        shell(
            L10n.string("droid.card.gpu.title"),
            backgroundOpacity: backgroundOpacity,
            fillsRow: fillsRow,
            stale: staleInfo(for: device)
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
            OPSparkline(points: metrics?.gpuHistory ?? [], color: OPColor.cta, height: chartHeight)
                .frame(height: chartHeight)
        }
    }

    // MARK: - Memory

    static func memory(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        backgroundOpacity: Double = 1,
        fillsRow: Bool = false,
        onMore: (() -> Void)? = nil
    ) -> some View {
        shell(
            L10n.string("droid.card.memory.title"),
            backgroundOpacity: backgroundOpacity,
            fillsRow: fillsRow,
            stale: staleInfo(for: device)
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

    static func sensors(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        fillsRow: Bool = false
    ) -> some View {
        shell(L10n.string("droid.card.sensors.title"), fillsRow: fillsRow, stale: staleInfo(for: device)) {
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

    static func battery(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        fillsRow: Bool = false
    ) -> some View {
        shell(L10n.string("droid.card.battery.title"), fillsRow: fillsRow, stale: staleInfo(for: device)) {
            Text(batteryValue(device))
                .font(OPFont.number(16))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            batteryGrid(device)
            if let banner = neglectBanner(device) {
                Text(banner)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.thermalSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(OPColor.thermal.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(OPColor.thermal.opacity(0.3), lineWidth: 1)
                    )
            }
            OPSparkline(points: metrics?.levelHistory ?? [], color: OPColor.ok, height: chartHeight)
                .frame(height: chartHeight)
        }
    }

    /// 충전 방치 배너 — 온라인 + 방치 중일 때만 문구. 모르면 nil (0초는 모순)
    static func neglectBanner(_ device: DeviceSnapshot?) -> String? {
        guard let d = device, d.isOnline,
              let secs = d.neglectSeconds, secs > 0 else { return nil }
        return L10n.format("droid.card.battery.neglect", neglectDuration(secs))
    }

    /// 방치 지속 표기 — 0이 아닌 가장 큰 단위부터 (6시간 12분 · 45분 · 30초)
    static func neglectDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h > 0 { return L10n.format("droid.duration.hm", h, m) }
        if m > 0 { return L10n.format("droid.duration.min", m) }
        return L10n.format("droid.duration.sec", seconds)
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
        backgroundOpacity: Double = 1,
        fillsRow: Bool = false,
        onMore: (() -> Void)? = nil
    ) -> some View {
        let up = device?.netUpMBps
        let down = device?.netDownMBps
        let upFmt = up.map { AdbClient.formatNetRate($0) }
        let downFmt = down.map { AdbClient.formatNetRate($0) }
        return shell(
            L10n.string("droid.card.network.title"),
            backgroundOpacity: backgroundOpacity,
            trailing: AnyView(SignalGradeChip(device: device)),
            fillsRow: fillsRow,
            stale: staleInfo(for: device)
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
                    .minimumScaleFactor(0.9)
            }
            if let top = device?.appNetRates?.prefix(3), !top.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(top)) { r in
                        HStack(spacing: 6) {
                            Text(r.packageName ?? "uid \(r.uid)")
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.ink.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(AdbClient.formatNetRatePair(up: r.upMBps, down: r.downMBps))
                                .font(OPFont.number(10))
                                .foregroundStyle(OPColor.inkDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
            // 차트는 더보기 직전(카드 하단 고정) — 전 카드 위치·높이 규칙 통일
            OPDualSparkline(
                up: metrics?.netUpHistory ?? [],
                down: metrics?.netDownHistory ?? [],
                height: chartHeight
            )
            .frame(height: chartHeight)
            if let onMore {
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

    // MARK: - Thermal

    static func thermal(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        fillsRow: Bool = false
    ) -> some View {
        shell(
            L10n.string("droid.card.thermal.title"),
            accent: OPColor.thermal,
            fillsRow: fillsRow,
            stale: staleInfo(for: device)
        ) {
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
            OPSparkline(points: metrics?.tempHistory ?? [], color: OPColor.thermal, height: chartHeight)
                .frame(height: chartHeight)
        }
    }

    // MARK: - Storage

    static func storage(
        device: DeviceSnapshot?,
        metrics: DroidMetrics?,
        fillsRow: Bool = false
    ) -> some View {
        shell(L10n.string("droid.card.storage.title"), fillsRow: fillsRow, stale: staleInfo(for: device)) {
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
                OPDualSparkline(up: r, down: w, height: chartHeight)
                    .frame(height: chartHeight)
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

    static func health(device: DeviceSnapshot?, fillsRow: Bool = false) -> some View {
        shell(
            L10n.string("droid.card.health.title"),
            accent: OPColor.cta,
            fillsRow: fillsRow,
            stale: staleInfo(for: device)
        ) {
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

    private static func healthRow(label: String, value: Int?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 48, alignment: .leading)
            Group {
                if let value {
                    ProgressView(value: Double(value), total: 100)
                        .progressViewStyle(.linear)
                        .tint(bandColor(HealthScoreLogic.bandKey(total: value)))
                } else {
                    ProgressView(value: 0, total: 100)
                        .progressViewStyle(.linear)
                        .tint(OPColor.inkDim.opacity(0.4))
                }
            }
            Text(value.map(String.init) ?? L10n.na)
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

    /// 서브라인 1줄 (IP 제외 — 40자 예산)
    /// 셀룰러: `KT · LTE · RSRP -99 · RSRQ -12 · SINR 4`
    /// Wi-Fi : `<SSID> · Wi-Fi · RSSI -55 dBm`
    static func networkSubline(_ device: DeviceSnapshot?) -> String? {
        guard let d = device else { return nil }
        var parts: [String] = []
        if d.networkType == "Wi-Fi" {
            if let ssid = d.wifiSsid, !ssid.isEmpty {
                parts.append(ssid)
            } else {
                parts.append(L10n.string("droid.card.network.wifiOff"))
            }
            parts.append("Wi-Fi")
            if let rssi = d.wifiRssi { parts.append("RSSI \(rssi) dBm") }
        } else {
            if let op = d.signalOperator, !op.isEmpty { parts.append(op) }
            if let rat = d.signalRat, !rat.isEmpty { parts.append(rat) }
            if let v = d.rsrp { parts.append("RSRP \(v)") }
            if let v = d.rsrq { parts.append("RSRQ \(v)") }
            if let v = d.sinr { parts.append("SINR \(v)") }
        }
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
