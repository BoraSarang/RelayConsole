import Foundation

/// ADB 연결 방식 — serial에 `:` 유무로 판별 (IP:PORT = network)
enum ConnectionKind: String, Sendable, Equatable, Codable {
    case usb
    case network
}

/// 메모리/스왑 프로세스 RSS 행
struct ProcessRSS: Sendable, Equatable, Hashable {
    var name: String
    var rssMB: Double
}

/// 프로세스 목록 행 — 이름 + PID + CPU% + RSS + 실행 경로
struct ProcessRow: Sendable, Equatable, Hashable, Identifiable {
    var name: String
    var cpuPercent: Double?
    var rssMB: Double?
    var pid: Int?
    /// ARGS/cmdline — 실행 경로 (앱 APK 경로 또는 바이너리)
    var path: String?
    /// 네트워크 속도 (MB/s) — uid별 netstats delta를 패키지명으로 매핑
    var netMBps: Double?
    var id: String {
        if let pid { return "\(pid):\(name)" }
        return name
    }
}

/// thermalservice 온도 존 행
struct ThermalZone: Sendable, Equatable, Hashable {
    var name: String
    var tempC: Double
}

/// uid별 앱 네트워크 사용량 (누적량 스냅샷, `dumpsys netstats detail`)
struct AppNetStat: Sendable, Equatable, Hashable, Identifiable {
    var uid: Int
    var packageName: String?
    var rxBytes: UInt64
    var txBytes: UInt64
    var id: Int { uid }
    var totalBytes: UInt64 { rxBytes &+ txBytes }
}

/// 두 스냅샷 사이의 앱별 속도 (MB/s)
struct AppNetRate: Sendable, Equatable, Hashable, Identifiable {
    var uid: Int
    var packageName: String?
    var upMBps: Double
    var downMBps: Double
    var totalMBps: Double { upMBps + downMBps }
    var id: Int { uid }
}

