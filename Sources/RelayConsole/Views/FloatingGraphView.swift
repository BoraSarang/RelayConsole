import SwiftUI

/// 플로팅 그래프 본체 — **한 창 = 한 지표** (네트워크/CPU/GPU/MEMORY)
/// borderless NSPanel(.nonactivating) 안에서 호스팅 (FloatingGraphController가 창 id별로 소유)
struct FloatingGraphView: View {
    @ObservedObject var store: ConsoleStore
    /// 이 창이 표시할 (지표, 기기, 위치) — 변경 시 컨트롤러가 호스팅을 교체
    let win: FloatingGraphLogic.FloatWin
    var onOpenProcesses: () -> Void = {}
    var onOpenAppNetwork: () -> Void = {}
    var onOpenConsole: () -> Void = {}

    @ObservedObject private var float = FloatingGraphController.shared
    @AppStorage(FloatingGraphLogic.opacityKey) private var opacity = FloatingGraphLogic.defaultOpacity

    @State private var isHovering = false
    @State private var showOpacityPopover = false

    private static let corner: CGFloat = 12
    private static let width: CGFloat = 300
    /// 헤더 우측 고정 슬롯 — hover 시 opacity만 변화 (삽입/삭제로 인한 출렁임 방지)
    /// dashboard(22) + scrcpy(≈90) + menu/opacity/close(22×3) + spacing(4×5)
    private static let trailingSlotWidth: CGFloat = 200

    /// 이 창의 기기 — serial이 비었거나 기기가 사라졌으면 전역 선택으로 폴백
    private var device: DeviceSnapshot? {
        if let d = store.inventory.devices.first(where: { $0.serial == win.serial }) {
            return d
        }
        return store.selectedDevice
    }

    private var devices: [DeviceSnapshot] { store.inventory.devices }

    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }

    private var serialForChild: String { device?.serial ?? win.serial }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider().overlay(OPColor.border).padding(.horizontal, 12).padding(.vertical, 6)

            if device == nil {
                emptyHint
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                card
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: Self.width)
        .background(
            // 블러(뒤 내용 흐림) + 브랜드 틴트 — 텍스트는 항상 불투명
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(FloatingGraphLogic.clampOpacity(opacity))
        )
        .background(
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(OPColor.popBG)
                .opacity(FloatingGraphLogic.clampOpacity(opacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .stroke(isHovering ? OPColor.border : Color.clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    /// 한 창에 지표 1개만 — 높이가 카드 1장으로 고정되어 화면 가림 최소
    @ViewBuilder
    private var card: some View {
        let bg = FloatingGraphLogic.clampOpacity(opacity)
        switch win.metric {
        case .network:
            DroidCards.network(
                device: device,
                metrics: metrics,
                backgroundOpacity: bg,
                onMore: { onOpenAppNetwork() }
            )
            .environment(\.dynamicTypeSize, .xSmall)
        case .cpu:
            DroidCards.cpu(
                device: device,
                metrics: metrics,
                backgroundOpacity: bg
            )
        case .gpu:
            DroidCards.gpu(
                device: device,
                metrics: metrics,
                backgroundOpacity: bg
            )
        case .memory:
            DroidCards.memory(
                device: device,
                metrics: metrics,
                backgroundOpacity: bg,
                onMore: { onOpenProcesses() }
            )
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(device?.isOnline == true ? OPColor.ok : OPColor.inkDim)
                .frame(width: 7, height: 7)
            if devices.count > 1 {
                devicePicker
            } else {
                Text(device?.displayName ?? L10n.string("float.noDevice"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            // 항상 레이아웃 점유 — 메뉴/닫기 아이콘이 생겨도 헤더 폭·높이 고정
            HStack(spacing: 4) {
                // 대시보드(콘솔) 창 열기 — 플로팅에서 전체 화면으로 전환
                Button {
                    onOpenConsole()
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 11))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(L10n.string("float.console"))

                // 창 추가 · 지표 전환 · 정렬 — Menu 안 Slider는 macOS에서 깨짐(투명도는 전용 팝오버)
                Menu {
                    Menu(L10n.string("float.add")) {
                        ForEach(FloatingGraphLogic.Metric.allCases, id: \.self) { m in
                            Button(L10n.string(m.l10nKey)) {
                                FloatingGraphController.shared.openWindow(
                                    metric: m, serial: serialForChild
                                )
                            }
                            .disabled(float.isAtCapacity)
                        }
                    }
                    Menu(L10n.string("float.switch")) {
                        ForEach(FloatingGraphLogic.Metric.allCases, id: \.self) { m in
                            Button {
                                FloatingGraphController.shared.setMetric(id: win.id, metric: m)
                            } label: {
                                if m == win.metric {
                                    Label(L10n.string(m.l10nKey), systemImage: "checkmark")
                                } else {
                                    Text(L10n.string(m.l10nKey))
                                }
                            }
                            .disabled(m == win.metric)
                        }
                    }
                    Button(L10n.string("float.arrange")) {
                        FloatingGraphController.shared.arrange()
                    }
                    .disabled(float.wins.count < 2)
                    if float.isAtCapacity {
                        Text(L10n.string("float.limit"))
                            .font(OPFont.body(10))
                    }
                    Divider()
                    Button(L10n.string("float.processes")) { onOpenProcesses() }
                    Button(L10n.string("float.appnet")) { onOpenAppNetwork() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 22, height: 22)
                .help(L10n.string("float.menu.help"))

                Button {
                    showOpacityPopover = true
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(L10n.string("float.opacity.help"))
                .popover(isPresented: $showOpacityPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("float.opacity"))
                            .font(OPFont.body(11))
                            .foregroundStyle(OPColor.ink)
                        Slider(value: $opacity, in: FloatingGraphLogic.minOpacity...FloatingGraphLogic.maxOpacity)
                            .frame(width: 160)
                        Text("\(Int(FloatingGraphLogic.clampOpacity(opacity) * 100))%")
                            .font(OPFont.number(11))
                            .foregroundStyle(OPColor.inkDim)
                    }
                    .padding(12)
                    .frame(width: 184)
                    .background(OPColor.popBG)
                    .preferredColorScheme(ThemeManager.shared.mode.preferred)
                }

                if let d = device, !d.serial.isEmpty {
                    ScrcpyHeaderButton(serial: d.serial)
                }

                Button {
                    FloatingGraphController.shared.closeWindow(id: win.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OPColor.inkDim)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(L10n.string("float.close"))
            }
            .frame(width: Self.trailingSlotWidth, alignment: .trailing)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 2)
        // 헤더 높이 고정 — hover/menu 오픈 시 출렁임 방지
        .frame(height: 34)
    }

    /// 다중 기기 — **이 창 전용** 기기 지정 (전역 선택은 건드리지 않음)
    private var devicePicker: some View {
        Menu {
            ForEach(devices, id: \.serial) { d in
                Button {
                    FloatingGraphController.shared.setSerial(id: win.id, serial: d.serial)
                } label: {
                    Label(d.displayName, systemImage: d.isOnline ? "iphone" : "iphone.slash")
                }
            }
        } label: {
            Text(device?.displayName ?? L10n.string("float.noDevice"))
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(OPColor.inkDim)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.string("droid.header.picker"))
    }

    private var emptyHint: some View {
        Text(L10n.string("float.empty"))
            .font(OPFont.body(11))
            .foregroundStyle(OPColor.inkDim)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }
}
