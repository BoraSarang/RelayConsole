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

    // MARK: - frame 저장 포맷 (x,y,w,h) + 하위호환

    func testParseFrameLegacyPointOnly() {
        let f = FloatingGraphLogic.parseFrame("120.5,-40.25")
        XCTAssertEqual(f?.topLeft.x, 120.5)
        XCTAssertEqual(f?.topLeft.y, -40.25)
        XCTAssertEqual(f?.size.width, 300)
        XCTAssertEqual(f?.size.height, 200)
    }

    func testParseFrameWithSize() {
        let f = FloatingGraphLogic.parseFrame("10, 20, 640, 480")
        XCTAssertEqual(f?.topLeft.x, 10)
        XCTAssertEqual(f?.topLeft.y, 20)
        XCTAssertEqual(f?.size.width, 640)
        XCTAssertEqual(f?.size.height, 480)
    }

    func testParseFrameRejectsNilAndGarbage() {
        XCTAssertNil(FloatingGraphLogic.parseFrame(nil))
        XCTAssertNil(FloatingGraphLogic.parseFrame(""))
        XCTAssertNil(FloatingGraphLogic.parseFrame("a,b"))
        XCTAssertNil(FloatingGraphLogic.parseFrame(","))
        XCTAssertNil(FloatingGraphLogic.parseFrame("100"))
    }

    func testParseFrameNonPositiveSizeFallsBackToDefault() {
        let f = FloatingGraphLogic.parseFrame("10,20,0,480")
        XCTAssertEqual(f?.size.width, 300)
        XCTAssertEqual(f?.size.height, 200)
    }

    func testFormatFrameRoundTrip() {
        let p = NSPoint(x: 42, y: 777)
        let s = NSSize(width: 640, height: 460)
        let str = FloatingGraphLogic.formatFrame(topLeft: p, size: s)
        let back = FloatingGraphLogic.parseFrame(str)
        XCTAssertEqual(back?.topLeft, p)
        XCTAssertEqual(back?.size, s)
    }

    func testClampOriginKeepsWindowInsideUnion() {
        let union = NSRect(x: -1000, y: 0, width: 3000, height: 900)
        let size = NSSize(width: 300, height: 200)
        // 왼쪽 밖
        let left = FloatingGraphLogic.clampOrigin(NSPoint(x: -5000, y: 400), size: size, in: union)
        XCTAssertEqual(left.x, union.minX)
        // 오른쪽 밖
        let right = FloatingGraphLogic.clampOrigin(NSPoint(x: 99999, y: 400), size: size, in: union)
        XCTAssertEqual(right.x, union.maxX - size.width)
        // 위 밖
        let top = FloatingGraphLogic.clampOrigin(NSPoint(x: 0, y: 99999), size: size, in: union)
        XCTAssertEqual(top.y, union.maxY - size.height)
        // 아래 밖
        let bottom = FloatingGraphLogic.clampOrigin(NSPoint(x: 0, y: -99999), size: size, in: union)
        XCTAssertEqual(bottom.y, union.minY)
    }

    func testClampOriginWhenWindowTallerThanScreen() {
        let rect = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 300, height: 1200)
        let p = FloatingGraphLogic.clampOrigin(NSPoint(x: 50, y: 400), size: size, in: rect)
        XCTAssertEqual(p.x, 50)
        XCTAssertEqual(p.y, 0, "창이 화면보다 크면 minY에 고정되어 상단이 벗어나지 않도록")
    }

    func testScreenFrameNeverDegenerate() {
        let f = FloatingGraphLogic.screenFrame(containing: NSPoint(x: -99999, y: -99999))
        XCTAssertGreaterThan(f.width, 0)
        XCTAssertGreaterThan(f.height, 0)
    }

    func testUnionFrameCoversAllScreens() {
        let u = FloatingGraphLogic.unionFrame()
        XCTAssertGreaterThan(u.width, 0)
        for s in NSScreen.screens {
            XCTAssertTrue(u.contains(s.frame), "합집합이 모든 화면을 포함해야 함")
        }
    }
}