struct DeviceSnapshot: Sendable, Equatable {
    var serial: String = ""
    var model: String = ""
    var isOnline: Bool = false
    /// 이 스냅샷이 **실제 adb 응답**을 포함할 때만 찍히는 시각.
    ///
    /// 종전엔 `isOnline` 만 보고 `lastSampleAt` 을 갱신했는데, `isOnline` 은
    /// `pollDevice` 시작에서 무조건 true 가 된다. 그래서 adb 가 전부 실패해도
    /// "방금 측정" 으로 위장했다. 이제 실제 응답이 있었을 때만 신선도를 올린다.
    var measuredAt: Date?
    /// 연속 실패 횟수 — 실패 / 미측정 / 오프라인 을 구분하기 위한 값 ([표시②])
    var failureStreak: Int = 0
    /// USB | network
    var connectionKind: ConnectionKind?
    /// 표시용 연결 라벨 — USB | 10.x.x.x:5555
    var connectionLabel: String?
    /// 오프라인 전환 시각 — 일정 시간 지나면 목록에서 제거한다(`pruneOffline`)
    var offlineSince: Date?
    /// settings get global device_name (예: S22)
    var deviceName: String?
    var batteryLevel: Int?
    var batteryTempC: Double?
    var isCharging: Bool?
    var thermalStatus: Int?
    var cpuUsePercent: Double?
    var deviceTempC: Double?
    var memoryUsedGB: Double?
    var memoryTotalGB: Double?
    var storageUsedGB: Double?
    var storageTotalGB: Double?
    var networkInfo: String?
    var netUpMBps: Double?
    var netDownMBps: Double?
    /// Wi-Fi / LTE / NR / … — dumpsys connectivity Active default
    var networkType: String?
    var voltageMV: Int?
    var batteryHealthPct: Int?
    var isProtectionMode: Bool?
    var protectionThresholdPct: Int?
    /// settings global low_power (0/1)
    var isLowPowerMode: Bool?
    var cycleEstimate: Int?
    var load1: Double?
    var load5: Double?
    var load15: Double?
    var androidVersion: String?
    var sdkInt: Int?
    // ── Phase1 카드 필드 ──
    var coreFreqsMHz: [Double]?
    var coreMaxMHz: [Double]?
    var coreUsePercents: [Double]?
    var cpuGovernor: String?
    /// PSI memory some avg10
    var memPressurePct: Double?
    /// none / low / moderate / full
    var memPressureLabel: String?
    var topProcesses: [ProcessRSS]?
    /// 전체 프로세스 목록 (CPU% + RSS, 시트용)
    var processList: [ProcessRow]?
    var swapUsedGB: Double?
    var thermalZones: [ThermalZone]?
    var rsrp: Int?
    var signalOperator: String?
    var wifiSsid: String?
    var wifiRssi: Int?
    var ipV4: String?
    /// RSRQ (dB) — `dumpsys telephony.registry` rsrq=
    var rsrq: Int?
    /// SINR (dB) — rssnr= / ssSinr=
    var sinr: Int?
    /// "LTE" | "NR" | "UMTS" | … — getRilDataRadioTechnology=(RAT)
    var signalRat: String?
    /// 밴드 요약 — "B3" / "B3+B8" / "B3+n78"
    var signalBands: String?
    /// CA 사용 여부 — isUsingCarrierAggregation=
    var signalCA: Bool?
    /// uid별 앱 네트워크 누적량 (15s, `dumpsys netstats detail`)
    var appNetStats: [AppNetStat]?
    /// uid별 앱 네트워크 속도 (MB/s) — 15s delta
    var appNetRates: [AppNetRate]?
    // ── P2 카드 필드 (PLAN_v0.4) ──
    /// SurfaceFlinger GLES 렌더러 (예: Adreno (TM) 730)
    var gpuRenderer: String?
    /// OpenGL ES 버전 문자열
    var gpuEsVersion: String?
    /// kgsl gpuclk MHz
    var gpuFreqMHz: Double?
    /// kgsl gpu_busy_percentage 0…100
    var gpuUtilPercent: Double?
    /// sensorservice 전체 n/w 센서 수
    var sensorTotalCount: Int?
    /// 현재 active 센서 수
    var sensorActiveCount: Int?
    /// 활성 센서 이름 (최대 8)
    var sensorActiveNames: [String]?
    /// 활성 센서 샘플 주기(ms) — sensorActiveNames와 같은 순서
    var sensorActivePeriodsMs: [Double?]?
    /// diskstats sda delta MB/s
    var diskReadMBps: Double?
    var diskWriteMBps: Double?
    /// 세션 중 설정 변경 횟수 (accelerometer_rotation / user_rotation)
    var settingsChangedCount: Int?
    /// 세션 중 logcat 키워드 적중 수
    var logcatHitCount: Int?
    /// 포그라운드 앱 패키지 (15s dumpsys activity)
    var foregroundPackage: String?
    /// 마지막 측정 시각 — 오프라인 후 지표 신선도 표시용 (AGENTS.local §4 [표시②])
    var lastSampleAt: Date?
    /// 수집 실패 원인 (성공 틱에서 자동 해제)
    var lastError: String?

    /// Equatable — 배열/옵셔널 필드 자동 합성 충분 (tuple 없음)

    /// ≥40°C or thermal Status≥2 (V0-2 Surface A)
    var isThermalAlert: Bool {
        if let t = deviceTempC ?? batteryTempC, t >= 40 { return true }
        if let s = thermalStatus, s >= 2 { return true }
        return false
    }

    /// 헤더 표시 이름 — deviceName > model > serial 원문
    var displayName: String {
        AdbClient.displayDeviceName(deviceName: deviceName, model: model, serial: serial)
    }

    /// 기기 식별 라벨 — 화면·알림·내보내기 공통 진입점 (마스킹 금지 · AGENTS.local §4)
    /// network → `IP:PORT`, USB → `기기명 또는 모델 · 시리얼 원문`
    var identLabel: String {
        if connectionKind == .network {
            if let l = connectionLabel, !l.isEmpty, l != "USB" { return l }
            return serial
        }
        let name = displayName
        if serial.isEmpty { return name }
        if name.isEmpty || name == serial { return serial }
        return "\(name) · \(serial)"
    }
}

/// UI 유일 read 모델 (값 타입 — ConsoleStore가 @Published로 보유)
struct DeviceInventory: Equatable {
    var devices: [DeviceSnapshot] = []

