import Foundation

/// 폴링 1틱의 adb 호출을 **1회로 묶는** 배칭 계층.
///
/// ## 왜 필요한가
/// 폴링은 5초마다 돌아가고, slow 틱(15초)에는 기기당 25번의 `adb shell`을 띄운다.
/// 각 호출은 호스트 fork+exec + adb 서버 TCP 재연결 + **기기측 adbd 셸 프로세스 신규 생성**을
/// 을 수반한다. 실측(기기 1대·Wi-Fi):
///
/// | | 개별 | 배치 | 비고 |
/// |---|---|---|---|
/// | fast 틱 6회 | 361~401ms | **171~174ms** | 2.1배 |
/// | slow 틱 21회 | 1378~1518ms | **546~551ms** | 2.6배 |
///
/// 분당 adb 프로세스 수가 **156 → 36**으로 감소한다(기기 1대 기준).
///
/// ## 마커 프로토콜
/// 기기측 `sh`가 `@@RLY<n>@@` 마커를 출력하면, 호스트는 마커로 출력을 잘라
/// **종전과 동일한 문자열**을 각 파서에 넘긴다. 즉 파서는 전혀 바뀌지 않는다.
///
/// 실기기 대조 검증: 21개 명령 전수 비교에서 18개가 줄 단위로 완전 일치,
/// 나머지 3개(`/proc/loadavg`·`/proc/stat`·`dumpsys netstats detail`)는
/// 실행 시점마다 값이 변하는 **누적 카운터**라 개별 실행끼리도 서로 다르다.
enum PollBatch {

    /// 배치에 포함할 명령. **순서가 곧 마커 인덱스**이므로 임의로 바꾸면 안 된다.
    enum Cmd: CaseIterable {
        // ── fast (매 5초)
        case battery
        case thermal
        case loadavg
        case procStat
        case accelRotation
        case userRotation

        // ── slow (15초)
        case lowPower
        case scalingCur
        case scalingMax
        case meminfo
        case psi
        case ps
        case cpuinfo
        case netdev
        case netstats
        case connectivity
        case signal
        case activity
        case ipWlan
        case df
        case gpuBusy
        case gpuGpubusy
        case gpuClk
        case sensors
        case diskstats

        /// 기기측 `sh`에 넘길 단일 문자열.
        ///
        /// - `adb shell`은 argv를 따옴표 없이 공백으로 이어 붙인다(1.16.0 핫픽ks 참조).
        ///   그래서 파이프·글로브가 있는 명령은 **반드시 한 인자**로 넘긴다.
        /// - 파이프/리다이렉션은 기기측 `sh`가 처리한다.
        var shell: String {
            switch self {
            case .battery: return "dumpsys battery"
            case .thermal: return "dumpsys thermalservice"
            case .loadavg: return "cat /proc/loadavg"
            case .procStat: return "cat /proc/stat"
            case .accelRotation: return "settings get system accelerometer_rotation"
            case .userRotation: return "settings get system user_rotation"
            case .lowPower: return "settings get global low_power"
            case .scalingCur: return "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"
            case .scalingMax: return "cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq"
            case .meminfo: return "cat /proc/meminfo"
            case .psi: return "cat /proc/pressure/memory"
            case .ps: return "ps -A -o PID,RSS,NAME,ARGS --sort=-rss"
            case .cpuinfo: return "dumpsys cpuinfo"
            case .netdev: return "cat /proc/net/dev"
            case .netstats: return "dumpsys netstats detail"
            case .connectivity: return "dumpsys connectivity"
            case .signal:
                // 자기 RustSignal 수신 grep
                return "dumpsys telephony.registry | grep -E 'mSignalStrength|mOperatorAlphaLong|mServiceState|mDataConnectionState'"
            case .activity: return "dumpsys activity activities"
            case .ipWlan: return "ip -f inet addr show wlan0"
            case .df: return "df -h /data"
            case .gpuBusy: return "cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage"
            case .gpuGpubusy: return "cat /sys/class/kgsl/kgsl-3d0/gpubusy"
            case .gpuClk: return "cat /sys/class/kgsl/kgsl-3d0/gpuclk"
            case .sensors:
                return "dumpsys sensorservice | grep -E 'Total [0-9]+ h/w sensors|active-count|\\) type 0x|active connections|Sensor Device|Sensor List'"
            case .diskstats: return "cat /proc/diskstats"
            }
        }
    }

    /// 매 틱 공통 — 5초마다
    static let fast: [Cmd] = [.battery, .thermal, .loadavg, .procStat, .accelRotation, .userRotation]

    /// slow 틱 — 15초마다 (fast + 15초 항목)
    static let slow: [Cmd] = fast + [
        .lowPower, .scalingCur, .scalingMax, .meminfo, .psi, .ps, .cpuinfo, .netdev,
        .netstats, .connectivity, .signal, .activity, .ipWlan, .df,
        .gpuBusy, .gpuGpubusy, .gpuClk, .sensors, .diskstats,
    ]

    // MARK: - 마커

    static let markerPrefix = "@@RLY"
    static let markerSuffix = "@@"

    static func marker(_ index: Int) -> String { "\(markerPrefix)\(index)\(markerSuffix)" }

    /// 명령들을 마커로 연결한 **단일 셸 문자열**.
    ///
    /// `;` 로 연결하므로 한 명령이 실패해도 나머지는 계속 실행된다(`set -e` 없음).
    /// 실패한 명령의 청크는 비어 있을 뿐 마커 자체는 항상 emitted 된다.
    static func build(_ cmds: [Cmd]) -> String {
        guard !cmds.isEmpty else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(cmds.count * 2)
        for (i, c) in cmds.enumerated() {
            parts.append("echo \"\(marker(i))\"")
            parts.append(c.shell)
        }
        return parts.joined(separator: "; ")
    }

    /// 마커로 출력을 잘라 명령별 문자열로 돌려준다.
    ///
    /// - 키는 `Cmd` — 존재하지 않거나 출력이 비었으면 `nil`(= 종전의 `try?` 실패와 동일 취급).
    /// - 마커가 하나도 없으면 **전체 출력을 첫 명령 것으로 간주**하지 않는다.
    ///   배치가 깨졌을 수 있으므로 전부 `nil` 로 두어 "조용한 오염"을 막는다([표시②]).
    static func parse(_ output: String, into cmds: [Cmd]) -> [Cmd: String] {
        var result: [Cmd: String] = [:]
        var currentIndex: Int?
        var buffer: [String] = []

        func flush() {
            guard let idx = currentIndex, idx >= 0, idx < cmds.count else { return }
            let text = buffer.joined(separator: "\n")
            // 빈 출력은 실패(종전 try? 실패)와 동일하게 취급 — 구분 불필요
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[cmds[idx]] = text
            }
            buffer = []
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if let idx = parseMarker(s) {
                flush()
                currentIndex = idx
            } else if currentIndex != nil {
                buffer.append(s)
            }
        }
        flush()

        return result
    }

    /// `@@RLY<n>@@` 형태만 마커로 인정 — 다른 줄에 우연히 걸리지 않도록 **정확히** 검사
    static func parseMarker(_ line: String) -> Int? {
        guard line.hasPrefix(markerPrefix), line.hasSuffix(markerSuffix) else { return nil }
        let mid = line.dropFirst(markerPrefix.count).dropLast(markerSuffix.count)
        guard !mid.isEmpty, mid.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(mid)
    }
}
