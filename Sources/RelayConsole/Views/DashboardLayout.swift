import Foundation

/// 대시보드 카드 식별 — 순서·행 구성의 단일 진실원처 (콘솔 Android)
enum DashboardCard: String, CaseIterable, Sendable {
    case cpu
    case thermal
    case memory
    case network
    case battery
    case health
    case gpu
    case storage
    case sensors

    /// 2열 행 구성 — 관제 우선순위: 성능/발열 → 자원/연결 → 수명/종합 → 부가 하드웨어
    static let rows: [[DashboardCard]] = [
        [.cpu, .thermal],
        [.memory, .network],
        [.battery, .health],
        [.gpu, .storage]
    ]

    /// 전폭 단독 카드 — 목록형이라 그리드 아래 한 줄
    static let wideCards: [DashboardCard] = [.sensors]

    /// 표시 순서 (행 펼침 → wide) — 메뉴바 팝오버·설정 카드 토글 미러링용
    static var ordered: [DashboardCard] { rows.flatMap { $0 } + wideCards }

    /// 설정 → 카드 토글 라벨 키 (`settings.cards.<rawValue>`)
    var settingsLabelKey: String { "settings.cards.\(rawValue)" }
}
