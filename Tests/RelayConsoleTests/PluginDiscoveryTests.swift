import Testing
@testable import RelayConsole

struct PluginDiscoveryTests {
    private var spot: PluginDescriptor { .spotShift }
    private var relay: PluginDescriptor { .droidRelay }

    // MARK: - 명단

    @Test func registryListsBothPluginsWithDistinctTags() {
        let tags = PluginRegistry.plugins.map(\.logTag)
        #expect(Set(tags).count == tags.count)
        #expect(PluginRegistry.plugin(logTag: "SpotShift")?.id == "spotshift")
        #expect(PluginRegistry.plugin(logTag: "DroidRelay")?.id == "droidrelay")
        #expect(PluginRegistry.plugin(logTag: "Unknown") == nil)
    }

    // MARK: - 설치 확인

    @Test func installedWhenPackageListed() {
        let pm = "package:com.borasarang.spotshift\npackage:com.borasarang.droidrelay\n"
        #expect(PluginDiscoveryLogic.isInstalled(pmListText: pm, packageName: spot.packageName) == true)
        #expect(PluginDiscoveryLogic.isInstalled(pmListText: pm, packageName: relay.packageName) == true)
        #expect(PluginDiscoveryLogic.isInstalled(pmListText: pm, packageName: "com.foo.bar") == false)
    }

