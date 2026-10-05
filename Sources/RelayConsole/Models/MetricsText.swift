import Foundation

/// `/metrics` 응답을 만드는 **순수 입력** — store 와 무관하다
///
/// ## 왜 store 를 스냅숏으로 떼는가
/// `ConsoleStore` 는 `@MainActor` 이고 창·기기·네트워크를 끌어다 쓴다.
/// 그대로 쓰면 지표 텍스트를 **눈으로 확인**해야만 한다(그러면 테스트가 못 한다).
/// 순수 스냅숏을 받으면 `Rule`·`RelayWidgetCore`·`ThresholdGate` 처럼
/// **값이 틀리면 테스트가 죽는** 구조가 된다.
struct MetricsSnapshot: Equatable, Sendable {
    struct Device: Equatable, Sendable {
        var serial: String
        var model: String
        var connectionKind: String
        var isOnline: Bool
        /// nil = **확인하지 못했다** (0% 와 다른 값이다 — 행을 내지 않는다)
        var batteryPercent: Int?
        /// 충전 방치 지속 초 — nil = **방치 중이 아니다** (0 초와 다른 값이다)
        var neglectSeconds: Int?
    }

    var version: String
    var build: String
    var devices: [Device] = []
    var activeCriticalAlerts: Int = 0
}

/// 도메인 상태 → `MetricsSnapshot` 변환 — **store 없이** 돈다
///
/// ## 왜 store 밖으로 꺼냈나
/// `ConsoleStore` 는 `private init` 인 싱글턴이라 **테스트에서 만들 수 없다.**
/// 그러면 지표가 틀렸을 때 잡아낼 방법이 없다. 입력만 받고 스냅숏을 내는
/// 순수 함수로 두면 **"이 기기가 이 값으로 보인다"** 를 테스트로 고정한다.
enum MetricsSnapshotBuilder {
    static func make(
        devices: [DeviceSnapshot],
        events: [WatchEvent],
        now: Date = .now,
        version: String = AppVersion.display,
        neglect: [String: Int] = [:]
    ) -> MetricsSnapshot {
        var snap = MetricsSnapshot(version: version, build: version)
        snap.devices = devices.map { d in
            MetricsSnapshot.Device(
                serial: d.serial,
                model: d.model,
                connectionKind: d.connectionKind?.rawValue ?? "unknown",
                isOnline: d.isOnline,
                // 오프라인 기기의 배터리는 "확인하지 못했다" — 저장값이 있어도 내지 않는다
                batteryPercent: d.isOnline ? d.batteryLevel : nil,
                // 방치 시간은 **관측이 쌓인 결과**다 — 기기가 목록에서 사라지면 같이 사라진다
                neglectSeconds: d.isOnline ? neglect[d.serial] : nil
            )
        }
        snap.activeCriticalAlerts = BriefingLogic.activeCriticalCount(events)
        return snap
    }
}

/// Prometheus text exposition format (version 0.0.4) 렌더러 — **순수 함수**
enum MetricsTextBuilder {
    /// 라벨 값 이스케이프 (`\` · `"` · 개행만 규격에 있다)
    static func escapeLabel(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for ch in raw {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            default: out.append(ch)
            }
        }
        return out
    }

    /// IEEE 754 스펙에 맞는 수치 표기 — `nan`/`inf` 가 나올 수 있는 자리에만 쓴다
    private static func number(_ v: Double) -> String {
        guard v.isFinite else { return v.isNaN ? "NaN" : (v > 0 ? "+Inf" : "-Inf") }
        if v == v.rounded(), abs(v) < 1e15 { return String(format: "%.1f", v) }
        return String(format: "%g", v)
    }

    private static func line(_ name: String, _ labels: [String: String] = [:], _ value: String) -> String {
        lineForTest(name, labels, value)
    }

    /// 라벨 정렬 순서까지 테스트로 잠근다 (몸통은 `render` 가 호출)
    static func lineForTest(_ name: String, _ labels: [String: String], _ value: String) -> String {
        guard !labels.isEmpty else { return "\(name) \(value)" }
        let body = labels
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\"\(escapeLabel($0.value))\"" }
            .joined(separator: ",")
        return "\(name){\(body)} \(value)"
    }

    /// 응답 본문 전체 — 뒤에 개행 하나를 붙인다 (스펙 요구)
    static func render(_ snap: MetricsSnapshot) -> String {
        var out = ""

        out += "# HELP relay_build_info 앱 버전 (항상 1 — 값은 라벨로)\n"
        out += "# TYPE relay_build_info gauge\n"
        out += line("relay_build_info", ["version": snap.version, "build": snap.build], "1") + "\n"

        out += "# HELP relay_device_online 기기가 지금 연결돼 있는가 (오프라인도 0 으로 낸다)\n"
        out += "# TYPE relay_device_online gauge\n"
        for d in snap.devices {
            out += line("relay_device_online", [
                "serial": d.serial, "model": d.model, "kind": d.connectionKind,
            ], d.isOnline ? "1" : "0") + "\n"
        }

        out += "# HELP relay_device_battery_percent 배터리 잔량(%) — 미확인 기기는 행이 없다\n"
        out += "# TYPE relay_device_battery_percent gauge\n"
        for d in snap.devices {
            // 미확인은 0 이 아니라 **행 없음** — 0% 는 "확인했다가 0" 이라는 뜻이 된다
            guard let pct = d.batteryPercent else { continue }
            out += line("relay_device_battery_percent", ["serial": d.serial], String(pct)) + "\n"
        }

        out += "# HELP relay_device_battery_neglect_seconds 임계 이하 배터리가 충전 없이 지속된 초 (방치 중이 아니면 행이 없다)\n"
        out += "# TYPE relay_device_battery_neglect_seconds gauge\n"
        for d in snap.devices {
            // 방치 **중인** 기기만 행을 낸다 — 0 초는 "방치 중이지만 0 초" 라는 모순이다
            guard let neg = d.neglectSeconds else { continue }
            out += line("relay_device_battery_neglect_seconds", ["serial": d.serial], String(neg)) + "\n"
        }

        out += "# HELP relay_alert_active_critical 지금 활성화된 critical 알림 수\n"
        out += "# TYPE relay_alert_active_critical gauge\n"
        out += line("relay_alert_active_critical", [:], String(snap.activeCriticalAlerts)) + "\n"

        return out
    }
}
