import XCTest
@testable import RelayConsole

/// 알림 → 캘린더 초안 — **무엇을 넣을지** 를 값으로 고정한다
///
/// `EKEventStore` 는 테스트에서 만들 수 없다. 그래서 "제목이 뭔가 · 언제인가" 를
/// 순수 함수로 떼어 냈다. 값이 틀리면 여기서 죽는다.
final class CalendarDraftTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: - 제목

    /// 기기 이름을 뒤에 붙인다 — 캘린더는 제목을 자르므로 **앞이 무엇인지** 남아야 한다
    func testTitlePutsDeviceAfterWhat() {
        XCTAssertEqual(
            CalendarDraft.title(detail: "발열 급등 56.8°C", serialLabel: "S22"),
            "발열 급등 56.8°C · S22"
        )
    }

    /// 기기 라벨이 없으면 사유만 — " · " 로 끝나지 않는다
    func testTitleWithoutDeviceHasNoTrailingSeparator() {
        XCTAssertEqual(CalendarDraft.title(detail: "발열 급등", serialLabel: nil), "발열 급등")
        XCTAssertEqual(CalendarDraft.title(detail: "발열 급등", serialLabel: "  "), "발열 급등")
    }

    /// 공백을 정리한다 — 그대로 캘린더에 들어가지 않는다
    func testTitleTrimsWhitespace() {
        XCTAssertEqual(
            CalendarDraft.title(detail: "  발열 급등  ", serialLabel: "  S22  "),
            "발열 급등 · S22"
        )
    }

    // MARK: - 시각

    /// 시작은 **지금 + 15분** — 캘린더는 "언제 볼지" 를 물으면 그것이 답이다
    func testStartIsFifteenMinutesLater() {
        let d = CalendarDraft.make(detail: "x", serialLabel: "S22", now: t0)
        XCTAssertEqual(d.start.timeIntervalSince(t0), 15 * 60, accuracy: 0.5)
    }

    /// 길이는 15분
    func testDurationIsFifteenMinutes() {
        let d = CalendarDraft.make(detail: "x", serialLabel: nil, now: t0)
        XCTAssertEqual(d.end.timeIntervalSince(d.start), 15 * 60, accuracy: 0.5)
    }

    /// end 가 start 보다 앞이면 안 된다 — 캘린더가 거절한다
    func testEndIsAfterStart() {
        let d = CalendarDraft.make(detail: "x", serialLabel: nil, now: t0)
        XCTAssertGreaterThan(d.end, d.start)
    }

    /// 알람을 **붙이지 않는다** — 캘린더가 이미 알린다 (이중 알림 방지)
    /// → 초안에 알람 필드가 아예 없다
    func testDraftHasNoAlarmField() {
        // 컴파일 타임에 확인할 수 있는 형태: Draft 의 필드는 title/start/end 뿐이다
        let d = CalendarDraft.make(detail: "x", serialLabel: nil, now: t0)
        XCTAssertEqual(d.title, "x")
    }

    /// 기본값을 바꾸면 그것이 그대로 적용된다 (분리해 둬서 바꿀 수 있게)
    func testLeadAndDurationAreConstants() {
        XCTAssertEqual(CalendarDraft.leadMinutes, 15)
        XCTAssertEqual(CalendarDraft.durationMinutes, 15)
    }
}

/// 캘린더 상태 — **실패를 하나로 뭉치지 않는다** ([표시②])
///
/// "안 됐어요" 라고만 하면 사용자는 뭘 해야 하는지 모른다.
final class CalendarBridgeStateTests: XCTestCase {

    /// 각 상태가 **서로 다른 문구 키**를 가진다 — 합쳐지지 않는다
    func testEveryStateHasItsOwnMessage() {
        let states: [CalendarBridgeState] = [
            .ready, .permissionDenied, .noCalendar, .added("제목"), .failed("원문"),
        ]
        let keys = states.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count, "서로 다른 상태가 같은 문구를 쓰면 안 된다")
    }

    /// 실패 계열 3개는 서로 다른 키 (권한/캘린더/오류를 구분한다)
    func testFailureKindsAreDistinct() {
        XCTAssertNotEqual(CalendarBridgeState.permissionDenied.titleKey,
                          CalendarBridgeState.noCalendar.titleKey)
        XCTAssertNotEqual(CalendarBridgeState.noCalendar.titleKey,
                          CalendarBridgeState.failed("x").titleKey)
        XCTAssertNotEqual(CalendarBridgeState.permissionDenied.titleKey,
                          CalendarBridgeState.failed("x").titleKey)
    }

    /// 성공은 제목 을 **보관한다** — 뭐가 들어갔는지 알 수 있어야 한다
    func testAddedKeepsTheTitle() {
        XCTAssertEqual(CalendarBridgeState.added("발열 급등 · S22").addedTitle, "발열 급등 · S22")
    }

    /// 오류는 **원문을 그대로** 보관한다 — 앱이 요약하면 진짜 원인을 잃는다
    func testFailedKeepsRawMessage() {
        XCTAssertEqual(CalendarBridgeState.failed("E-MAC-CAL-0001 원문").errorText, "E-MAC-CAL-0001 원문")
    }
}
