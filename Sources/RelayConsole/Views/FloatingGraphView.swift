import SwiftUI

/// 플로팅 그래프 본체 — Network(고정) + CPU/GPU/Memory 토글
/// borderless NSPanel(.nonactivating) 안에서 호스팅 (FloatingGraphController 소유)
struct FloatingGraphView: View {
    @ObservedObject var store: ConsoleStore
    var onOpenProcesses: () -> Void = {}

    @AppStorage("relay.float.showNetwork") private var showNetwork = true
    @AppStorage("relay.float.showCPU") private var showCPU = true
    @AppStorage("relay.float.showGPU") private var showGPU = false
    @AppStorage("relay.float.showMemory") private var showMemory = false
    @AppStorage(FloatingGraphLogic.opacityKey) private var opacity = FloatingGraphLogic.defaultOpacity

    @State private var isHovering = false
    @State private var showOpacityPopover = false

    private static let corner: CGFloat = 12
    private static let width: CGFloat = 300
    /// 헤더 우측 고정 슬롯 — hover 시 opacity만 변화 (삽입/삭제로 인한 출렁임 방지)
    /// scrcpy(≈90) + menu/opacity/close(22×3) + spacing
    private static let trailingSlotWidth: CGFloat = 176

    private var device: DeviceSnapshot? { store.selectedDevice }
    private var devices: [DeviceSnapshot] { store.inventory.devices }
    private var metrics: DroidMetrics? {
        device.map { store.metrics(for: $0.serial) }
    }

    /// 전부 off 방지
    private var cards: FloatingGraphLogic.Cards {
        FloatingGraphLogic.resolve(
            network: showNetwork,
            cpu: showCPU,
            gpu: showGPU,
            memory: showMemory
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider().overlay(OPColor.border).padding(.horizontal, 12).padding(.vertical, 6)

            if device == nil {
                emptyHint
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                let bg = FloatingGraphLogic.clampOpacity(opacity)
                VStack(alignment: .leading, spacing: 10) {
                    if cards.network {
                        DroidCards.network(
                            device: device,
                            metrics: metrics,
                            backgroundOpacity: bg
                        )
                        .environment(\.dynamicTypeSize, .xSmall)
                    }
                    if cards.cpu {
                        DroidCards.cpu(
                            device: device,
                            metrics: metrics,
                            backgroundOpacity: bg
                        )
                    }
                    if cards.gpu {
                        DroidCards.gpu(
                            device: device,
                            metrics: metrics,
                            backgroundOpacity: bg
                        )
                    }
                    if cards.memory {
                        DroidCards.memory(
                            device: device,
                            metrics: metrics,
                            backgroundOpacity: bg,
                            onMore: { onOpenProcesses() }
                        )
                    }
                }
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
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            // fittingSize 갱신 — 카드 토글/데이터 변화 대응
            FloatingGraphController.shared.fitToContent()
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
                // 카드 선택만 — Menu 안 Slider는 macOS에서 깨짐(투명도는 전용 팝오버)
                Menu {
                    Toggle(L10n.string("float.card.cpu"), isOn: $showCPU)
                    Toggle(L10n.string("float.card.gpu"), isOn: $showGPU)
                    Toggle(L10n.string("float.card.memory"), isOn: $showMemory)
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

                if let d = device, !d.serial.isEmpty {
                    ScrcpyHeaderButton(serial: d.serial)
                }

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

                Button {
                    FloatingGraphController.shared.hide()
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

    /// 다중 기기 — 헤더에서 전역 선택 변경 (이슈 0)
    private var devicePicker: some View {
        Menu {
            ForEach(devices, id: \.serial) { d in
                Button {
                    store.select(d.serial)
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
