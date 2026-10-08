import Foundation
import Combine
import SwiftUI

/// 플러그인 상태 — MainActor UI 바인딩 (IO는 여기서만)
/// 계약: 상시 연결·폴링 없음. **검색 버튼을 누를 때만 1회 스윕**
/// (`pm 1회` → 설치된 곳에 프로브 일괄 → 2초 후 `logcat 1회`).
/// 느려도 상관없다 — 사용자가 누른 순간에만 돈다.
/// 액션은 fire-and-forget, 결과는 다음 검색(또는 결과 확인)의 덤프에서 귀속.
@MainActor
final class PluginStore: ObservableObject {
    static let shared = PluginStore()

    struct ProbeState: Equatable {
        var installed: Bool?
        var probe: PluginDiscoveryLogic.Probe?
        var fetchedAt: Date?
    }

    struct ResultState: Equatable {
        var result: PluginDiscoveryLogic.RemoteResult?
        var fetchedAt: Date?
        /// 액션 요청을 보낸 시각 — 결과 대기 표시용 (fire-and-forget이라 콜백 없음)
        var pendingSince: Date?
    }

    /// key = `serial + "\n" + pluginId` — 기기×플러그인 1칸씩
    @Published private(set) var probeByKey: [String: ProbeState] = [:]
    @Published private(set) var resultByKey: [String: ResultState] = [:]
    @Published private(set) var busyKeys: Set<String> = []
    @Published private(set) var busySerials: Set<String> = []
    /// key → 마지막 실패 원인 원문 ([표시②] 원인 삭제 금지)
    @Published private(set) var lastErrorByKey: [String: String] = [:]
    @Published private(set) var lastMessageByKey: [String: String] = [:]
    /// L2 메타데이터 (표시 이름·설명·아이콘) — key = `serial + "\n" + pluginId`
    @Published private(set) var metadataByKey: [String: PluginDiscoveryLogic.PluginMetadata] = [:]

    private init() {}

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - 키·조회

    func key(serial: String, plugin: PluginDescriptor) -> String {
        serial + "\n" + plugin.id
    }

    func probeState(serial: String, plugin: PluginDescriptor) -> ProbeState {
        probeByKey[key(serial: serial, plugin: plugin)] ?? ProbeState()
    }

    func resultState(serial: String, plugin: PluginDescriptor) -> ResultState {
        resultByKey[key(serial: serial, plugin: plugin)] ?? ResultState()
    }

    func lastError(serial: String, plugin: PluginDescriptor) -> String? {
        lastErrorByKey[key(serial: serial, plugin: plugin)]
    }

    func lastMessage(serial: String, plugin: PluginDescriptor) -> String? {
        lastMessageByKey[key(serial: serial, plugin: plugin)]
    }

    func metadata(serial: String, plugin: PluginDescriptor) -> PluginDiscoveryLogic.PluginMetadata? {
        metadataByKey[key(serial: serial, plugin: plugin)]
    }

    /// 캐시된 아이콘 파일 — 없으면 nil (View가 SF Symbol 폴백)
    func iconFileURL(serial: String, plugin: PluginDescriptor) -> URL? {
        guard metadata(serial: serial, plugin: plugin) != nil,
              let url = PluginDiscoveryLogic.iconCacheURL(
                  packageName: plugin.packageName,
                  appVersion: metadata(serial: serial, plugin: plugin)?.appVersion ?? ""
              ),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - 소비자 토글 (플러그인별, 기기 allowed 와 AND)

    private func toggleKey(_ plugin: PluginDescriptor) -> String {
        "relay.plugin.\(plugin.id).enabled"
    }

    func consumerEnabled(_ plugin: PluginDescriptor) -> Bool {
        UserDefaults.standard.object(forKey: toggleKey(plugin)) as? Bool ?? true
    }

    func setConsumerEnabled(_ plugin: PluginDescriptor, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: toggleKey(plugin))
        objectWillChange.send()
    }

    func consumerBinding(_ plugin: PluginDescriptor) -> Binding<Bool> {
        Binding(
            get: { self.consumerEnabled(plugin) },
            set: { self.setConsumerEnabled(plugin, $0) }
        )
    }

    /// 양쪽 AND — 소비자 토글과 기기 allowed가 모두 true일 때만 동작
    func effectiveEnabled(plugin: PluginDescriptor, probe: PluginDiscoveryLogic.Probe?) -> Bool {
        guard consumerEnabled(plugin), let p = probe, p.allowed else { return false }
        return PluginDiscoveryLogic.supports(p, descriptor: plugin)
    }

    // MARK: - 검색 1회 스윕 (검색 버튼 전용)

