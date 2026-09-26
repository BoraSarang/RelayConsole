import Foundation

/// 히스토리 링 버퍼 — 최대 60샘플
///
/// ## 주기 관련 주의
/// 종전 주석은 "5s x 60 = 5분" 이었으나 실제로는 `sleep(5s) + tick 소요시간`이 주기다.
/// slow 틱은 adb 호출이 많아 tick이 수 초씩 걸렸고(배치화로 크게 줄었지만 0은 아니다),
/// 기기가 느리면 그만큼 늘어난다. 즉 60칸이 **항상 5분은 아니다.**
/// 그래서 실제 창을 `windowSeconds`로 노출해 진짜 길이를 알 수 있게 한다.
struct DroidMetrics {
    static let capacity = 60
    /// 설계상 목표 주기 — 실제 주기는 `actualInterval`을 볼 것
    static let nominalInterval: TimeInterval = 5

    private(set) var cpuHistory: [Double] = []
    private(set) var tempHistory: [Double] = []
    private(set) var levelHistory: [Double] = []
    private(set) var netUpHistory: [Double] = []
    private(set) var netDownHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []

    /// 가장 오래된 샘플 / 최신 샘플 시각 — 실제 창 계산용
    private(set) var firstAt: Date?
    private(set) var lastAt: Date?

    /// 실제 커버하는 시간(초) — 샘플 2개 미만이면 nil
    var windowSeconds: TimeInterval? {
        guard let firstAt, let lastAt, lastAt > firstAt else { return nil }
        return lastAt.timeIntervalSince(firstAt)
    }

    /// 실제 평균 주기(초) — "5분" 주석이 실제로는 몇 초 창인지 알려준다
    var actualInterval: TimeInterval? {
        guard let w = windowSeconds, cpuHistory.count > 1 else { return nil }
        return w / Double(cpuHistory.count - 1)
    }

    mutating func push(
        cpu: Double? = nil,
        temp: Double? = nil,
        level: Double? = nil,
        netUp: Double? = nil,
        netDown: Double? = nil,
        diskRead: Double? = nil,
        diskWrite: Double? = nil,
        gpu: Double? = nil,
        at date: Date = .now
    ) {
        if firstAt == nil { firstAt = date }
        lastAt = date
        if let cpu { cpuHistory = Self.ring(cpuHistory, cpu) }
        if let temp { tempHistory = Self.ring(tempHistory, temp) }
        if let level { levelHistory = Self.ring(levelHistory, level) }
        if let netUp { netUpHistory = Self.ring(netUpHistory, netUp) }
        if let netDown { netDownHistory = Self.ring(netDownHistory, netDown) }
        if let diskRead { diskReadHistory = Self.ring(diskReadHistory, diskRead) }
        if let diskWrite { diskWriteHistory = Self.ring(diskWriteHistory, diskWrite) }
        if let gpu { gpuHistory = Self.ring(gpuHistory, gpu) }
    }

    private static func ring(_ array: [Double], _ value: Double) -> [Double] {
        var next = array
        next.append(value)
        if next.count > capacity {
            next.removeFirst(next.count - capacity)
        }
        return next
    }
}
