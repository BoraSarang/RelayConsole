import SwiftUI
import AppKit

struct DroidDashboardView: View {
    @ObservedObject var store: ConsoleStore
    /// 사이드바 알림(Alerts)으로 이동 — 탐지 타임라인 행 탭
    var onOpenAlerts: () -> Void = {}
    @Environment(\.openWindow) private var openWindow
    @State private var showProcessList = false
    @State private var showLogs = false
    @State private var showScreenshot = false
    @State private var showWifiOnboarding = false
    @State private var showAppHub = false
    @State private var showGallery = false
    @ObservedObject private var shots = ScreenshotService.shared
    @ObservedObject private var scrcpy = ScrcpyController.shared

    private var device: DeviceSnapshot? { store.selectedDevice }
    private var devices: [DeviceSnapshot] { store.inventory.devices }
    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }

    /// 토글 ON인 행 (행 안 전부 OFF면 그 행은 건너뜀)
    private var visibleRows: [[DashboardCard]] {
        DashboardCard.rows.compactMap { row in
            let visible = row.filter { store.cardEnabled($0) }
            return visible.isEmpty ? nil : visible
        }
    }

    /// 토글 ON인 전폭 카드
    private var visibleWideCards: [DashboardCard] {
        DashboardCard.wideCards.filter { store.cardEnabled($0) }
    }

    var body: some View {
        ZStack {
            OPColor.popBG.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    if device == nil {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else {
                        header
                        if let d = device, !d.isOnline {
                            offlineBanner(d)
                        }
                        // [표시②] 측정 실패(adb 무응답)는 오프라인과 **다른 상태**다.
                        // 기기가 연결돼 있어도 측정이 안 되면 값이 이전 정상값 그대로이므로
                        // 사용자가 알 수 없으면 "정상"으로 오해한다.
                        if let d = device, d.failureStreak > 0 {
                            staleBanner(d)
                        }
                        if let d = device, let err = d.lastError, !err.isEmpty {
                            lastErrorBanner(err)
                        }
                        if devices.count > 1 {
                            devicePicker
                        }
                        if let d = device, d.isThermalAlert {
                            thermalBanner(device: d)
                        }
                        // 1순위 — 오늘 요약 상단 전폭 (관제 진입 시 오늘 상태 먼저)
                        todaySummaryCard
                        dashboardGrid
                        // 2순위 — 설정 변경·logcat 탐지 타임라인 (하단)
                        detectionCard
                    }
                }
                .padding(OPSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .sheet(isPresented: $showProcessList) {
            ProcessListSheet(store: store)
        }
        .sheet(isPresented: $showLogs) {
            LogViewerSheet(store: store)
        }
        .sheet(isPresented: $showScreenshot) {
            if let d = device, !d.serial.isEmpty {
                ScreenshotPreviewSheet(serial: d.serial)
            }
        }
        .sheet(isPresented: $showAppHub) {
            if let d = device, !d.serial.isEmpty {
                AppHubSheet(serial: d.serial)
            }
        }
        .sheet(isPresented: $showGallery) {
            GallerySheet(serial: device?.serial)
        }
    }

    /// 앱 네트워크 사용량 독립 창 (네트워크 카드 더보기)
    private func openAppNetwork() {
        NSApp.activate(ignoringOtherApps: true)
        WindowFocus.dismissMenuBarPanels()
        openWindow(id: "appnetwork")
        WindowFocus.present(sceneID: "appnetwork")
    }

    // MARK: - Dashboard grid

    /// 2열 Grid + 전폭 카드 — 행 높이 동기화(바닥 정렬) · 순서 = `DashboardLayout` 단일 진실원처
    @ViewBuilder
    private var dashboardGrid: some View {
        if visibleRows.isEmpty && visibleWideCards.isEmpty {
            Text(L10n.string("cards.empty"))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(OPSpace.lg)
                .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                        .stroke(OPColor.border, lineWidth: 1)
                )
        } else {
            if !visibleRows.isEmpty {
                Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row, id: \.self) { card in
                                cardView(card, fillsRow: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                    }
                }
            }
            ForEach(visibleWideCards, id: \.self) { card in
                cardView(card, fillsRow: false)
            }
        }
    }

    @ViewBuilder
    private func cardView(_ card: DashboardCard, fillsRow: Bool) -> some View {
        switch card {
        case .cpu:
            DroidCards.cpu(device: device, metrics: metrics, fillsRow: fillsRow)
        case .thermal:
            DroidCards.thermal(device: device, metrics: metrics, fillsRow: fillsRow)
        case .memory:
            DroidCards.memory(device: device, metrics: metrics, fillsRow: fillsRow) {
                showProcessList = true
            }
        case .network:
            DroidCards.network(device: device, metrics: metrics, fillsRow: fillsRow) {
                openAppNetwork()
            }
        case .battery:
            DroidCards.battery(device: device, metrics: metrics, fillsRow: fillsRow)
        case .health:
            DroidCards.health(device: device, fillsRow: fillsRow)
        case .gpu:
            DroidCards.gpu(device: device, metrics: metrics, fillsRow: fillsRow)
        case .storage:
            DroidCards.storage(device: device, metrics: metrics, fillsRow: fillsRow)
        case .sensors:
            DroidCards.sensors(device: device, metrics: metrics, fillsRow: fillsRow)
        }
    }

    /// 오프라인 — 지표가 과거 스냅샷임을 명시 (AGENTS.local §4 [표시②])
    private func offlineBanner(_ d: DeviceSnapshot) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OPColor.bad)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("droid.offline.banner"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                if let at = d.lastSampleAt {
                    Text(L10n.format("droid.lastSample.at", Self.timeString(at)))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OPColor.bad.opacity(0.45), lineWidth: 1)
        )
    }

    /// 측정 실패 배너 — 기기는 연결돼 있으나 adb 응답이 없는 상태.
    /// 오프라인과는 **구분되는 별개 상태**로 표시한다([표시②] — 성공/실패/미측정 분리).
    private func staleBanner(_ d: DeviceSnapshot) -> some View {
        HStack(spacing: OPSpace.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("droid.stale.banner"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                HStack(spacing: 6) {
                    Text(L10n.format("droid.stale.count", d.failureStreak))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim)
                    if let at = d.lastSampleAt {
                        Text(L10n.format("droid.lastSample.at", Self.timeString(at)))
                            .font(OPFont.number(10))
                            .foregroundStyle(OPColor.inkDim)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OPColor.warn.opacity(0.45), lineWidth: 1)
        )
    }

    /// 수집 실패 원인 표시 — 원인 없는 일반 문구 대신 실제 에러 노출 (AGENTS.local §4 [표시②])
    private func lastErrorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OPColor.bad)
            Text(L10n.format("droid.lastError", text))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.bad)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OPColor.bad.opacity(0.45), lineWidth: 1)
        )
    }

    /// 탐지 타임라인 행마다 DateFormatter 를 새로 만들지 않는다 (생성 1회당 0.178ms 실측)
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func timeString(_ date: Date) -> String {
        timeFmt.string(from: date)
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(state: device?.isOnline == true ? .ok : .bad)
            Text(device?.displayName ?? L10n.na)
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
            if let kind = device?.connectionKind {
                Text(device?.connectionLabel ?? (kind == .usb ? L10n.string("menubar.device.usb") : L10n.string("menubar.device.network")))
                    .font(OPFont.number(10))
                    .foregroundStyle(kind == .network ? OPColor.cta : OPColor.inkDim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 4))
            }
            if let level = device?.batteryLevel {
                Text("\(level)%")
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.inkDim)
            }
            if let temp = device?.deviceTempC ?? device?.batteryTempC {
                Text(String(format: "%.1f°C", temp))
                    .font(OPFont.number(12))
                    .foregroundStyle(OPColor.thermal)
            }
            if let chip = DroidCards.healthChip(device) {
                Text(chip.0)
                    .font(OPFont.number(12))
                    .foregroundStyle(chip.1)
            }
            if let online = device?.isOnline {
                Text(online
                    ? L10n.string("menubar.status.connected")
                    : L10n.string("menubar.status.disconnected"))
                    .font(OPFont.body(12))
                    .foregroundStyle(online ? OPColor.ok : OPColor.bad)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let d = device, !d.serial.isEmpty {
                ScrcpyHeaderButton(serial: d.serial)
                WifiOnboardingHeaderButton(serial: d.serial, connectionKind: d.connectionKind)
                Button {
                    showAppHub = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.string("apphub.button"))
                            .font(OPFont.number(10))
                    }
                    .foregroundStyle(OPColor.cta)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OPColor.cta.opacity(0.35), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("apphub.button.help"))
                Button {
                    showGallery = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.string("gallery.button"))
                            .font(OPFont.number(10))
                    }
                    .foregroundStyle(OPColor.cta)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OPColor.cta.opacity(0.35), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("gallery.button.help"))
                Button {
                    showScreenshot = true
                } label: {
                    HStack(spacing: 3) {
                        if shots.loadingSerials.contains(d.serial) {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(L10n.string("scrcpy.thumb.title"))
                            .font(OPFont.number(10))
                    }
                    .foregroundStyle(OPColor.inkDim)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(OPColor.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OPColor.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("scrcpy.thumb.openHint"))
                Text(d.identLabel)
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var devicePicker: some View {
        HStack(spacing: 6) {
            Text(L10n.string("droid.header.picker"))
                .font(OPFont.body(10))
                .foregroundStyle(OPColor.inkDim)
            ForEach(devices, id: \.serial) { d in
                Button {
                    store.select(d.serial)
                } label: {
                    Text(d.displayName)
                        .font(OPFont.number(10))
                        .foregroundStyle(d.serial == store.selectedSerial ? .white : OPColor.inkDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(d.serial == store.selectedSerial
                                    ? OPColor.cta.opacity(0.25)
                                    : OPColor.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(d.serial == store.selectedSerial
                                    ? OPColor.cta
                                    : OPColor.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func thermalBanner(device d: DeviceSnapshot) -> some View {
        HStack(spacing: 8) {
            let temp = d.deviceTempC ?? d.batteryTempC
            Text("⚠ " + L10n.format(
                "menubar.alert.thermal",
                temp.map { String(format: "%.1f", $0) } ?? L10n.na
            ))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.thermal)
                .lineLimit(1)
                .truncationMode(.tail)
            if let s = d.thermalStatus, s >= 2 {
                Text("[\(L10n.string("menubar.alert.throttling"))]")
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.thermalSoft)
            }
            Spacer(minLength: 0)
            OPSparkline(
                points: metrics?.tempHistory ?? [],
                color: OPColor.thermal,
                height: 16
            )
            .frame(width: 100, height: 16)
        }
        .padding(OPSpace.md)
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

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("droid.empty.noDevice"))
                .font(OPFont.title(16))
                .foregroundStyle(OPColor.ink)
            Text(L10n.string("droid.empty.noDeviceBody"))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.inkDim)
                .multilineTextAlignment(.center)
            Text(L10n.string("droid.empty.noDeviceHint"))
                .font(OPFont.number(12))
                .foregroundStyle(OPColor.inkDim.opacity(0.85))
                .multilineTextAlignment(.center)
            Button(L10n.string("wifi.button.enable")) {
                showWifiOnboarding = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 6)
        }
        .padding(.horizontal, OPSpace.xl)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showWifiOnboarding) {
            WifiOnboardingSheet(presetSerial: nil, connectionKind: nil)
        }
    }

    // MARK: - Values

    /// 오늘 요약 카드 — 상단 전폭 KPI 바 (PLAN Phase3 표시 위치 C → 2026-09-25 상단 이동)
    private var todaySummaryCard: some View {
        Group {
            if let d = device {
                let dayKey = InsightLogic.dayKey(for: .now)
                let report = ReportLogic.dayOverDay(
                    events: store.recentWatchEvents,
                    dailies: Array(DeviceDailyStore.shared.map.values),
                    sessions: ConnectionSessionStore.shared.sessions,
                    dayKey: dayKey,
                    serial: d.serial,
                    thresholds: store.patternThresholds()
                )
                let daily = DeviceDailyStore.shared.day(serial: d.serial, dayKey: dayKey)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.string("droid.today.title"))
                            .font(OPFont.body(12))
                            .foregroundStyle(OPColor.ink)
                        Spacer()
                        Text(dayKey)
                            .font(OPFont.number(10))
                            .foregroundStyle(OPColor.inkDim)
                    }
                    HStack(spacing: 12) {
                        todayMetric(
                            L10n.string("insights.metric.critical"),
                            "\(report.criticalCount)",
                            report.criticalCount > 0 ? OPColor.bad : OPColor.ok
                        )
                        todayMetric(
                            L10n.string("insights.metric.crash"),
                            "\(report.crashCount)",
                            report.crashCount > 0 ? OPColor.bad : OPColor.ok
                        )
                        todayMetric(
                            L10n.string("insights.metric.temp"),
                            daily?.tempMax.map { String(format: "%.1f°", $0) } ?? L10n.na,
                            OPColor.thermal
                        )
                        todayMetric(
                            L10n.string("insights.pattern.repeating"),
                            "\(report.repeatingCount)",
                            report.repeatingCount > 0 ? OPColor.bad : OPColor.ok
                        )
                    }
                }
                .padding(OPSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                        .stroke(OPColor.border.opacity(0.5), lineWidth: 1)
                )
            }
        }
    }

    private func todayMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OPFont.number(9))
                .foregroundStyle(OPColor.inkDim)
            Text(value)
                .font(OPFont.number(13))
                .foregroundStyle(color)
        }
    }

    // MARK: - Detect (settings · logcat)

    /// 오늘 · 현재 기기의 탐지 이벤트 (신순)
    private var todayDetectEvents: [WatchEvent] {
        DetectLogic.today(events: store.recentWatchEvents, serial: device?.serial ?? "")
    }

    /// 탐지 카드 — 설정 변경·logcat을 구조화 이벤트 타임라인으로 표시
    /// (구버전 텍스트 카운터 대체 — 시각·원인 노출, 행 탭 → Alerts) (AGENTS.local §4 [표시②])
    private var detectionCard: some View {
        let events = todayDetectEvents
        let counts = DetectLogic.counts(events)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.string("droid.detect.title"))
                    .font(OPFont.body(12))
                    .foregroundStyle(OPColor.ink)
                Spacer(minLength: 8)
                detectCountChip(L10n.string("droid.detect.settings"), counts.settings, color: OPColor.thermal)
                detectCountChip(L10n.string("droid.detect.logcat"), counts.logcat, color: OPColor.cta)
                Button {
                    showLogs = true
                } label: {
                    Text(L10n.string("droid.detect.logs"))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.cta)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(OPColor.cta.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(OPColor.cta.opacity(0.35), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string("droid.logs.button"))
            }
            if events.isEmpty {
                Text(L10n.string("droid.detect.empty"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(events.prefix(DetectLogic.listLimit))) { e in
                        Button(action: onOpenAlerts) {
                            detectRow(e)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.string("sidebar.alerts"))
                    }
                }
            }
        }
        .padding(OPSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: OPSpace.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: OPSpace.radiusCard)
                .stroke(OPColor.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func detectCountChip(_ label: String, _ count: Int, color: Color) -> some View {
        Text("\(label) \(count)")
            .font(OPFont.number(10))
            .foregroundStyle(count > 0 ? color : OPColor.inkDim)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                (count > 0 ? color : OPColor.inkDim).opacity(count > 0 ? 0.14 : 0.06),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }

    private func detectRow(_ e: WatchEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeString(e.at))
                .font(OPFont.number(10))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 56, alignment: .leading)
            Image(systemName: e.kind == .settingsChanged ? "gearshape" : "terminal")
                .font(.system(size: 11))
                .foregroundStyle(e.kind == .settingsChanged ? OPColor.thermal : OPColor.cta)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !e.detail.isEmpty {
                    Text(e.detail)
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(OPColor.inkDim)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
