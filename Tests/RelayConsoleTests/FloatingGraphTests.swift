import XCTest
@testable import RelayConsole

final class FloatingGraphTests: XCTestCase {
    typealias Metric = FloatingGraphLogic.Metric
    typealias FloatWin = FloatingGraphLogic.FloatWin

    // MARK: - 창 리스트 저장/마이그레이션

    func testDecodeWinsRoundTrip() {
        let wins = [
            FloatWin(id: UUID(), metric: .network, serial: "SER1", frame: "20,1082,300,220"),
            FloatWin(id: UUID(), metric: .memory, serial: "SER2", frame: "340,700,300,180")
        ]
        let json = FloatingGraphLogic.encodeWins(wins)
        let back = FloatingGraphLogic.decodeWins(json)
        XCTAssertEqual(back, wins)
    }

    func testDecodeWinsCorruptReturnsEmpty() {
        XCTAssertTrue(FloatingGraphLogic.decodeWins(nil).isEmpty)
        XCTAssertTrue(FloatingGraphLogic.decodeWins("").isEmpty)
        XCTAssertTrue(FloatingGraphLogic.decodeWins("not json").isEmpty)
        XCTAssertTrue(FloatingGraphLogic.decodeWins("[]").isEmpty)
    }

    func testDecodeWinsCapsAtMax() {
        let many = (0..<10).map {
            FloatWin(id: UUID(), metric: .network, serial: "S\($0)", frame: "")
        }
        let back = FloatingGraphLogic.decodeWins(FloatingGraphLogic.encodeWins(many))
        XCTAssertEqual(back.count, FloatingGraphLogic.maxWindows)
    }

    func testMigrateWinsFromLegacyOriginAndToggles() {
        let wins = FloatingGraphLogic.migrateWins(
            origin: "20,1082,300,220",
            network: true, cpu: true, gpu: false, memory: false,
            serial: "SER1"
        )
        XCTAssertEqual(wins.count, 2)
        XCTAssertEqual(wins.map(\.metric), [.network, .cpu])
        XCTAssertEqual(wins.map(\.serial), ["SER1", "SER1"])
        XCTAssertEqual(wins[0].frame, "20,1082,300,220")
        XCTAssertEqual(wins[1].frame, "20,1082,300,220")
    }

    func testMigrateWinsAllOffForcesNetwork() {
        let wins = FloatingGraphLogic.migrateWins(
            origin: nil,
            network: false, cpu: false, gpu: false, memory: false,
            serial: ""
        )
        XCTAssertEqual(wins.count, 1)
        XCTAssertEqual(wins[0].metric, .network)
        XCTAssertEqual(wins[0].frame, "")
    }

    // MARK: - 창 조작

    func testOpenWindowRejectsAtCapacity() {
        var wins: [FloatWin] = []
        for _ in 0..<FloatingGraphLogic.maxWindows {
            XCTAssertTrue(FloatingGraphLogic.openWindow(metric: .network, serial: "S", wins: &wins))
        }
        XCTAssertEqual(wins.count, FloatingGraphLogic.maxWindows)
        XCTAssertFalse(FloatingGraphLogic.openWindow(metric: .cpu, serial: "S", wins: &wins))
        XCTAssertEqual(wins.count, FloatingGraphLogic.maxWindows)
    }

    func testToggleMetricOpensThenClosesAllOfThatMetric() {
        var wins: [FloatWin] = []
        XCTAssertTrue(FloatingGraphLogic.toggleMetric(.cpu, serial: "S", wins: &wins))
        XCTAssertEqual(wins.count, 1)
        XCTAssertEqual(wins[0].metric, .cpu)
        // 같은 지표가 이미 있으면 전부 닫힘
        XCTAssertFalse(FloatingGraphLogic.toggleMetric(.cpu, serial: "S", wins: &wins))
        XCTAssertTrue(wins.isEmpty)
        XCTAssertFalse(FloatingGraphLogic.isOpen(.cpu, wins: wins))
    }

    func testSetMetricKeepsIdAndFrame() {
        let id = UUID()
        var wins = [FloatWin(id: id, metric: .network, serial: "SER1", frame: "10,20,300,220")]
        FloatingGraphLogic.setMetric(id: id, metric: .gpu, wins: &wins)
        XCTAssertEqual(wins[0].id, id)
        XCTAssertEqual(wins[0].metric, .gpu)
        XCTAssertEqual(wins[0].frame, "10,20,300,220")
    }