    func device(serial: String) -> DeviceSnapshot? {
        devices.first { $0.serial == serial }
    }

    var onlineDevices: [DeviceSnapshot] {
        devices.filter(\.isOnline)
    }

    /// 부분 스냅샷 병합 — nil optional은 이전 값 유지 (5s 틱이 15s 필드를 덮지 않음)
    mutating func merge(_ snapshot: DeviceSnapshot, now: Date = .now) {
        guard !snapshot.serial.isEmpty else { return }
        if let idx = devices.firstIndex(where: { $0.serial == snapshot.serial }) {
            var merged = snapshot
            let prev = devices[idx]
            if merged.isOnline {
                merged.batteryLevel = merged.batteryLevel ?? prev.batteryLevel
                merged.batteryTempC = merged.batteryTempC ?? prev.batteryTempC
                merged.isCharging = merged.isCharging ?? prev.isCharging
                merged.thermalStatus = merged.thermalStatus ?? prev.thermalStatus
                merged.cpuUsePercent = merged.cpuUsePercent ?? prev.cpuUsePercent
                merged.deviceTempC = merged.deviceTempC ?? prev.deviceTempC
                merged.memoryUsedGB = merged.memoryUsedGB ?? prev.memoryUsedGB
                merged.memoryTotalGB = merged.memoryTotalGB ?? prev.memoryTotalGB
                merged.storageUsedGB = merged.storageUsedGB ?? prev.storageUsedGB
                merged.storageTotalGB = merged.storageTotalGB ?? prev.storageTotalGB
                merged.networkInfo = merged.networkInfo ?? prev.networkInfo
                merged.netUpMBps = merged.netUpMBps ?? prev.netUpMBps
                merged.netDownMBps = merged.netDownMBps ?? prev.netDownMBps
                merged.networkType = merged.networkType ?? prev.networkType
                merged.voltageMV = merged.voltageMV ?? prev.voltageMV
                merged.batteryHealthPct = merged.batteryHealthPct ?? prev.batteryHealthPct
                merged.isProtectionMode = merged.isProtectionMode ?? prev.isProtectionMode
                merged.protectionThresholdPct = merged.protectionThresholdPct ?? prev.protectionThresholdPct
                merged.isLowPowerMode = merged.isLowPowerMode ?? prev.isLowPowerMode
                merged.cycleEstimate = merged.cycleEstimate ?? prev.cycleEstimate
                merged.load1 = merged.load1 ?? prev.load1
                merged.load5 = merged.load5 ?? prev.load5
                merged.load15 = merged.load15 ?? prev.load15
                merged.androidVersion = merged.androidVersion ?? prev.androidVersion
                merged.sdkInt = merged.sdkInt ?? prev.sdkInt
                merged.settingsChangedCount = merged.settingsChangedCount ?? prev.settingsChangedCount
                merged.logcatHitCount = merged.logcatHitCount ?? prev.logcatHitCount
                merged.foregroundPackage = merged.foregroundPackage ?? prev.foregroundPackage
                if merged.model.isEmpty { merged.model = prev.model }
                merged.connectionKind = merged.connectionKind ?? prev.connectionKind
                merged.connectionLabel = merged.connectionLabel ?? prev.connectionLabel
                merged.deviceName = merged.deviceName ?? prev.deviceName
                merged.coreFreqsMHz = merged.coreFreqsMHz ?? prev.coreFreqsMHz
                merged.coreMaxMHz = merged.coreMaxMHz ?? prev.coreMaxMHz
                merged.coreUsePercents = merged.coreUsePercents ?? prev.coreUsePercents
                merged.cpuGovernor = merged.cpuGovernor ?? prev.cpuGovernor
                merged.memPressurePct = merged.memPressurePct ?? prev.memPressurePct
                merged.memPressureLabel = merged.memPressureLabel ?? prev.memPressureLabel
                merged.topProcesses = merged.topProcesses ?? prev.topProcesses
                merged.processList = merged.processList ?? prev.processList
                merged.swapUsedGB = merged.swapUsedGB ?? prev.swapUsedGB
                merged.thermalZones = merged.thermalZones ?? prev.thermalZones
                merged.rsrp = merged.rsrp ?? prev.rsrp
                merged.signalOperator = merged.signalOperator ?? prev.signalOperator
                merged.rsrq = merged.rsrq ?? prev.rsrq
                merged.sinr = merged.sinr ?? prev.sinr
                merged.signalRat = merged.signalRat ?? prev.signalRat
                merged.signalBands = merged.signalBands ?? prev.signalBands
                merged.signalCA = merged.signalCA ?? prev.signalCA
                merged.appNetStats = merged.appNetStats ?? prev.appNetStats
                merged.appNetRates = merged.appNetRates ?? prev.appNetRates
                merged.wifiSsid = merged.wifiSsid ?? prev.wifiSsid
                merged.wifiRssi = merged.wifiRssi ?? prev.wifiRssi
                merged.ipV4 = merged.ipV4 ?? prev.ipV4
                merged.gpuRenderer = merged.gpuRenderer ?? prev.gpuRenderer
                merged.gpuEsVersion = merged.gpuEsVersion ?? prev.gpuEsVersion
                merged.gpuFreqMHz = merged.gpuFreqMHz ?? prev.gpuFreqMHz
                merged.gpuUtilPercent = merged.gpuUtilPercent ?? prev.gpuUtilPercent
                merged.sensorTotalCount = merged.sensorTotalCount ?? prev.sensorTotalCount
                merged.sensorActiveCount = merged.sensorActiveCount ?? prev.sensorActiveCount
                merged.sensorActiveNames = merged.sensorActiveNames ?? prev.sensorActiveNames
                merged.sensorActivePeriodsMs = merged.sensorActivePeriodsMs ?? prev.sensorActivePeriodsMs
                merged.diskReadMBps = merged.diskReadMBps ?? prev.diskReadMBps
                merged.diskWriteMBps = merged.diskWriteMBps ?? prev.diskWriteMBps
            }
            // 신선도는 **실제 adb 응답이 있었을 때만** 올린다.
            // 종전엔 isOnline(=무조건 true) 로 갱신해 adb 전체 실패를 "방금 측정" 으로 위장했다.
            if let m = snapshot.measuredAt, merged.isOnline {
                merged.lastSampleAt = m
                merged.offlineSince = nil          // 재접속 → 오프라인 경과 초기화
            } else {
                merged.lastSampleAt = prev.lastSampleAt
            }
            devices[idx] = merged
        } else {
            var added = snapshot
            // 신규 등록 — 실제 응답이 있었을 때만 신선도를 찍는다
            if added.isOnline { added.lastSampleAt = snapshot.measuredAt }
            devices.append(added)
        }
    }

