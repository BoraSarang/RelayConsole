import Foundation

/// 히스토리 링 버버 — 5s × 60 = 5분
struct DroidMetrics {
    static let capacity = 60

    private(set) var cpuHistory: [Double] = []
    private(set) var tempHistory: [Double] = []
    private(set) var levelHistory: [Double] = []
    private(set) var netUpHistory: [Double] = []
    private(set) var netDownHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []

    mutating func push(
        cpu: Double? = nil,
        temp: Double? = nil,
        level: Double? = nil,
        netUp: Double? = nil,
        netDown: Double? = nil,
        diskRead: Double? = nil,
        diskWrite: Double? = nil,
        gpu: Double? = nil
    ) {
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
