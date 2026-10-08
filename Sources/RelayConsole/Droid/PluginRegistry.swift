import Foundation

/// 기기에 있을 수 있는 플러그인 명단 — 껍데기(어디에 물어볼지)만 등록,
/// 내용(설치·버전·허용·결과·액션 실행)은 기기 검색 1회로 채운다.
/// 플러그인 추가 = 여기 1블록, UI·Store 수정 없음.
/// 표시 이름·액션 제목은 잠정 하드코딩 — L2 메타데이터 Provider가 오면 기기값으로 교체
/// (`docs/PLUGIN_SDK.md` §3).
struct PluginDescriptor: Equatable, Sendable {
    struct Action: Equatable, Sendable {
        enum Kind: String, Sendable { case button, text }
        enum Value: Equatable, Sendable {
            /// 고정 문자열 값
            case fixed(String)
            /// 텍스트 입력값 ($input)
            case input
        }
        enum Invoke: Equatable, Sendable {
            /// v2 명시적 브로드캐스트 (§4.1, `-n` 필수).
            /// extras = [(cmdKey, id)] + argKey 있을 때 [(argKey, 값)].
            case broadcast(receiver: String, action: String, cmdKey: String, argKey: String?)
            /// v1 activity 경로 (§4.3, 폐지 예정)
            case activity(component: String, key: String)
        }
        /// 계약 액션 id (`[REMOTE] action=` 귀속용)
        var id: String
        /// 버튼·행 제목 (잠정 — L2 Provider가 오면 기기값)
        var title: String
        var kind: Kind
        /// 텍스트 입력 placeholder (잠정)
        var hint: String = ""
        var invoke: Invoke
        var value: Value
    }
    var id: String
    var displayName: String
    var packageName: String
    var probeAction: String
    var probeReceiver: String
    var logTag: String
    var contractVersion: Int
    var knownActionIds: Set<String>
    var actions: [Action]
}

enum PluginRegistry {
    static let plugins: [PluginDescriptor] = [.spotShift, .droidRelay]

    /// logTag → 플러그인 — 1회 덤프에서 응답 귀속용
    static func plugin(logTag: String) -> PluginDescriptor? {
        plugins.first { $0.logTag == logTag }
    }
}

extension PluginDescriptor {
    static let spotShift = PluginDescriptor(
        id: "spotshift",
        displayName: "SpotShift",
        packageName: "com.borasarang.spotshift",
        probeAction: "com.borasarang.spotshift.PLUGIN_PROBE",
        probeReceiver: "com.borasarang.spotshift/.receiver.PluginProbeReceiver",
        logTag: "SpotShift",
        contractVersion: 2,
        knownActionIds: ["autorotate"],
        actions: [
            Action(
                id: "autorotate", title: "IP 변경 요청", kind: .button,
                invoke: .broadcast(
                    receiver: "com.borasarang.spotshift/.receiver.PluginActionReceiver",
                    action: "com.borasarang.spotshift.PLUGIN_ACTION",
                    cmdKey: "cmd", argKey: nil
                ),
                value: .fixed("")
            )
        ]
    )

    static let droidRelay = PluginDescriptor(
        id: "droidrelay",
        displayName: "DroidRelay",
        packageName: "com.borasarang.droidrelay",
        probeAction: "com.borasarang.droidrelay.PLUGIN_PROBE",
        probeReceiver: "com.borasarang.droidrelay/.receiver.PluginProbeReceiver",
        logTag: "DroidRelay",
        contractVersion: 2,
        knownActionIds: ["server_status", "server_control", "download_add", "torrent_add"],
        actions: [
            Action(
                id: "server_status", title: "서버 상태 조회", kind: .button,
                invoke: .broadcast(
                    receiver: "com.borasarang.droidrelay/.plugin.PluginActionReceiver",
                    action: "com.borasarang.droidrelay.PLUGIN_ACTION",
                    cmdKey: "cmd", argKey: nil
                ),
                value: .fixed("")
            ),
            Action(
                id: "server_control", title: "서버 시작", kind: .button,
                invoke: .broadcast(
                    receiver: "com.borasarang.droidrelay/.plugin.PluginActionReceiver",
                    action: "com.borasarang.droidrelay.PLUGIN_ACTION",
                    cmdKey: "cmd", argKey: "arg"
                ),
                value: .fixed("start")
            ),
            Action(
                id: "server_control", title: "서버 정지", kind: .button,
                invoke: .broadcast(
                    receiver: "com.borasarang.droidrelay/.plugin.PluginActionReceiver",
                    action: "com.borasarang.droidrelay.PLUGIN_ACTION",
                    cmdKey: "cmd", argKey: "arg"
                ),
                value: .fixed("stop")
            ),
            Action(
                id: "download_add", title: "URL 추가", kind: .text, hint: "https://…",
                invoke: .broadcast(
                    receiver: "com.borasarang.droidrelay/.plugin.PluginActionReceiver",
                    action: "com.borasarang.droidrelay.PLUGIN_ACTION",
                    cmdKey: "cmd", argKey: "arg"
                ),
                value: .input
            ),
            Action(
                id: "torrent_add", title: "magnet 추가", kind: .text, hint: "magnet:…",
                invoke: .broadcast(
                    receiver: "com.borasarang.droidrelay/.plugin.PluginActionReceiver",
                    action: "com.borasarang.droidrelay.PLUGIN_ACTION",
                    cmdKey: "cmd", argKey: "arg"
                ),
                value: .input
            )
        ]
    )
}
