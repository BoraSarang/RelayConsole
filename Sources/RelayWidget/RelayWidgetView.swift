import SwiftUI
import WidgetKit

/// 위젯 다크 토큰 — docs/DESIGN.md v2 카드와 동일 색 (팝오버·대시보드 다크 전용 규칙 승계)
enum WidgetTheme {
    static let card = Color(red: 0x1c / 255.0, green: 0x1f / 255.0, blue: 0x2a / 255.0) // #1c1f2a
    static let ink = Color(red: 0xEB / 255.0, green: 0xF0 / 255.0, blue: 0xFA / 255.0)
    static let inkDim = Color(red: 0x9E / 255.0, green: 0xAD / 255.0, blue: 0xC7 / 255.0)
    static let ok = Color(red: 0x33 / 255.0, green: 0xD9 / 255.0, blue: 0x73 / 255.0)
    static let warn = Color(red: 0xFF / 255.0, green: 0xB3 / 255.0, blue: 0x33 / 255.0)
    static let bad = Color(red: 0xFF / 255.0, green: 0x4D / 255.0, blue: 0x52 / 255.0)
    static let thermal = Color(red: 0xFF / 255.0, green: 0x8C / 255.0, blue: 0x32 / 255.0) // #ff8c32
    static let border = Color.white.opacity(0.08)

    static func toneColor(_ tone: WidgetSnapshot.Tone) -> Color {
        switch tone {
        case .ok: return ok
        case .warn: return warn
        case .bad: return bad
        }
    }

    static func severityColor(_ raw: String) -> Color {
        switch raw {
        case "critical": return bad
        case "warning": return warn
        default: return inkDim
        }
    }

    static func siteColor(_ state: WidgetSiteState) -> Color {
        switch state {
        case .up: return ok
        case .down: return bad
        case .unknown: return inkDim
        }
    }
}

struct RelayWidgetView: View {
    let entry: RelayWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.isEmpty {
                content(snapshot)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { WidgetTheme.card }
        .widgetURL(WidgetDeepLinkURL.console)
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .systemMedium: MediumView(snapshot: snapshot)
        case .systemLarge: LargeView(snapshot: snapshot)
        default: SmallView(snapshot: snapshot)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(WidgetTheme.inkDim).frame(width: 6, height: 6)
                Text(verbatim: "RELAY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetTheme.inkDim)
            }
            Spacer(minLength: 0)
            Text(verbatim: WidgetStrings.string("widget.empty"))
                .font(.system(size: 11))
                .foregroundStyle(WidgetTheme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// 딥링크 URL — WidgetDeepLink.scheme와 동일 유지
private enum WidgetDeepLinkURL {
    static let console = URL(string: "relayconsole://console")!
}

// MARK: - Small

private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(WidgetTheme.toneColor(snapshot.tone))
                    .frame(width: 6, height: 6)
                Text(verbatim: headerText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WidgetTheme.toneColor(snapshot.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }

            if let device = snapshot.devices.first {
                deviceBlock(device)
            } else if let site = snapshot.sites.first {
                siteBlock(site)
            }

            Spacer(minLength: 0)
            UpdatedFooter(updatedAt: snapshot.updatedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }

    private var headerText: String {
        if snapshot.critical > 0 {
            return WidgetStrings.format("widget.critical", "\(snapshot.critical)")
        }
        return WidgetStrings.string("widget.ok")
    }

    @ViewBuilder
    private func deviceBlock(_ device: WidgetDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: device.ident)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                if let pct = device.batteryPct {
                    Text(verbatim: "\(pct)%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(batteryColor(pct: pct, charging: device.charging ?? false))
                }
                if device.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WidgetTheme.ok)
                }
                if device.thermalAlert {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.thermal)
                }
                if !device.online {
                    Text(verbatim: WidgetStrings.string("widget.offline"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetTheme.inkDim)
                }
            }
        }
    }

    @ViewBuilder
    private func siteBlock(_ site: WidgetSite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: site.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 5) {
                Circle()
                    .fill(WidgetTheme.siteColor(site.state))
                    .frame(width: 7, height: 7)
                if let pct = site.uptime7dPct {
                    Text(verbatim: String(format: "%.1f%%", pct))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WidgetTheme.ink)
                }
            }
        }
    }

    private func batteryColor(pct: Int, charging: Bool) -> Color {
        if charging { return WidgetTheme.ok }
        if pct <= 20 { return WidgetTheme.bad }
        if pct <= 40 { return WidgetTheme.warn }
        return WidgetTheme.ink
    }
}

