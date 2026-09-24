import XCTest
@testable import RelayConsole

final class FloatingGraphTests: XCTestCase {
    func testAllOffForcesNetwork() {
        let r = FloatingGraphLogic.resolve(network: false, cpu: false, gpu: false, memory: false)
        XCTAssertTrue(r.network)
        XCTAssertFalse(r.cpu)
        XCTAssertFalse(r.gpu)
        XCTAssertFalse(r.memory)
    }

    func testKeepsValidSelection() {
        let r = FloatingGraphLogic.resolve(network: true, cpu: true, gpu: false, memory: false)
        XCTAssertEqual(r, .init(network: true, cpu: true, gpu: false, memory: false))
    }

    func testNetworkOnlyStillValid() {
        let r = FloatingGraphLogic.resolve(network: true, cpu: false, gpu: false, memory: false)
        XCTAssertTrue(r.network)
        XCTAssertFalse(r.cpu)
    }

    func testCPUWithoutNetworkStays() {
        // 사용자가 network를 끄고 cpu만 켠 경우 — network always-on이 아님(PLAN: 전부 off만 방지)
        let r = FloatingGraphLogic.resolve(network: false, cpu: true, gpu: false, memory: false)
        XCTAssertFalse(r.network)
        XCTAssertTrue(r.cpu)
    }

    func testParseOriginValid() {
        let p = FloatingGraphLogic.parseOrigin("120.5,-40.25")
        XCTAssertEqual(p?.x, 120.5)
        XCTAssertEqual(p?.y, -40.25)
    }

    func testParseOriginInvalid() {
        XCTAssertNil(FloatingGraphLogic.parseOrigin(nil))
        XCTAssertNil(FloatingGraphLogic.parseOrigin(""))
        XCTAssertNil(FloatingGraphLogic.parseOrigin("abc"))
        XCTAssertNil(FloatingGraphLogic.parseOrigin("1,2,3"))
        XCTAssertNil(FloatingGraphLogic.parseOrigin("a,b"))
    }

    func testFormatOriginRoundTrip() {
        let p = NSPoint(x: 10, y: 20)
        let s = FloatingGraphLogic.formatOrigin(p)
        let back = FloatingGraphLogic.parseOrigin(s)
        XCTAssertEqual(back?.x, 10)
        XCTAssertEqual(back?.y, 20)
    }
}