    mutating func markOffline(serial: String, now: Date = .now) {
        guard let idx = devices.firstIndex(where: { $0.serial == serial }) else { return }
        let wasOnline = devices[idx].isOnline
        devices[idx].isOnline = false
        // 재연결 → 해제 반복 시 시각이 갱신되지 않도록 첫 전환 시각만 기록
        if wasOnline || devices[idx].offlineSince == nil {
            devices[idx].offlineSince = now
        }
    }

    /// 오래 오프라인인 기기를 목록에서 제거한다.
    ///
    /// ## 왜 필요한가
    /// `markOffline` 은 플래그만 바꾸고 배열에서 지우지 않아, 한번 연결된 기기는 영원히 남았다.
    /// 결과:
    /// - 메뉴바 아이콘 판정이 `devices.isEmpty` 로 되어 **기기 0대인데 Online** 으로 표시됨
    /// - 팝오버 기기 수가 `0/47` 처럼 무의미해짐 (오프라인 누적)
    /// - 네트워크 ADB 는 serial 이 `IP:PORT` 라 DHCP 변경마다 새 항목 → 무한 증가
    ///
    /// 이벤트·일일 집계는 별도 저장소(영구 데이터)이므로 여기서는 건드리지 않는다.
    mutating func pruneOffline(olderThan interval: TimeInterval, now: Date = .now) {
        devices.removeAll { d in
            guard !d.isOnline, let since = d.offlineSince else { return false }
            return now.timeIntervalSince(since) >= interval
        }
    }
}