// MARK: - Medium

private struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Divider().overlay(WidgetTheme.border)
            HStack(alignment: .top, spacing: 10) {
                sitesColumn
                Divider().overlay(WidgetTheme.border)
                rightColumn
            }
            Spacer(minLength: 0)
            UpdatedFooter(updatedAt: snapshot.updatedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(WidgetTheme.toneColor(snapshot.tone))
                .frame(width: 6, height: 6)
            Text(verbatim: headerText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(WidgetTheme.toneColor(snapshot.tone))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if snapshot.critical > 0 {
                CriticalChip(count: snapshot.critical)
            }
        }
    }

    private var headerText: String {
        if let briefing = snapshot.briefing { return briefing }
        return WidgetStrings.format(
            "widget.summary",
            "\(snapshot.siteUp)",
            "\(snapshot.siteTotal)",
            "\(snapshot.jobsOverdue)"
        )
    }

    private var sitesColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.sites.isEmpty {
                Text(verbatim: WidgetStrings.string("widget.sites.none"))
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.inkDim)
            } else {
                ForEach(Array(snapshot.sites.prefix(4).enumerated()), id: \.offset) { _, site in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(WidgetTheme.siteColor(site.state))
                            .frame(width: 6, height: 6)
                        Text(verbatim: site.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let pct = site.uptime7dPct {
                            Text(verbatim: String(format: "%.1f%%", pct))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(WidgetTheme.inkDim)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            if snapshot.devices.isEmpty {
                Text(verbatim: WidgetStrings.string("widget.devices.none"))
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.inkDim)
                    .lineLimit(2)
            } else {
                ForEach(Array(snapshot.devices.prefix(2).enumerated()), id: \.offset) { _, device in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: device.ident)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 4) {
                            if let pct = device.batteryPct {
                                Text(verbatim: "\(pct)%")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(device.thermalAlert ? WidgetTheme.thermal : WidgetTheme.inkDim)
                            }
                            if device.charging == true {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(WidgetTheme.ok)
                            }
                            if device.thermalAlert {
                                Image(systemName: "thermometer.medium")
                                    .font(.system(size: 9))
                                    .foregroundStyle(WidgetTheme.thermal)
                            }
                            if !device.online {
                                Text(verbatim: WidgetStrings.string("widget.offline"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(WidgetTheme.inkDim)
                            }
                        }
                    }
                }
            }
            jobsLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var jobsLine: some View {
        if snapshot.jobsOverdue > 0 {
            Text(verbatim: WidgetStrings.format("widget.overdue", "\(snapshot.jobsOverdue)"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(WidgetTheme.warn)
        } else if snapshot.jobsTotal > 0 {
            Text(verbatim: WidgetStrings.string("widget.jobs.ok"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(WidgetTheme.ok)
        }
    }
}

// MARK: - Large

private struct LargeView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MediumHeader(snapshot: snapshot)
            Divider().overlay(WidgetTheme.border)
            section(title: WidgetStrings.string("widget.section.devices")) {
                if snapshot.devices.isEmpty {
                    emptyLine("widget.devices.none")
                } else {
                    ForEach(Array(snapshot.devices.prefix(3).enumerated()), id: \.offset) { _, device in
                        deviceRow(device)
                    }
                }
            }
            Divider().overlay(WidgetTheme.border)
            section(title: WidgetStrings.string("widget.section.sites")) {
                if snapshot.sites.isEmpty {
                    emptyLine("widget.sites.none")
                } else {
                    ForEach(Array(snapshot.sites.enumerated()), id: \.offset) { _, site in
                        siteRow(site)
                    }
                }
            }
            Divider().overlay(WidgetTheme.border)
            section(title: WidgetStrings.string("widget.section.events")) {
                if snapshot.events.isEmpty {
                    emptyLine("widget.events.none")
                } else {
                    ForEach(Array(snapshot.events.enumerated()), id: \.offset) { _, event in
                        eventRow(event)
                    }
                }
            }
            Spacer(minLength: 0)
            UpdatedFooter(updatedAt: snapshot.updatedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetTheme.inkDim)
            content()
        }
    }

    private func emptyLine(_ key: String) -> some View {
        Text(verbatim: WidgetStrings.string(key))
            .font(.system(size: 10))
            .foregroundStyle(WidgetTheme.inkDim)
    }

    private func deviceRow(_ device: WidgetDevice) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(device.online ? WidgetTheme.ok : WidgetTheme.inkDim)
                .frame(width: 6, height: 6)
            Text(verbatim: device.ident)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if device.thermalAlert {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.thermal)
            }
            if let pct = device.batteryPct {
                if device.charging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WidgetTheme.ok)
                }
                Text(verbatim: "\(pct)%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(batteryColor(pct: pct, charging: device.charging ?? false))
            }
            if !device.online {
                Text(verbatim: WidgetStrings.string("widget.offline"))
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.inkDim)
            }
        }
    }

    private func siteRow(_ site: WidgetSite) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(WidgetTheme.siteColor(site.state))
                .frame(width: 6, height: 6)
            Text(verbatim: site.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(verbatim: site.state == .down
                ? WidgetStrings.string("widget.sites.down")
                : (site.uptime7dPct.map { String(format: "%.1f%%", $0) } ?? "—"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(site.state == .down ? WidgetTheme.bad : WidgetTheme.inkDim)
        }
    }

    private func eventRow(_ event: WidgetEvent) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: WidgetStrings.clock(event.at))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(WidgetTheme.inkDim)
            Circle()
                .fill(WidgetTheme.severityColor(event.severity))
                .frame(width: 6, height: 6)
            Text(verbatim: event.title)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(verbatim: event.ident)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(WidgetTheme.inkDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func batteryColor(pct: Int, charging: Bool) -> Color {
        if charging { return WidgetTheme.ok }
        if pct <= 20 { return WidgetTheme.bad }
        if pct <= 40 { return WidgetTheme.warn }
        return WidgetTheme.ink
    }
}

