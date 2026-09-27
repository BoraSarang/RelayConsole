import Foundation
import Combine

/// 최근 로그 한 줄 목록 — 알림 유입이 `ConsoleStore` 를 무효화하지 않도록 분리
/// (2026-09-28 · `PLAN_published_split_recentevents_relayconsole`)
///
/// ## 왜 이 필드만 뺐나
///
/// `ConsoleStore` 는 View 에 `@ObservedObject` 로 통째로 관찰된다. 그래서 `@Published` 하나가
/// 대입되면 **관찰 중인 모든 View** 의 body 가 재평가된다. 알림 1건(`ingestWatch`)은
/// `recentWatchEvents` 대입 + `pushEvent` 대입으로 **2회** 발화했다(실측).
///
/// 계측 결과 중복 신호의 계산 비용은 이미 0이었다 — 인사이트 캐시 키 9종에 `recentEvents` 가
/// 없어 `pushEvent` 는 캐시 적중(재계산 0ms)하기 때문이다. 그래도 **다른 View body 는 다시 그려진다.**
///
/// 필드별 읽는 곳을 전수 계측한 결과:
///
/// | 필드 | 읽는 View | 분리 비용 |
/// |---|---|---|
/// | `recentWatchEvents` | AlertsView · MenuBarPopoverView · DroidDashboardView · InsightsView (+ 위젯 sync) | 14개 — **분리하지 않음** |
/// | `recentEvents` | **MenuBarPopoverView 하나 (3곳)** | 1개 — **이것만 분리** |
///
/// `recentWatchEvents` 를 빼면 14개 View 의존성을 전부 재매핑해야 한다(09-26 보류 전례).
/// 중복 신호의 원인이 `recentEvents` 였으므로 **원인 필드만 자르면 된다.**
@MainActor
final class RecentEventsStore: ObservableObject {
    static let shared = RecentEventsStore()

    /// 최근 로그 텍스트 상한
    nonisolated static let maxTexts = 20

    /// 최신 것이 맨 앞
    @Published private(set) var texts: [String] = []

    private init() {}

    /// 1회 대입 — 중간 상태(21건) 관측 방지.
    /// `@Published` 는 대입마다 `objectWillChange` 를 발화하므로 insert 와 trim 을 나눠 하면
    /// **상한을 넘긴 중간 상태**가 관측된다. 게다가 링이 가득 찬 상태에서 in-place `removeLast()` 를
    /// 쓰면 `willChange` 가 **두 번** 난다(실측).
    func push(_ text: String) {
        var next = texts
        next.insert(text, at: 0)
        if next.count > Self.maxTexts {
            next.removeLast(next.count - Self.maxTexts)
        }
        texts = next
    }
}
