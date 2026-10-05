import XCTest
@testable import RelayConsole

/// `/metrics` 텍스트 규약 — 값이 틀리면 **경고가 아니라 오류**가 나야 한다
final class MetricsTextTests: XCTestCase {

    private func snapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            version: "1.16.0",
            build: "1.16.0",
            devices: [
                .init(serial: "ABC123", model: "SM-S901N", connectionKind: "network",
                      isOnline: true, batteryPercent: 87),
                .init(serial: "OFFLINE9", model: "Pixel", connectionKind: "usb",
                      isOnline: false, batteryPercent: nil),
            ],
            activeCriticalAlerts: 2
        )
    }

    private func line(_ name: String, in text: String) -> String? {
        text.split(separator: "\n").first { $0.hasPrefix(name) }.map(String.init)
    }

    // MARK: - 라벨 이스케이프

    func testEscapesBackslashQuoteAndNewline() {
        XCTAssertEqual(MetricsTextBuilder.escapeLabel(#"a\b"#), #"a\\b"#)
        XCTAssertEqual(MetricsTextBuilder.escapeLabel("a\"b"), "a\\\"b")
        XCTAssertEqual(MetricsTextBuilder.escapeLabel("a\nb"), "a\\nb")
        // 순수하게 통과시켜야 하는 문자
        XCTAssertEqual(MetricsTextBuilder.escapeLabel("한글-가나_ok:1"), "한글-가나_ok:1")
    }

    func testLabelWithQuoteDoesNotBreakLine() {
        let snap = MetricsSnapshot(
            version: "1", build: "1",
            devices: [.init(serial: "his\"dev", model: "m", connectionKind: "usb",
                            isOnline: true, batteryPercent: 50)]
        )
        let text = MetricsTextBuilder.render(snap)
        let l = line("relay_device_battery_percent", in: text)
        XCTAssertEqual(l, #"relay_device_battery_percent{serial="his\"dev"} 50"#)
    }

    // MARK: - 값이 있으면 있는 만큼

    func testOnlineDeviceGauges() {
        let text = MetricsTextBuilder.render(snapshot())
        XCTAssertEqual(
            line("relay_device_online{", in: text),
            #"relay_device_online{kind="network",model="SM-S901N",serial="ABC123"} 1"#
        )
        // 오프라인 기기는 **행이 있고 0** — 사라지면 "기기가 사라졌다" 와 구분되지 않는다
        XCTAssertTrue(text.contains(#"relay_device_online{kind="usb",model="Pixel",serial="OFFLINE9"} 0"#))
    }

    func testBatteryUnmeasuredIsAbsentNotZero() {
        let text = MetricsTextBuilder.render(snapshot())
        XCTAssertTrue(text.contains("relay_device_battery_percent{serial=\"ABC123\"} 87"))
        // 미확인(오프라인) 기기의 배터리는 **행이 없어야** 한다 — 0% 는 다른 말이다.
        // (행 수로 센다: 문자열 부분 일치는 `...online{...serial="OFFLINE9"} 0` 과 겹친다)
        XCTAssertEqual(text.components(separatedBy: "relay_device_battery_percent{").count - 1, 1)
    }

    func testCriticalAlertCount() {
        let text = MetricsTextBuilder.render(snapshot())
        XCTAssertEqual(line("relay_alert_active_critical", in: text), "relay_alert_active_critical 2")
    }

    // MARK: - 스펙 형식

    func testEveryFamilyHasHelpAndType() {
        let text = MetricsTextBuilder.render(snapshot())
        let families = Set(
            text.split(separator: "\n")
                .filter { !$0.hasPrefix("#") && !$0.isEmpty }
                .map { String($0.prefix(while: { $0 != "{" && $0 != " " })) }
        )
        XCTAssertFalse(families.isEmpty)
        for f in families {
            XCTAssertTrue(text.contains("# HELP \(f) "), "HELP 없음: \(f)")
            XCTAssertTrue(text.contains("# TYPE \(f) gauge"), "TYPE 없음: \(f)")
        }
    }

    func testEndsWithNewlineAndHasNoBlankLine() {
        let text = MetricsTextBuilder.render(snapshot())
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertFalse(text.contains("\n\n"))
    }

    func testEmptySnapshotStillHasScalars() {
        // 기기 0대여도 값이 있는 스칼라 지표는 **내보낸다** — 빈 응답은 scrape 실패로 보인다
        let text = MetricsTextBuilder.render(MetricsSnapshot(version: "9", build: "9"))
        XCTAssertTrue(text.contains(#"relay_build_info{build="9",version="9"} 1"#))
        XCTAssertTrue(text.contains("relay_alert_active_critical 0"))
        // HELP/TYPE 은 남는다 (리라벨러가 없음을 알 수 있어야 한다)
        XCTAssertTrue(text.contains("# TYPE relay_device_online gauge"))
    }

    func testRenderIsDeterministic() {
        let snap = snapshot()
        XCTAssertEqual(MetricsTextBuilder.render(snap), MetricsTextBuilder.render(snap))
    }

    func testLabelsAreSortedForDeterminism() {
        // 라벨 순서가 뒤섞이면 본문이 흔들린다 — 스크래퍼는 그대로 파싱하지만 비교·diff 가 불가능해진다
        let a = MetricsTextBuilder.lineForTest("m", ["z": "1", "a": "2", "m": "3"], "1")
        XCTAssertEqual(a, #"m{a="2",m="3",z="1"} 1"#)
    }
}