    /// 전 플러그인 1회 스윕 — pm 1회 → 프로브 일괄 → logcat 1회.
    /// 프로브 응답과 `[REMOTE]` 결과 귀속까지 같은 덤프에서 끝낸다.
    func search(serial: String) async {
        guard !busySerials.contains(serial) else { return }
        guard let adb = DeviceMonitor.adbPathNow() else {
            markAllError(serial: serial, message: L10n.string("plugin.error.noAdb"))
            return
        }
        busySerials.insert(serial)
        defer { busySerials.remove(serial) }
        clearSerialMessages(serial: serial)
        do {
            // ① 설치 1회 — 명단 전원 판정
            let pmText = try await run(adb, PluginDiscoveryLogic.pmListArgs(serial: serial))
            var installedIds = Set<String>()
            for plugin in PluginRegistry.plugins {
                let installed = PluginDiscoveryLogic.isInstalled(
                    pmListText: pmText, packageName: plugin.packageName
                )
                if installed {
                    installedIds.insert(plugin.id)
                } else {
                    probeByKey[key(serial: serial, plugin: plugin)] = ProbeState(
                        installed: false, probe: nil, fetchedAt: Date()
                    )
                }
            }
            // ② 프로브 일괄 — 설치된 곳에만, 출력 대기 없음
            for plugin in PluginRegistry.plugins where installedIds.contains(plugin.id) {
                _ = try await run(adb, PluginDiscoveryLogic.probeBroadcastArgs(
                    serial: serial, action: plugin.probeAction, receiver: plugin.probeReceiver
                ))
            }
            guard !installedIds.isEmpty else { return }
            // 앱 꺼져 있어도 응답하지만 콜드스타트 여유 2초 (실측 기준)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // ③ 덤프 1회 — 프로브 응답 + 결과 로그를 태그로 귀속
            let dump = try await run(adb, PluginDiscoveryLogic.logcatDumpArgs(
                serial: serial, logTags: PluginRegistry.plugins.map(\.logTag)
            ))
            applyDump(serial: serial, dump: dump, now: Date())
            // ④ 메타데이터 (L2, best-effort — 없어도 카드는 뜬다)
            await fetchMetadata(serial: serial, adb: adb, installedIds: installedIds)
        } catch {
            markAllError(serial: serial, message: cause(error))
        }
    }

    /// 결과만 다시 긁기 — 같은 1회 덤프, 전 플러그인 귀속
    func refreshResults(serial: String) async {
        guard !busySerials.contains(serial) else { return }
        guard let adb = DeviceMonitor.adbPathNow() else {
            markAllError(serial: serial, message: L10n.string("plugin.error.noAdb"))
            return
        }
        busySerials.insert(serial)
        defer { busySerials.remove(serial) }
        do {
            let dump = try await run(adb, PluginDiscoveryLogic.logcatDumpArgs(
                serial: serial, logTags: PluginRegistry.plugins.map(\.logTag)
            ))
            let remotes = PluginDiscoveryLogic.parseRemoteOutput(dump)
            var sawAny = false
            for plugin in PluginRegistry.plugins {
                guard let r = remotes[plugin.logTag] else { continue }
                sawAny = true
                var st = resultState(serial: serial, plugin: plugin)
                st.result = r
                st.fetchedAt = Date()
                st.pendingSince = nil
                resultByKey[key(serial: serial, plugin: plugin)] = st
                lastMessageByKey.removeValue(forKey: key(serial: serial, plugin: plugin))
            }
            if !sawAny {
                markAllMessage(serial: serial, message: L10n.string("plugin.result.none"))
            }
        } catch {
            markAllError(serial: serial, message: cause(error))
        }
    }

    private func applyDump(serial: String, dump: String, now: Date) {
        let probes = PluginDiscoveryLogic.parseProbeOutput(dump)
        let remotes = PluginDiscoveryLogic.parseRemoteOutput(dump)
        for plugin in PluginRegistry.plugins {
            let k = key(serial: serial, plugin: plugin)
            guard probeByKey[k]?.installed != false else { continue }
            guard let probe = probes[plugin.logTag] else {
                probeByKey[k] = ProbeState(installed: true, probe: nil, fetchedAt: now)
                lastErrorByKey[k] = L10n.string("plugin.error.noProbe")
                continue
            }
            probeByKey[k] = ProbeState(installed: true, probe: probe, fetchedAt: now)
            if !PluginDiscoveryLogic.supports(probe, descriptor: plugin) {
                lastMessageByKey[k] = L10n.format(
                    "plugin.unsupported", plugin.displayName, "\(probe.version)"
                )
            }
            if let r = remotes[plugin.logTag] {
                var st = resultState(serial: serial, plugin: plugin)
                st.result = r
                st.fetchedAt = now
                st.pendingSince = nil
                resultByKey[k] = st
            }
        }
    }

