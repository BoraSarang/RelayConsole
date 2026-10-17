import SwiftUI

/// 기기 선택 메뉴 항목 — **한 폰은 한 줄**, 같은 폰의 다른 전송은 하위 메뉴로 (T-2026-10-17-10)
///
/// 실측(2026-10-17): S22 하나가 `192.168.86.49:5555`(레거시 tcpip)와 `192.168.86.49:45325`
/// (무선 디버깅)로 동시에 잡혀 기기 선택에 **두 줄**로 떴다(USB 까지 꽂으면 세 줄).
/// 팝오버·파일 탐색기가 같은 문법을 쓰도록 여기 한 곳에서 만든다.
struct DeviceTransportMenuItems: View {
    let group: DeviceInventory.DeviceGroup
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(group.primary.serial)
        } label: {
            menuLabel(group.primary, text: primaryText)
        }
        .disabled(group.primary.serial == selected)

        if group.hasMultipleTransports {
            Menu(L10n.format("device.transport.others", group.others.count)) {
                ForEach(group.others, id: \.serial) { other in
                    Button {
                        onSelect(other.serial)
                    } label: {
                        menuLabel(other, text: otherText(other))
                    }
                    .disabled(other.serial == selected)
                }
            }
            .help(otherHelp)
        }
    }

    /// 대표 전송 줄 — 배지로 어느 경로인지 밝힌다(엔드포인트는 재부팅마다 바뀔 수 있다)
    private var primaryText: String {
        "\(group.primary.displayName) · \(group.primary.transportBadge)"
    }

    /// 나머지 전송 줄 — 엔드포인트까지 보여줘야 미러링 대상 고르기가 가능하다
    private func otherText(_ other: DeviceSnapshot) -> String {
        "\(other.connShort) · \(other.transportBadge)"
    }

    private var otherHelp: String {
        group.others.map(\.transportHelp).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func menuLabel(_ d: DeviceSnapshot, text: String) -> some View {
        if d.serial == selected {
            Label(text, systemImage: "checkmark")
        } else {
            Label(text, systemImage: d.isOnline ? "iphone" : "iphone.slash")
        }
    }
}