// MARK: - 공용 조각

private struct MediumHeader: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(WidgetTheme.toneColor(snapshot.tone))
                .frame(width: 6, height: 6)
            Text(verbatim: headerText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(WidgetTheme.toneColor(snapshot.tone))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if snapshot.critical > 0 {
                CriticalChip(count: snapshot.critical)
            } else if snapshot.jobsOverdue > 0 {
                Text(verbatim: WidgetStrings.format("widget.overdue", "\(snapshot.jobsOverdue)"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WidgetTheme.warn)
            }
        }
    }

    private var headerText: String {
        if let briefing = snapshot.briefing { return briefing }
        return WidgetStrings.format(
            "widget.summary",
            "\(snapshot.siteUp)",
            "\(snapshot.siteTotal)",
            "\(snapshot.jobsOverdue)"
        )
    }
}

private struct CriticalChip: View {
    let count: Int

    var body: some View {
        Text(verbatim: WidgetStrings.format("widget.critical", "\(count)"))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(WidgetTheme.bad)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WidgetTheme.bad.opacity(0.15), in: Capsule())
    }
}

/// 마지막 업데이트 — 오프라인/이전 수치임을 반드시 명시 ([표시②])
private struct UpdatedFooter: View {
    let updatedAt: Date

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Image(systemName: "clock")
                .font(.system(size: 8))
            Text(verbatim: WidgetStrings.format("widget.updated", WidgetStrings.relative(updatedAt)))
                .font(.system(size: 9, design: .monospaced))
        }
        .foregroundStyle(WidgetTheme.inkDim.opacity(0.8))
    }
}

// MARK: - Widget 등록

struct RelayStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.widgetKind, provider: RelayWidgetProvider()) { entry in
            RelayWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
        }
        .configurationDisplayName(Text(verbatim: WidgetStrings.string("widget.name")))
        .description(Text(verbatim: WidgetStrings.string("widget.desc")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