    @Test func notInstalledOnPrefixMatch() {
        // `spotshift2` 같은 접미사는 다른 앱 — 정확히 일치만 인정
        #expect(PluginDiscoveryLogic.isInstalled(
            pmListText: "package:com.borasarang.spotshift2\n", packageName: spot.packageName
        ) == false)
    }

    // MARK: - 프로브 파싱 (실측 형식)

    @Test func parseProbeRealLine() {
        let line = "10-08 13:25:25.617 13160 13182 I SpotShift: [PLUGIN] version=1 actions=autorotate logTag=SpotShift allowed=true"
        let p = PluginDiscoveryLogic.parseProbeLine(line)
        #expect(p?.version == 1)
        #expect(p?.actions == ["autorotate"])
        #expect(p?.allowed == true)
        #expect(p?.logTag == "SpotShift")
    }

    @Test func parseProbeMultiActionRealLine() {
        let line = "10-08 13:51:11.390 22873 23102 I DroidRelay: [PLUGIN] version=1 actions=server_status,server_control,download_add,torrent_add logTag=DroidRelay allowed=true"
        let p = PluginDiscoveryLogic.parseProbeLine(line)
        #expect(p?.actions.count == 4)
        #expect(p?.actions.contains("download_add") == true)
        #expect(p?.logTag == "DroidRelay")
    }

    @Test func parseProbeOutputRoutesByTag() {
        let text = """
        10-08 13:51:11.390 1 1 I SpotShift: [PLUGIN] version=1 actions=autorotate logTag=SpotShift allowed=true
        10-08 13:51:11.391 2 2 I DroidRelay: [PLUGIN] version=1 actions=server_status logTag=DroidRelay allowed=false
        """
        let out = PluginDiscoveryLogic.parseProbeOutput(text)
        #expect(out["SpotShift"]?.allowed == true)
        #expect(out["DroidRelay"]?.allowed == false)
    }

    @Test func parseProbeOutputTakesLastPerTag() {
        let text = """
        [PLUGIN] version=1 actions=autorotate logTag=SpotShift allowed=true
        [PLUGIN] version=1 actions=autorotate logTag=SpotShift allowed=false
        """
        #expect(PluginDiscoveryLogic.parseProbeOutput(text)["SpotShift"]?.allowed == false)
    }

    @Test func parseProbeRejectsMalformed() {
        #expect(PluginDiscoveryLogic.parseProbeLine("no marker here") == nil)
        #expect(PluginDiscoveryLogic.parseProbeLine("[PLUGIN] version=x actions=autorotate allowed=true") == nil)
        #expect(PluginDiscoveryLogic.parseProbeLine("[PLUGIN] version=1 actions=autorotate") == nil)
    }

    // MARK: - 지원 판정

    @Test func supportsV2Actions() {
        let s = PluginDiscoveryLogic.Probe(version: 2, actions: ["autorotate"], allowed: true)
        #expect(PluginDiscoveryLogic.supports(s, descriptor: spot) == true)
        let d = PluginDiscoveryLogic.Probe(version: 2, actions: ["server_status"], allowed: true)
        #expect(PluginDiscoveryLogic.supports(d, descriptor: relay) == true)
        #expect(PluginDiscoveryLogic.supports(d, descriptor: spot) == false)
    }

    @Test func rejectsUnknownVersion() {
        // 모르는 버전은 추측 실행 금지 — 미지원
        let p = PluginDiscoveryLogic.Probe(version: 3, actions: ["autorotate"], allowed: true)
        #expect(PluginDiscoveryLogic.supports(p, descriptor: spot) == false)
    }

    // MARK: - 결과 파싱 v1 changed형 (실측)

    @Test func parseRemoteSuccessRealLine() {
        let line = "10-08 13:25:05.990 13160 13160 I SpotShift: [REMOTE] 원격 변경 결과 changed=true 118.235.3.241 → 39.7.46.252 측정 2.16Mbps ≥ 기준 2.0Mbps — 달성"
        let r = PluginDiscoveryLogic.parseRemoteLine(line)
        #expect(r?.changed == true)
        #expect(r?.oldIp == "118.235.3.241")
        #expect(r?.newIp == "39.7.46.252")
        #expect(r?.refused == false)
        #expect((r?.note.contains("2.16Mbps") ?? false))
    }

    // MARK: - 결과 파싱 v2 ok형 (실측)

    @Test func parseRemoteStatusRealLine() {
        let line = "10-08 13:51:33.878 22873 22873 I DroidRelay: [REMOTE] action=server_status ok=true running=true ip=10.112.134.138 port=3000 version=0.50.0"
        let r = PluginDiscoveryLogic.parseRemoteLine(line)
        #expect(r?.action == "server_status")
        #expect(r?.ok == true)
        #expect(r?.changed == nil)
        #expect(r?.refused == false)
        let dict = Dictionary(r?.fields.map { ($0.key, $0.value) } ?? [], uniquingKeysWith: { a, _ in a })
        #expect(dict["running"] == "true")
        #expect(dict["ip"] == "10.112.134.138")
        #expect(dict["port"] == "3000")
    }

    @Test func parseRemoteFailureRealLine() {
        let line = "10-08 13:42:05.981 21031 21031 I DroidRelay: [REMOTE] action=download_add ok=false errorCode=E-AND-PLG-0002 note=invalid url"
        let r = PluginDiscoveryLogic.parseRemoteLine(line)
        #expect(r?.action == "download_add")
        #expect(r?.ok == false)
        #expect(r?.errorCode == "E-AND-PLG-0002")
        #expect(r?.note == "invalid url")
    }

    @Test func parseRemoteRefused() {
        let r = PluginDiscoveryLogic.parseRemoteLine("[REMOTE] 거부됨 (연동 OFF)")
        #expect(r?.refused == true)
        #expect(r?.changed == nil)
        #expect(r?.ok == nil)
    }

    @Test func parseRemoteV2OkFormRealLine() {
        // SpotShift v2 실측 (명시적 브로드캐스트 발송 후)
        let line = "10-08 14:14:53.629 30898 31514 I SpotShift: [REMOTE] action=autorotate ok=true oldIp=118.235.25.68 newIp=39.7.230.26 speedMbps=2.03 note=측정 2.03Mbps ≥ 기준 2.0Mbps — 달성"
        let r = PluginDiscoveryLogic.parseRemoteLine(line)
        #expect(r?.action == "autorotate")
        #expect(r?.ok == true)
        #expect(r?.changed == nil)
        let dict = Dictionary(r?.fields.map { ($0.key, $0.value) } ?? [], uniquingKeysWith: { a, _ in a })
        #expect(dict["oldIp"] == "118.235.25.68")
        #expect(dict["newIp"] == "39.7.230.26")
        #expect(dict["speedMbps"] == "2.03")
    }

    @Test func parseRemoteOutputRoutesByLineTag() {
        let text = """
        10-08 13:25:05.990 1 1 I SpotShift: [REMOTE] 원격 변경 결과 changed=true 1.1.1.1 → 2.2.2.2 ok
        10-08 13:51:33.878 2 2 I DroidRelay: [REMOTE] action=server_status ok=true running=true
        """
        let out = PluginDiscoveryLogic.parseRemoteOutput(text)
        #expect(out["SpotShift"]?.changed == true)
        #expect(out["DroidRelay"]?.ok == true)
    }

    @Test func parseRemoteRejectsMalformed() {
        #expect(PluginDiscoveryLogic.parseRemoteLine("no marker") == nil)
        #expect(PluginDiscoveryLogic.parseRemoteLine("[REMOTE] changed=maybe 1.1.1.1 → 2.2.2.2") == nil)
        // ok형인데 action 없음 → 귀속 불가
        #expect(PluginDiscoveryLogic.parseRemoteLine("[REMOTE] ok=true running=true") == nil)
    }

    // MARK: - 줄 TAG 추출

    @Test func lineTagExtractsLogTag() {        #expect(PluginDiscoveryLogic.lineTag(
            "10-08 13:51:33.878 22873 22873 I DroidRelay: [REMOTE] action=x ok=true",
            marker: "[REMOTE]"
        ) == "DroidRelay")
        #expect(PluginDiscoveryLogic.lineTag("garbage", marker: "[REMOTE]") == nil)
    }

    // MARK: - adb 인자 계약 고정

    @Test func adbArgsContainContractConstants() {        let s = "10.0.0.1:5555"
        let probe = PluginDiscoveryLogic.probeBroadcastArgs(
            serial: s, action: relay.probeAction, receiver: relay.probeReceiver
        ).joined(separator: " ")
        #expect(probe.contains("com.borasarang.droidrelay.PLUGIN_PROBE"))
        #expect(probe.contains("com.borasarang.droidrelay/.receiver.PluginProbeReceiver"))
        let dump = PluginDiscoveryLogic.logcatDumpArgs(
            serial: s, logTags: ["SpotShift", "DroidRelay"]
        ).joined(separator: " ")
        // 덤프 1회 — 태그 전부 실림
        #expect(dump.contains("SpotShift:*"))
        #expect(dump.contains("DroidRelay:*"))
        let boolArgs = PluginDiscoveryLogic.actionStartArgs(
            serial: s, activity: "com.x/.MainActivity", key: "k", value: "true", asBool: true
        )
        #expect(boolArgs.contains("--ez"))
        let strArgs = PluginDiscoveryLogic.actionStartArgs(
            serial: s, activity: "com.x/.MainActivity", key: "k", value: "v", asBool: false
        )
        #expect(strArgs.contains("--es"))
        // v2 명시적 발송 — `-n` 포함 (암시적은 배달 안 됨, 실측)
        let bcast = PluginDiscoveryLogic.explicitBroadcastArgs(
            serial: s, receiver: "com.x/.receiver.PluginActionReceiver",
            action: "com.x.PLUGIN_ACTION", extras: [(key: "cmd", value: "autorotate", asBool: false)]
        ).joined(separator: " ")
        #expect(bcast.contains("-n com.x/.receiver.PluginActionReceiver"))
        #expect(bcast.contains("--es cmd autorotate"))
    }

    // MARK: - 호출 인자 조립 (명단 → 실측 명령)

    @Test func invokeArgsSpotShiftBroadcast() {
        let s = "10.0.0.1:5555"
        let action = PluginDescriptor.spotShift.actions[0]
        let args = PluginDiscoveryLogic.invokeArgs(serial: s, action: action, input: "")?
            .joined(separator: " ") ?? ""
        // 실측 동작 명령과 동일
        #expect(args.contains("-n com.borasarang.spotshift/.receiver.PluginActionReceiver"))
        #expect(args.contains("--es cmd autorotate"))
        #expect(!args.contains("MainActivity"))
    }

    @Test func invokeArgsRelayControlAddsArg() {
        let s = "10.0.0.1:5555"
        let start = PluginDescriptor.droidRelay.actions.first {
            $0.id == "server_control" && $0.title == "서버 시작"
        }!
        let args = PluginDiscoveryLogic.invokeArgs(serial: s, action: start, input: "")?
            .joined(separator: " ") ?? ""
        #expect(args.contains("--es cmd server_control"))
        #expect(args.contains("--es arg start"))
    }

    @Test func invokeArgsTextRequiresInput() {
        let s = "10.0.0.1:5555"
        let add = PluginDescriptor.droidRelay.actions.first { $0.id == "download_add" }!
        #expect(PluginDiscoveryLogic.invokeArgs(serial: s, action: add, input: "   ") == nil)
        let args = PluginDiscoveryLogic.invokeArgs(
            serial: s, action: add, input: "https://x"
        )?.joined(separator: " ") ?? ""
        #expect(args.contains("--es arg https://x"))
    }

    // MARK: - L2 메타데이터 1행

    @Test func parseInfoRowRealLine() {
        let line = "Row: 0 label=SpotShift, description=핫스팟 IP 자동 변경, contractVersion=2, appVersion=0.5.0, allowed=true, iconBase64=iVBOR, actionsJson=[{}]"
        let m = PluginDiscoveryLogic.parseInfoRow(line)
        #expect(m?.label == "SpotShift")
        #expect(m?.description == "핫스팟 IP 자동 변경")
        #expect(m?.appVersion == "0.5.0")
        #expect(m?.allowed == true)
        #expect(m?.iconBase64 == "iVBOR")
    }

    @Test func parseInfoRowEmptyIcon() {
        let line = "Row: 0 label=DroidRelay, description=x, contractVersion=2, appVersion=0.50.0, allowed=true, iconBase64=, actionsJson=[]"
        let m = PluginDiscoveryLogic.parseInfoRow(line)
        #expect(m?.label == "DroidRelay")
        #expect(m?.iconBase64 == "")
    }

    @Test func parseInfoRowRejectsMalformed() {
        #expect(PluginDiscoveryLogic.parseInfoRow("Row: 0 foo=bar") == nil)
        #expect(PluginDiscoveryLogic.parseInfoRow("Row: 0 label=, description=x, contractVersion=2, appVersion=1, allowed=true, iconBase64=, actionsJson=[]") == nil)
    }

    @Test func pngBytesValidatesSignature() {
        // 1x1 투명 PNG
        let tiny = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        #expect(PluginDiscoveryLogic.pngBytes(base64: tiny) != nil)
        #expect(PluginDiscoveryLogic.pngBytes(base64: "") == nil)
        #expect(PluginDiscoveryLogic.pngBytes(base64: "aGVsbG8=") == nil)
    }

    @Test func iconCacheURLKeysByPackageAndVersion() {
        let u1 = PluginDiscoveryLogic.iconCacheURL(packageName: "com.x", appVersion: "1.0")
        let u2 = PluginDiscoveryLogic.iconCacheURL(packageName: "com.x", appVersion: "2.0")
        #expect(u1 != nil && u2 != nil && u1 != u2)
        #expect(u1?.lastPathComponent.contains("com.x") == true)
    }
}