    // MARK: - 액션 (fire-and-forget, 콜백 없음)

    /// 액션 1회 발송 — 성공/실패는 다음 검색·결과 확인의 `[REMOTE]` 로그로만 확인
    func request(plugin: PluginDescriptor, action: PluginDescriptor.Action, serial: String, input: String = "") async {
        let k = key(serial: serial, plugin: plugin)
        guard !busyKeys.contains(k) else { return }
        let probe = probeState(serial: serial, plugin: plugin).probe
        guard effectiveEnabled(plugin: plugin, probe: probe) else {
            lastErrorByKey[k] = L10n.string("plugin.error.disabled")
            return
        }
        guard let adb = DeviceMonitor.adbPathNow() else {
            lastErrorByKey[k] = L10n.string("plugin.error.noAdb")
            return
        }
        let args = PluginDiscoveryLogic.invokeArgs(serial: serial, action: action, input: input)
        guard let args else {
            lastErrorByKey[k] = L10n.string("plugin.error.needInput")
            return
        }
        busyKeys.insert(k)
        lastErrorByKey.removeValue(forKey: k)
        defer { busyKeys.remove(k) }
        do {
            _ = try await run(adb, args)
            var st = resultState(serial: serial, plugin: plugin)
            st.pendingSince = Date()
            resultByKey[k] = st
            lastMessageByKey[k] = L10n.format("plugin.pending", Self.timeFmt.string(from: Date()))
        } catch {
            lastErrorByKey[k] = cause(error)
        }
    }

    func clearPending(serial: String, plugin: PluginDescriptor) {
        let k = key(serial: serial, plugin: plugin)
        var st = resultState(serial: serial, plugin: plugin)
        st.pendingSince = nil
        resultByKey[k] = st
    }

    /// L2 메타데이터 수집 — 플러그인별 `content query` 1발씩, 실패해도 카드에 영향 없음.
    /// 아이콘은 버전 키 캐시에 저장 (버전 바뀌면 다시 받음).
    private func fetchMetadata(serial: String, adb: String, installedIds: Set<String>) async {
        for plugin in PluginRegistry.plugins where installedIds.contains(plugin.id) {
            let k = key(serial: serial, plugin: plugin)
            guard let out = try? await run(adb, PluginDiscoveryLogic.infoQueryArgs(
                serial: serial, packageName: plugin.packageName
            )) else { continue }
            var found: PluginDiscoveryLogic.PluginMetadata?
            for line in out.split(separator: "\n") {
                if let m = PluginDiscoveryLogic.parseInfoRow(String(line)) {
                    found = m
                    break
                }
            }
            guard let meta = found else { continue }
            metadataByKey[k] = meta
            if let data = PluginDiscoveryLogic.pngBytes(base64: meta.iconBase64),
               let url = PluginDiscoveryLogic.iconCacheURL(
                   packageName: plugin.packageName, appVersion: meta.appVersion
               ) {
                let dir = url.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let existing = try? Data(contentsOf: url)
                if existing != data {
                    try? data.write(to: url)
                }
            }
            objectWillChange.send()
        }
    }

    // MARK: - 실행·잡것
    private func run(_ adb: String, _ args: [String]) async throws -> String {
        // ProcessRunner는 블로킹 호출 — 백그라운드로 보내 MainActor를 붙잡지 않는다
        let argsCopy = args
        return try await Task.detached(priority: .utility) {
            try ProcessRunner.run(
                adb, argsCopy,
                timeout: 20,
                failure: .init(base: "", reason: "")
            )
        }.value
    }

    private func cause(_ error: Error) -> String {
        if let f = error as? ProcessRunner.Failure {
            let r = f.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return r.isEmpty ? f.base : "\(f.base) — \(r)"
        }
        return (error as NSError).localizedDescription
    }

    private func markAllError(serial: String, message: String) {
        for plugin in PluginRegistry.plugins {
            lastErrorByKey[key(serial: serial, plugin: plugin)] = message
        }
    }

    private func markAllMessage(serial: String, message: String) {
        for plugin in PluginRegistry.plugins {
            lastMessageByKey[key(serial: serial, plugin: plugin)] = message
        }
    }

    private func clearSerialMessages(serial: String) {
        for plugin in PluginRegistry.plugins {
            let k = key(serial: serial, plugin: plugin)
            lastErrorByKey.removeValue(forKey: k)
            lastMessageByKey.removeValue(forKey: k)
        }
    }
}