    func testSetSerialKeepsIdAndFrame() {
        let id = UUID()
        var wins = [FloatWin(id: id, metric: .network, serial: "SER1", frame: "10,20,300,220")]
        FloatingGraphLogic.setSerial(id: id, serial: "SER2", wins: &wins)
        XCTAssertEqual(wins[0].id, id)
        XCTAssertEqual(wins[0].serial, "SER2")
        XCTAssertEqual(wins[0].frame, "10,20,300,220")
        // 알 수 없는 id는 무시
        FloatingGraphLogic.setSerial(id: UUID(), serial: "SER3", wins: &wins)
        XCTAssertEqual(wins[0].serial, "SER2")
    }

    func testCloseWindowRemovesOnlyThatWindow() {
        let keep = FloatWin(id: UUID(), metric: .network, serial: "S", frame: "")
        let drop = FloatWin(id: UUID(), metric: .cpu, serial: "S", frame: "")
        var wins = [keep, drop]
        FloatingGraphLogic.closeWindow(id: drop.id, wins: &wins)
        XCTAssertEqual(wins, [keep])
    }

    // MARK: - Arrange / Cascade

    func testArrangeStacksVerticallyFromTopLeft() {
        var wins = (0..<3).map {
            FloatWin(id: UUID(), metric: .network, serial: "S", frame: "\($0),0,300,200")
        }
        let area = NSRect(x: 0, y: 0, width: 1000, height: 800)
        FloatingGraphLogic.arrange(wins: &wins, in: area, gap: 10)

        let a = FloatingGraphLogic.parseFrame(wins[0].frame)!.topLeft
        let b = FloatingGraphLogic.parseFrame(wins[1].frame)!.topLeft
        let c = FloatingGraphLogic.parseFrame(wins[2].frame)!.topLeft
        XCTAssertEqual(a.x, 16, accuracy: 0.01)
        XCTAssertEqual(a.y, 600, accuracy: 0.01)
        XCTAssertEqual(b.x, a.x, accuracy: 0.01)
        XCTAssertEqual(b.y, 390, accuracy: 0.01)
        XCTAssertEqual(c.x, a.x, accuracy: 0.01)
        XCTAssertEqual(c.y, 200, accuracy: 0.01)
    }

    func testArrangeWrapsToNextColumnWhenFull() {
        var wins = (0..<3).map { _ in
            FloatWin(id: UUID(), metric: .network, serial: "S", frame: "0,0,300,200")
        }
        let area = NSRect(x: 0, y: 0, width: 1000, height: 450)
        FloatingGraphLogic.arrange(wins: &wins, in: area, gap: 10)

        let a = FloatingGraphLogic.parseFrame(wins[0].frame)!.topLeft
        let c = FloatingGraphLogic.parseFrame(wins[2].frame)!.topLeft
        XCTAssertEqual(a.x, 16, accuracy: 0.01)
        XCTAssertEqual(a.y, 250, accuracy: 0.01)
        // 3번째는 다음 열로
        XCTAssertEqual(c.x, 326, accuracy: 0.01)
        XCTAssertEqual(c.y, 250, accuracy: 0.01)
    }

    func testArrangeEmptyIsNoop() {
        var wins: [FloatWin] = []
        FloatingGraphLogic.arrange(wins: &wins, in: NSRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertTrue(wins.isEmpty)
    }

    func testCascadeTopLeftNoOccupationKeepsPosition() {
        let p = NSPoint(x: 10, y: 500)
        let size = NSSize(width: 300, height: 200)
        let out = FloatingGraphLogic.cascadeTopLeft(
            p, size: size, occupied: [], in: NSRect(x: 0, y: 0, width: 1000, height: 800)
        )
        XCTAssertEqual(out.x, 10, accuracy: 0.01)
        XCTAssertEqual(out.y, 500, accuracy: 0.01)
    }

    func testCascadeTopLeftShiftsDownWhenOverlapping() {
        let p = NSPoint(x: 10, y: 500)
        let size = NSSize(width: 300, height: 200)
        let occupied = [
            NSRect(x: 10, y: 300, width: 300, height: 200)   // topLeft(10,500)와 겹침
        ]
        let out = FloatingGraphLogic.cascadeTopLeft(
            p, size: size, occupied: occupied, in: NSRect(x: 0, y: 0, width: 1000, height: 800)
        )
        XCTAssertEqual(out.x, 10, accuracy: 0.01)
        XCTAssertEqual(out.y, 288, accuracy: 0.01)
        let rect = NSRect(
            x: out.x, y: out.y - size.height, width: size.width, height: size.height
        )
        XCTAssertFalse(rect.intersects(occupied[0]))
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
