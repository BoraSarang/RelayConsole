import SwiftUI
import AppKit

/// 플러그인 탭 — 기기 종속 (D1 기기 관제탑 유지, 기기 미연결 시 빈 상태)
/// 명단(`PluginRegistry`) 루프 — 플러그인 추가 시 이 파일 수정 없음.
/// 검색 버튼을 누를 때만 1회 스윕 (폴링 없음, 느려도 됨).
struct PluginView: View {
    @ObservedObject var store: ConsoleStore
    @ObservedObject private var plugin = PluginStore.shared
    /// 텍스트 액션 입력값 — key = `serial\npluginId\nactionTitle`
    @State private var inputs: [String: String] = [:]

    private var device: DeviceSnapshot? { store.selectedDevice }

    var body: some View {
        ZStack {
            OPColor.popBG.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSpace.lg) {
                    if let d = device {
                        header(d)
                        if !d.isOnline {
                            offlineBanner
                        }
                        ForEach(PluginRegistry.plugins, id: \.id) { descriptor in
                            pluginCard(descriptor, d)
                        }
                    } else {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
                .padding(OPSpace.lg)
            }
        }
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
    }

    // MARK: - 헤더·검색

    private func header(_ d: DeviceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("plugin.title"))
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
            Text(d.identLabel)
                .font(OPFont.number(11))
                .foregroundStyle(OPColor.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(L10n.string("plugin.desc"))
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    Task { await plugin.search(serial: d.serial) }
                } label: {
                    Label(L10n.string("plugin.search"),
                          systemImage: "magnifyingglass")
                        .font(OPFont.body(12))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(OPColor.cta, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(plugin.busySerials.contains(d.serial) || !d.isOnline)
                Button {
                    Task { await plugin.refreshResults(serial: d.serial) }
                } label: {
                    Label(L10n.string("plugin.checkResult"),
                          systemImage: "doc.text.magnifyingglass")
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.cta)
                }
                .buttonStyle(.plain)
                .disabled(plugin.busySerials.contains(d.serial) || !d.isOnline)
                if plugin.busySerials.contains(d.serial) {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("plugin.noDevice"))
                .font(OPFont.title(15))
                .foregroundStyle(OPColor.ink)
        }
        .padding(.horizontal, OPSpace.xl)
    }

    private var offlineBanner: some View {
        HStack(spacing: 6) {
            Circle().fill(OPColor.bad).frame(width: 6, height: 6)
            Text(L10n.string("plugin.offline"))
                .font(OPFont.body(11))
                .foregroundStyle(OPColor.bad)
                .lineLimit(2)
        }
        .padding(OPSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(OPColor.bad.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.bad.opacity(0.3), lineWidth: 1))
    }

    // MARK: - 플러그인 카드

    private func pluginCard(_ descriptor: PluginDescriptor, _ d: DeviceSnapshot) -> some View {
        let serial = d.serial
        let state = plugin.probeState(serial: serial, plugin: descriptor)
        let result = plugin.resultState(serial: serial, plugin: descriptor)
        let busy = plugin.busySerials.contains(serial)
        let meta = plugin.metadata(serial: serial, plugin: descriptor)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                pluginIcon(descriptor, meta)
                VStack(alignment: .leading, spacing: 1) {
                    Text(meta?.label.isEmpty == false ? meta!.label : descriptor.displayName)
                        .font(OPFont.title(13))
                        .foregroundStyle(OPColor.ink)
                    if let m = meta, !m.description.isEmpty {
                        Text(m.description)
                            .font(OPFont.body(10))
                            .foregroundStyle(OPColor.inkDim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let p = state.probe, !p.appVersion.isEmpty {
                    Text(p.appVersion)
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.inkDim)
                }
                Spacer(minLength: 4)
                statusChip(descriptor, state)
            }

            Toggle(
                L10n.format("plugin.consumerToggle", descriptor.displayName),
                isOn: plugin.consumerBinding(descriptor)
            )
            .font(OPFont.body(12))

            if let err = plugin.lastError(serial: serial, plugin: descriptor), !err.isEmpty {
                Text(err)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.bad)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if let msg = plugin.lastMessage(serial: serial, plugin: descriptor), !msg.isEmpty {
                Text(msg)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let p = state.probe, !PluginDiscoveryLogic.supports(p, descriptor: descriptor) {
                Text(L10n.format("plugin.unsupported", descriptor.displayName, "\(p.version)"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let p = state.probe, PluginDiscoveryLogic.supports(p, descriptor: descriptor),
               plugin.consumerEnabled(descriptor), !p.allowed {
                Text(L10n.format("plugin.disabledDevice", descriptor.displayName))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !plugin.consumerEnabled(descriptor) {
                Text(L10n.string("plugin.disabledApp"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.installed == false {
                Text(L10n.format("plugin.notInstalled", descriptor.displayName))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
            } else if plugin.effectiveEnabled(plugin: descriptor, probe: state.probe) {
                actionBlock(descriptor, d, result, busy: busy)
            }

            resultBlock(descriptor, result)

            if let at = state.fetchedAt {
                Text(L10n.format("plugin.lastCheck", Self.timeFmt.string(from: at)))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.inkDim)
            }
        }
        .padding(OPSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(OPColor.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OPColor.border, lineWidth: 1))
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// 제공자 아이콘 (캐시) — 없으면 SF Symbol 폴백 (`iconBase64=""` 허용)
    @ViewBuilder
    private func pluginIcon(
        _ descriptor: PluginDescriptor,
        _ meta: PluginDiscoveryLogic.PluginMetadata?
    ) -> some View {
        if meta != nil,
           let url = plugin.iconFileURL(serial: device?.serial ?? "", plugin: descriptor),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 13))
                .foregroundStyle(OPColor.inkDim)
                .frame(width: 28, height: 28)
        }
    }

    private func statusChip(_ descriptor: PluginDescriptor, _ state: PluginStore.ProbeState) -> some View {        let (text, color): (String, Color) = {
            if state.installed == false { return (L10n.string("plugin.status.notInstalled"), OPColor.inkDim) }
            guard let p = state.probe else { return (L10n.string("plugin.status.unknown"), OPColor.inkDim) }
            if !PluginDiscoveryLogic.supports(p, descriptor: descriptor) {
                return (L10n.string("plugin.status.unsupported"), OPColor.warn)
            }
            if !plugin.consumerEnabled(descriptor) || !p.allowed {
                return (L10n.string("plugin.status.off"), OPColor.warn)
            }
            return (L10n.string("plugin.status.ready"), OPColor.ok)
        }()
        return Text(text)
            .font(OPFont.number(10))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.3), lineWidth: 1))
    }

    // MARK: - 액션 (제네릭 렌더)

    @ViewBuilder
    private func actionBlock(
        _ descriptor: PluginDescriptor, _ d: DeviceSnapshot,
        _ st: PluginStore.ResultState, busy: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(descriptor.actions.enumerated()), id: \.offset) { _, action in
                switch action.kind {
                case .button:
                    Button {
                        Task { await plugin.request(plugin: descriptor, action: action, serial: d.serial) }
                    } label: {
                        Text(action.title)
                            .font(OPFont.body(12))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(OPColor.cta, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || !d.isOnline)
                case .text:
                    HStack(spacing: 8) {
                        TextField(action.hint, text: Binding(
                            get: { inputs[inputKey(d.serial, descriptor, action)] ?? "" },
                            set: { inputs[inputKey(d.serial, descriptor, action)] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(OPFont.body(12))
                        .disabled(busy || !d.isOnline)
                        Button(L10n.string("plugin.action.run")) {
                            let v = inputs[inputKey(d.serial, descriptor, action)] ?? ""
                            Task { await plugin.request(plugin: descriptor, action: action, serial: d.serial, input: v) }
                        }
                        .buttonStyle(.plain)
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.cta)
                        .disabled(busy || !d.isOnline)
                    }
                    Text(action.title)
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                }
            }
        }
    }

    private func inputKey(_ serial: String, _ descriptor: PluginDescriptor, _ action: PluginDescriptor.Action) -> String {
        serial + "\n" + descriptor.id + "\n" + action.title
    }

    // MARK: - 결과 (제네릭 렌더)

    @ViewBuilder
    private func resultBlock(_ descriptor: PluginDescriptor, _ st: PluginStore.ResultState) -> some View {
        if let since = st.pendingSince {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text(L10n.format("plugin.pending", Self.timeFmt.string(from: since)))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.cta)
            }
        }
        if let r = st.result {
            VStack(alignment: .leading, spacing: 4) {
                if r.refused {
                    Text(L10n.string("plugin.result.refused"))
                        .font(OPFont.body(12))
                        .foregroundStyle(OPColor.warn)
                    Text(r.note)
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                } else if let changed = r.changed {
                    // v1 IP 전이형 (SpotShift)
                    if changed {
                        Text(L10n.format("plugin.result.ok", r.oldIp ?? L10n.na, r.newIp ?? L10n.na))
                            .font(OPFont.number(12))
                            .foregroundStyle(OPColor.ok)
                    } else {
                        Text(L10n.format("plugin.result.fail", r.oldIp ?? L10n.na, r.newIp ?? L10n.na))
                            .font(OPFont.number(12))
                            .foregroundStyle(OPColor.warn)
                    }
                    if !r.note.isEmpty {
                        Text(r.note)
                            .font(OPFont.body(11))
                            .foregroundStyle(OPColor.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                } else {
                    // v2 ok형 (DroidRelay) — 액션 제목 + 성공/실패 + 필드행
                    let title = actionTitle(descriptor, r.action)
                    if r.ok == true {
                        Text(L10n.format("plugin.result.actionOk", title))
                            .font(OPFont.body(12))
                            .foregroundStyle(OPColor.ok)
                    } else {
                        Text(L10n.format("plugin.result.actionFail", title))
                            .font(OPFont.body(12))
                            .foregroundStyle(OPColor.warn)
                    }
                    if let code = r.errorCode, !code.isEmpty {
                        Text(code)
                            .font(OPFont.number(11))
                            .foregroundStyle(OPColor.bad)
                            .textSelection(.enabled)
                    }
                    ForEach(Array(r.fields.enumerated()), id: \.offset) { _, f in
                        HStack {
                            Text(f.key)
                                .font(OPFont.body(11))
                                .foregroundStyle(OPColor.inkDim)
                            Spacer(minLength: 8)
                            Text(f.value)
                                .font(OPFont.number(11))
                                .foregroundStyle(OPColor.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if !r.note.isEmpty {
                        Text(r.note)
                            .font(OPFont.body(11))
                            .foregroundStyle(OPColor.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(OPSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(OPColor.popBG))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
        }
    }

    private func actionTitle(_ descriptor: PluginDescriptor, _ actionId: String?) -> String {
        guard let id = actionId,
              let a = descriptor.actions.first(where: { $0.id == id }) else {
            return actionId ?? L10n.na
        }
        return a.title
    }
}
