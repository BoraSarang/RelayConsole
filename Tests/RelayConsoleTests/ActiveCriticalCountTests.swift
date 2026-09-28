import XCTest
@testable import RelayConsole

/// 미해소 critical 카운트 — **엉뚱한 숫자를 쓰면 메뉴바 점과 브리핑이 함께 거짓말**한다
final class ActiveCriticalCountTests: XCTestCase {

    private func ev(_ kind: WatchKind, _ sev: WatchSeverity, _ at: Int,
                    clear: Bool = false, serial: String = "S1") -> WatchEvent {
        WatchEvent(
            kind: kind, severity: sev, serial: serial,
            title: "t", detail: "d",
            at: Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(at)),
            isClear: clear
        )
    }

    /// 저장 포맷은 **최신 우선**(인덱스 0 이 가장 최근)
    private func newestFirst(_ events: [WatchEvent]) -> [WatchEvent] {
        events.sorted { $0.at > $1.at }
    }

    func testNoEventsIsZero() {
        XCTAssertEqual(BriefingLogic.activeCriticalCount([]), 0)
    }

    func testActiveCriticalCountsOne() {
        let e = newestFirst([ev(.throttling, .critical, 0)])
        XCTAssertEqual(BriefingLogic.activeCriticalCount(e), 1)
    }

    func testClearedIsNotCounted() {
        // 최신 clear 가 위에 있어야 해제된다
        let e = newestFirst([
            ev(.throttling, .info, 10, clear: true),
            ev(.throttling, .critical, 0),
        ])
        XCTAssertEqual(BriefingLogic.activeCriticalCount(e), 0, "해소된 critical 을 세면 안 된다")
    }

    /// ★ 같은 지문의 반복 enter 는 **1개**여야 한다 (스택되면 카운터가 부풀어 오른다)
    func testRepeatedEnterCountsOnce() {
        let e = newestFirst([
            ev(.throttling, .critical, 120),
            ev(.throttling, .critical, 60),
            ev(.throttling, .critical, 0),
        ])
        XCTAssertEqual(BriefingLogic.activeCriticalCount(e), 1,
                       "쿨다운 재진입이 3번이어도 미해소 지문은 1개다")
    }

    /// ★ 이것이 76 의 출처 — 오래된 clear 가 **저장 상한에 밀려나면**
    /// 오래된 enter 는 영영 "해소된 적 없음" 으로 남는다
    func testClearFallingOffTheTailStillResolves() {
        var events: [WatchEvent] = [
            ev(.throttling, .info, 1000, clear: true),   // 오래된 clear (곧 잘려 나감)
            ev(.throttling, .critical, 0),
        ]
        // 최신 이벤트 3건만 남도록 상한 적용 — 오래된 clear 가 사라진다
        let kept = newestFirst(Array((events + (0..<3).map { ev(.throttling, .critical, 2000 + $0 * 10) })))
            .prefix(3)
        events = Array(kept)
        XCTAssertFalse(events.contains { $0.isClear },
                       "전제: 오래된 clear 는 상한에 밀려나 사라진다")
        XCTAssertEqual(BriefingLogic.activeCriticalCount(events), 1,
                       "지문당 1개여야 한다 — enter 3건이 스택되면 3이 된다")
    }

    /// 서로 다른 지문은 각각 센다
    func testDistinctFingerprintsCountSeparately() {
        let e = newestFirst([
            ev(.throttling, .critical, 0, serial: "A"),
            ev(.throttling, .critical, 0, serial: "B"),
            ev(.crash, .critical, 0, serial: "A"),
        ])
        XCTAssertEqual(BriefingLogic.activeCriticalCount(e), 3)
    }

    /// warning/info 는 critical 카운터에 넣지 않는다
    func testNonCriticalNotCounted() {
        let e = newestFirst([
            ev(.throttling, .warning, 0),
            ev(.loadSpike, .info, 0),
        ])
        XCTAssertEqual(BriefingLogic.activeCriticalCount(e), 0)
    }

    /// clear 뒤에 새 enter 가 또 오면 다시 미해소 — **시각순으로** 판단해야 한다
    ///
    /// 이게 버그의 핵심이었다. 이벤트는 **최신 우선**으로 저장되므로 인덱스가 작을수록
    /// 최근이다. 예전 구현은 "앞쪽에 clear 가 있나" 만 봤는데, 그건
    /// **[최신 enter] [clear] [오래된 enter]** 순서에서 최신 enter 까지 지워버렸다.
    /// 시각순으로 보면 clear 가 먼저고 enter 가 나중이므로 **미해소**가 맞다.
    func testEnterAfterClearIsActiveAgain() {
        let chronological = [
            ev(.throttling, .critical, 0),    // 오래된 enter
            ev(.throttling, .info, 100, clear: true),  // 해소
            ev(.throttling, .critical, 200),  // 다시 진입 → 미해소
        ]
        XCTAssertEqual(BriefingLogic.activeCriticalCount(chronological), 1,
                       "해소된 뒤 다시 진입했으므로 1개 (입력은 시각순)")
        // 저장 순서(최신 우선)로도 같은 답이어야 한다 — 순서와 무관해야 한다
        XCTAssertEqual(BriefingLogic.activeCriticalCount(newestFirst(chronological)), 1,
                       "저장 순서(최신 우선)로도 1개여야 한다")
    }
}
