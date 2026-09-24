import SwiftUI

/// 플로팅 그래프 본체 — Network(고정) + CPU/GPU/Memory 토글
/// borderless NSPanel(.nonactivating) 안에서 호스팅 (FloatingGraphController 소유)
struct FloatingGraphView: View {
    @ObservedObject var store: ConsoleStore

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
    private static let trailingSlotWidth: CGFloat = 74

    private var device: DeviceSnapshot? { store.selectedDevice }
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
                VStack(alignment: .leading, spacing: 10) {
                    if cards.network {
                        DroidCards.network(device: device, metrics: metrics)
                            .environment(\.dynamicTypeSize, .xSmall)
                    }
                    if cards.cpu {
                        DroidCards.cpu(device: device, metrics: metrics)
                    }
                    if cards.gpu {
                        DroidCards.gpu(device: device, metrics: metrics)
                    }
                    if cards.memory {
                        DroidCards.memory(device: device, metrics: metrics) {}
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .fill(Color(hex: 0x0F111A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .stroke(isHovering ? OPColor.border : Color.clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .onChange(of: opacity) { _, new in
            FloatingGraphController.shared.setOpacity(new)
        }
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
            Text(device?.displayName ?? L10n.string("float.noDevice"))
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            // 항상 레이아웃 점유 — 메뉴/닫기 아이콘이 생겨도 헤더 폭·높이 고정
            HStack(spacing: 4) {
                Menu {
                    Section(L10n.string("float.opacity")) {
                        Slider(value: $opacity, in: FloatingGraphLogic.minOpacity...FloatingGraphLogic.maxOpacity)
                    }
                    Divider()
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
                        Text("\(Int(opacity * 100))%")
                            .font(OPFont.number(11))
                            .foregroundStyle(OPColor.inkDim)
                    }
                    .padding(12)
                    .frame(width: 184)
                    .background(Color(hex: 0x0F111A))
                    .preferredColorScheme(.dark)
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

    private var emptyHint: some View {
        Text(L10n.string("float.empty"))
            .font(OPFont.body(11))
            .foregroundStyle(OPColor.inkDim)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }
}
