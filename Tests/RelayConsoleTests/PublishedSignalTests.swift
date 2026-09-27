import Foundation
import Testing
import Combine
import SwiftUI
@testable import RelayConsole

/// 알림 유입이 만드는 `objectWillChange` 횟수 — 2026-09-28 `recentEvents` 분리
/// (`PLAN_published_split_recentevents_relayconsole`)
///
/// ## 왜 이 테스트가 중요하나
///
/// `ConsoleStore` 는 View 에 `@ObservedObject` 로 통째로 관찰된다. `@Published` 대입 하나가
/// **관찰 중인 모든 View** 의 body 를 재평가시킨다. 알림 1건이 2회 불렀다면, 2번째는
/// 인사이트 캐시가 이미 0ms 로 만들어 둔 **그 아무도 필요로 하지 않는 신호**였다.
///
/// 중복 신호는 조용히 **되돌아오기 쉽다** — 필드 하나를 다시 `ConsoleStore` 에 붙이는 것만으로
/// 모든 View 가 다시 무효화된다. 계측 없이도 눈에 보이지 않는다. 그래서 횟수를 고정한다.
///
/// ## 이 테스트가 결정적인 이유
///
/// `ConsoleStore.init` 이 `private` 이라 격리 인스턴스를 만들 수 없다(컴파일 에러로 확인).
/// 그래서 `shared` 에 의존하고, 병렬 실행 잡음이 걱정된다.
/// **신호를 세는 구간이 동기 + `@MainActor` 이면** MainActor 는 조정하지 않으므로
/// `await` 이 없는 그 구간에 다른 MainActor 태스크가 끼어들 수 없다.
/// → `swift-testing` 의 병렬 실행과 무관하게 결정적이다.
@MainActor
struct PublishedSignalTests {
    // MARK: - 중복 신호 제거 (이번 작업의 핵심)

    /// 알림 1건이 `ConsoleStore` 를 **1번만** 무효화해야 한다
    @Test func alertIngestFiresExactlyOneObjectWillChange() {
        let store = ConsoleStore.shared
        var count = 0
        let sub = store.objectWillChange.sink { _ in count += 1 }
        defer { sub.cancel() }

        store.debugIngestWatchQuietly(
            WatchEvent(kind: .signalDrop, severity: .warning, serial: "SIGTEST",
                       title: "SIGTEST", detail: "1", at: Date())
        )

        #expect(count == 1, "알림 1건이 objectWillChange \(count)회 — 1회를 기대한다")
    }

    /// 최근 로그 추가는 `ConsoleStore` 를 건드리지 않아야 한다
    @Test func recentEventsPushDoesNotInvalidateConsoleStore() {
        let store = ConsoleStore.shared
        let events = RecentEventsStore.shared
        var storeCount = 0
        var eventsCount = 0
        let subA = store.objectWillChange.sink { _ in storeCount += 1 }
        let subB = events.objectWillChange.sink { _ in eventsCount += 1 }
        defer { subA.cancel(); subB.cancel() }

        events.push("SIGTEST-PUSH")

        #expect(storeCount == 0, "최근 로그 추가가 ConsoleStore 를 \(storeCount)회 무효화했다")
        #expect(eventsCount == 1, "RecentEventsStore 는 정확히 1회여야 한다 (지금 \(eventsCount))")
    }

    /// `ConsoleStore.pushEvent` 포워딩이 분리된 스토어로만 가야 한다
    @Test func consoleStorePushEventForwardsToSeparatedStore() {
        let store = ConsoleStore.shared
        let events = RecentEventsStore.shared
        var storeCount = 0
        let sub = store.objectWillChange.sink { _ in storeCount += 1 }
        defer { sub.cancel() }

        let before = events.texts.count
        store.pushEvent("SIGTEST-FORWARD")
        let after = events.texts.count

        #expect(storeCount == 0, "pushEvent 가 ConsoleStore 를 \(storeCount)회 무효화했다")
        #expect(after == min(before + 1, RecentEventsStore.maxTexts), "분리된 스토어에 반영돼야 한다")
    }

    // MARK: - 1회 대입이 왜 필요한가 (근거 고정)

    /// `@Published` 배열의 **in-place 변이**는 링이 가득 차면 `willChange` 를 두 번 낸다.
    /// 1회 대입이 필요한 이유를 문서 주석이 아니라 **테스트**로 남긴다.
    @Test func inPlaceMutationFiresTwiceWhenRingIsFull() {
        final class Probe: ObservableObject {
            @Published var items: [Int] = []
            /// 실제 코드 패턴 — 복사 후 1회 대입
            func assignOnce(_ v: Int, cap: Int) {
                var next = items
                next.insert(v, at: 0)
                if next.count > cap { next.removeLast(next.count - cap) }
                items = next
            }
            /// 사고가 쉬운 패턴 — in-place 변이
            func mutateInPlace(_ v: Int, cap: Int) {
                items.insert(v, at: 0)
                if items.count > cap { items.removeLast() }
            }
        }

        // 링이 가득 찬 상태에서 한 건 더 넣어야 trim 이 발화한다.
        // (빈 링에 1건 넣으면 `count > cap` 이 거짓이라 removeLast 가 아예 발동하지 않는다)
        let assign = Probe()
        assign.assignOnce(0, cap: 1)   // 예열 — 링을 가득 채운다 (측정 밖)
        var assignCount = 0
        let subA = assign.objectWillChange.sink { _ in assignCount += 1 }
        assign.assignOnce(1, cap: 1)   // 링이 가득 찬 상태에서 추가
        #expect(assignCount == 1, "1회 대입은 늘 1회여야 한다 (지금 \(assignCount))")
        subA.cancel()

        let mutate = Probe()
        mutate.mutateInPlace(0, cap: 1)  // 예열 — 링을 가득 채운다 (측정 밖)
        var mutateCount = 0
        let subB = mutate.objectWillChange.sink { _ in mutateCount += 1 }
        mutate.mutateInPlace(1, cap: 1)  // 링이 가득 찬 상태에서 추가
        #expect(mutateCount == 2, "in-place 변이는 링이 차면 2회다 (지금 \(mutateCount))")
        subB.cancel()
    }

    // MARK: - 상한 중간 상태

    /// 상한을 넘긴 중간 상태가 관측되지 않아야 한다 (차곡차곡히 삭제가 아니라 한 번에 대입)
    @Test func recentEventsStoreNeverExposesOverCapState() {
        let events = RecentEventsStore.shared
        var observedOverCap = false
        let sub = events.objectWillChange.sink { [weak events] _ in
            if let events, events.texts.count > RecentEventsStore.maxTexts {
                observedOverCap = true
            }
        }
        defer { sub.cancel() }

        for i in 0..<(RecentEventsStore.maxTexts + 15) {
            events.push("CAP-\(i)")
        }

        #expect(observedOverCap == false, "상한 초과 상태가 관측됐다")
        #expect(events.texts.count == RecentEventsStore.maxTexts, "상한이 지켜져야 한다")
    }
}
