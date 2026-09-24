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

    func testTopLeftOfFrame() {
        let frame = NSRect(x: 100, y: 400, width: 300, height: 150)
        let tl = FloatingGraphLogic.topLeft(of: frame)
        XCTAssertEqual(tl.x, 100)
        XCTAssertEqual(tl.y, 550)
    }

    func testBottomLeftFromTopLeft() {
        let bl = FloatingGraphLogic.bottomLeft(fromTopLeft: NSPoint(x: 100, y: 550), height: 150)
        XCTAssertEqual(bl.x, 100)
        XCTAssertEqual(bl.y, 400)
    }

    func testTopLeftSaveRestoresSameTopAfterHeightChange() {
        // 하단 저장 버그 재현: 높이가 달라도 상단 y는 유지되어야 함
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 900)
        let original = NSRect(x: 200, y: 500, width: 300, height: 320)
        let saved = FloatingGraphLogic.topLeft(of: original)

        let createHeight: CGFloat = 200
        let createBottom = FloatingGraphLogic.bottomLeft(fromTopLeft: saved, height: createHeight)
        XCTAssertEqual(createBottom.y + createHeight, original.maxY, "생성 직후 상단이 원래 상단과 일치")

        // fitToContent와 동일: 상단 고정으로 높이 조정
        var fitBottom = createBottom
        fitBottom.y += createHeight - original.height
        XCTAssertEqual(fitBottom.y + original.height, original.maxY, "fit 후에도 상단 유지")
        XCTAssertEqual(fitBottom.y, original.minY, "원래 높이로 돌아가면 원래 하단도 일치")
    }

    func testClampTopLeftKeepsWindowOnScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 300, height: 200)
        let clamped = FloatingGraphLogic.clampTopLeft(NSPoint(x: -50, y: 900), size: size, in: screen)
        XCTAssertEqual(clamped.x, 0)
        XCTAssertEqual(clamped.y, 800)
        let clamped2 = FloatingGraphLogic.clampTopLeft(NSPoint(x: 999, y: 10), size: size, in: screen)
        XCTAssertEqual(clamped2.x, 700)
        XCTAssertEqual(clamped2.y, 200)
    }

    func testSavableFrameRejectsDegenerate() {
        XCTAssertTrue(FloatingGraphLogic.isSavableFrame(NSRect(x: 20, y: 682, width: 300, height: 200)))
        XCTAssertFalse(FloatingGraphLogic.isSavableFrame(NSRect(x: 20, y: 682, width: 300, height: 0)))
        XCTAssertFalse(FloatingGraphLogic.isSavableFrame(NSRect(x: 20, y: 682, width: 300, height: 40)))
        XCTAssertFalse(FloatingGraphLogic.isSavableFrame(NSRect(x: 0, y: 0, width: 0, height: 200)))
    }

    func testDefaultTopLeftIsLeftEdge() {
        // 저장값 없을 때 오른쪽이 아니라 왼쪽 기준
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 900)
        let size = NSSize(width: 300, height: 200)
        let defaultTopLeft = NSPoint(x: screen.minX + 20, y: screen.maxY - 48)
        let clamped = FloatingGraphLogic.clampTopLeft(defaultTopLeft, size: size, in: screen)
        XCTAssertEqual(clamped.x, 20)
        XCTAssertLessThan(clamped.x, screen.midX)
    }

    func testClampOpacityValid() {
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(1.0), 1.0)
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(0.5), 0.5)
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(FloatingGraphLogic.minOpacity), FloatingGraphLogic.minOpacity)
    }

    func testClampOpacityOutOfRange() {
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(0.1), FloatingGraphLogic.minOpacity)
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(1.5), FloatingGraphLogic.maxOpacity)
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(-1), FloatingGraphLogic.minOpacity)
    }

    func testClampOpacityNonFinite() {
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(.nan), FloatingGraphLogic.defaultOpacity)
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(.infinity), FloatingGraphLogic.defaultOpacity)
        XCTAssertEqual(FloatingGraphLogic.clampOpacity(-.infinity), FloatingGraphLogic.defaultOpacity)
    }

    func testStoredOpacityDefault() {
        let d = UserDefaults(suiteName: "FloatingGraphTests.\(UUID().uuidString)")!
        defer { d.removePersistentDomain(forName: d.description) }
        XCTAssertEqual(FloatingGraphLogic.storedOpacity(d), FloatingGraphLogic.defaultOpacity)
        d.set(0.6, forKey: FloatingGraphLogic.opacityKey)
        XCTAssertEqual(FloatingGraphLogic.storedOpacity(d), 0.6, accuracy: 0.0001)
        d.set(9.9, forKey: FloatingGraphLogic.opacityKey)
        XCTAssertEqual(FloatingGraphLogic.storedOpacity(d), FloatingGraphLogic.maxOpacity)
    }
}
