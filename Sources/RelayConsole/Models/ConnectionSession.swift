import Foundation

/// Android 연결 세션 — 연속 연결 구간 (USB/network)
struct ConnectionSession: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let serial: String
    let kind: ConnectionKind
    let connectedAt: Date
    /// nil = 진행 중 (앱 종료 시 미닫힘 유지 가능)
    var disconnectedAt: Date?
    /// 연결 시각 기준 YYYYMMDD
    let dayKey: String

    init(
        id: UUID = UUID(),
        serial: String,
        kind: ConnectionKind,
        connectedAt: Date = .now,
        disconnectedAt: Date? = nil,
        dayKey: String? = nil
    ) {
        self.id = id
        self.serial = serial
        self.kind = kind
        self.connectedAt = connectedAt
        self.disconnectedAt = disconnectedAt
        self.dayKey = dayKey ?? ConnectionSession.dayKey(for: connectedAt)
    }

    /// ISO8601 일자 키 (로컬 캘린더)
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            c.year ?? 1970, c.month ?? 1, c.day ?? 1
        )
    }

    var isOngoing: Bool { disconnectedAt == nil }

    /// 종료 시각 기준 (진행 중이면 기준 시각)
    func endedAt(or fallback: Date) -> Date {
        disconnectedAt ?? fallback
    }

    /// 세션 길이 (초) — 기준 시각까지 진행 중 포함
    func durationSeconds(now: Date = .now) -> TimeInterval {
        max(0, endedAt(or: now).timeIntervalSince(connectedAt))
    }
}

// MARK: - 순수 집계 (테스트 대상)

enum ConnectionSessionLogic {
    /// 세션 열기 — 같은 serial 기존 open 세션이 있으면 먼저 close (이상 상태 정리)
    static func open(
        sessions: inout [ConnectionSession],
        serial: String,
        kind: ConnectionKind,
        at: Date = .now
    ) {
        if let idx = sessions.lastIndex(where: { $0.serial == serial && $0.isOngoing }) {
            sessions[idx].disconnectedAt = at
        }
        sessions.append(ConnectionSession(serial: serial, kind: kind, connectedAt: at))
    }

    /// 세션 닫기 — 가장 최근 open
    @discardableResult
    static func close(
        sessions: inout [ConnectionSession],
        serial: String,
        at: Date = .now
    ) -> Bool {
        guard let idx = sessions.lastIndex(where: { $0.serial == serial && $0.isOngoing }) else {
            return false
        }
        sessions[idx].disconnectedAt = at
        return true
    }

    /// dayKey 필터
    static func filtered(
        _ sessions: [ConnectionSession],
        dayKey: String,
        serial: String? = nil
    ) -> [ConnectionSession] {
        sessions.filter { s in
            guard s.dayKey == dayKey else { return false }
            if let serial { return s.serial == serial }
            return true
        }
    }

    /// 일자별 요약
    static func dailySummary(
        _ sessions: [ConnectionSession],
        dayKey: String,
        serial: String? = nil,
        now: Date = .now
    ) -> ConnectionDaySummary {
        let list = filtered(sessions, dayKey: dayKey, serial: serial)
        let total = list.reduce(0.0) { $0 + $1.durationSeconds(now: now) }
        let longest = list.map { $0.durationSeconds(now: now) }.max() ?? 0
        // dayKey 종료일 기준 종료 시각 대조 — dayKey가 오늘이 아니고 ongoing이면 now 사용
        return ConnectionDaySummary(
            dayKey: dayKey,
            serial: serial,
            count: list.count,
            totalMinutes: total / 60.0,
            longestMinutes: longest / 60.0,
            usbCount: list.filter { $0.kind == .usb }.count,
            networkCount: list.filter { $0.kind == .network }.count
        )
    }

    /// retention 경과분 제거 (days<=0 = 무제한)
    @discardableResult
    static func prune(
        _ sessions: inout [ConnectionSession],
        retentionDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard retentionDays > 0 else { return 0 }
        guard let cutoffDay = calendar.date(
            byAdding: .day,
            value: -retentionDays,
            to: calendar.startOfDay(for: now)
        ) else { return 0 }
        let cutoffKey = ConnectionSession.dayKey(for: cutoffDay, calendar: calendar)
        let before = sessions.count
        sessions.removeAll { $0.dayKey < cutoffKey }
        return before - sessions.count
    }
}

/// 일자별 연결 요약
struct ConnectionDaySummary: Codable, Equatable, Sendable {
    let dayKey: String
    let serial: String?
    let count: Int
    let totalMinutes: Double
    let longestMinutes: Double
    let usbCount: Int
    let networkCount: Int
}
