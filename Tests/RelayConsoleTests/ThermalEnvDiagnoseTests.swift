import Foundation
import Testing
@testable import RelayConsole

/// 자동 진단 Phase 2 (발열) + Phase 3 (셀·배터리 패턴) — PLAN_auto_diagnose
/// 트리거 가드·발동은 스토어/엔진 영역이라 순수 부분만 고정한다.
struct ThermalDiagnoseTests {
    private func row(_ name: String, cpu: Double?) -> ProcessRow {
        ProcessRow(name: name, cpuPercent: cpu, rssMB: nil, pid: nil, path: nil, netMBps: nil)
    }

    @Test func suspectPicksMaxCpu() {
        let top = ThermalSuspect.pick(from: [row("a", cpu: 3.1), row("b", cpu: 38.4), row("c", cpu: nil)])
        #expect(top?.name == "b")
        #expect(top?.cpu == 38.4)
    }

    @Test func suspectNilWithoutData() {
        // 자료가 없으면 주범을 지어내지 않는다 — 줄 생략
        #expect(ThermalSuspect.pick(from: nil) == nil)
        #expect(ThermalSuspect.pick(from: []) == nil)
        #expect(ThermalSuspect.pick(from: [row("a", cpu: nil)]) == nil)
    }

    @Test func topZonesSortedDescCapped() {
        let zones = [
            ThermalZone(name: "a", tempC: 30),
            ThermalZone(name: "b", tempC: 47.1),
            ThermalZone(name: "c", tempC: 45.0),
            ThermalZone(name: "d", tempC: 27.0),
        ]
        let top = ThermalSuspect.topZones(zones)
        #expect(top.map(\.name) == ["b", "c", "a"])
        #expect(ThermalSuspect.topZones(nil).isEmpty)
    }

    @Test func hotspotNeedsEqualGatewayAndDeviceIP() {
        #expect(ThermalSuspect.isHotspot(gateway: "10.0.0.1", deviceIP: "10.0.0.1"))
        #expect(!ThermalSuspect.isHotspot(gateway: "10.0.0.1", deviceIP: "10.0.0.2"))
        #expect(!ThermalSuspect.isHotspot(gateway: nil, deviceIP: "10.0.0.1"))
        #expect(!ThermalSuspect.isHotspot(gateway: "", deviceIP: ""))
    }

    @Test @MainActor func legacyCrashFileMigrates() throws {
        // Phase 1 파일([String: CrashDiagnose])은 버리지 않고 이관한다.
        // 합성 Decodable는 기본값 때문에 구파일을 "빈 신형"으로 오인하므로 키로 가른다.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-diagnose-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = #"{"fp1":{"fingerprint":"fp1","package":"com.a","exception":"E1","foreground":true,"count7d":2,"diagnosedAt":"2026-10-05T00:00:00Z"}}"#
        try legacy.write(to: dir.appendingPathComponent("diagnoses.json"), atomically: true, encoding: .utf8)
        let store = DiagnoseStore(url: dir.appendingPathComponent("diagnoses.json"))
        #expect(store.get(fingerprint: "fp1")?.package == "com.a")
        #expect(store.getThermal(fingerprint: "fp1") == nil)
    }
}

struct CellSignalTests {
    private let registry = """
        mCellInfo=[CellInfoLte:{mRegistered=YES mTimeStamp=1ns CellIdentityLte:{ mCi=12345 mPci=345 mTac=100 mEarfcn=1550 mBands=[3] mMcc=450 mMnc=08} CellSignalStrengthLte: rssi=-65 rsrp=-95 level=3}
        CellInfoLte:{mRegistered=NO mTimeStamp=1ns CellIdentityLte:{ mCi=2147483647 mPci=360 mEarfcn=1550 mBands=[3]} CellSignalStrengthLte: rssi=-81 rsrp=-106 level=1}
        getRilDataRadioTechnology=14(LTE)
        """

    @Test func servingCellPrefersRegistered() {
        let cell = AdbClient.servingCell(in: registry)
        #expect(cell?.ci == 12345)
        #expect(cell?.pci == 345)
    }

    @Test func sentinelIsNil() {
        #expect(AdbClient.servingCell(in: "CellIdentityLte:{ mCi=2147483647 mPci=360 mEarfcn=1550}") == nil)
        #expect(AdbClient.servingCell(in: "no cell here") == nil)
    }

    @Test func parseSignalCarriesCell() {
        let s = AdbClient.parseSignal(registry)
        #expect(s.cellCi == 12345)
        #expect(s.cellPci == 345)
    }

    @Test func recordOnlyOnChange() {
        let store = CellHistory(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-cell-test-\(UUID().uuidString).json"))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.record(serial: "S", ci: 1, pci: 10, rsrp: -95, at: t0)
        store.record(serial: "S", ci: 1, pci: 10, rsrp: -96, at: t0.addingTimeInterval(5))
        store.record(serial: "S", ci: 2, pci: 10, rsrp: -100, at: t0.addingTimeInterval(10))
        store.record(serial: "S", ci: nil, pci: nil, rsrp: -100, at: t0.addingTimeInterval(15))
        let h = store.history(serial: "S")
        // 동일 셀 재기록·모름(nil)은 저장 안 함 — 바뀔 때만
        #expect(h.count == 2)
        #expect(h[1].ci == 2)
        #expect(CellHistory.isCellChange(last: h[0], ci: 2, pci: 10))
        #expect(!CellHistory.isCellChange(last: h[0], ci: nil, pci: nil))
    }
}

struct EnvPatternTests {
    private func drop(at: Date) -> WatchEvent {
        WatchEvent(kind: .signalDrop, severity: .warning, serial: "S",
                   title: "T", detail: "D", at: at)
    }

    @Test func drainNeedsDischargeAndSpan() {
        // 10%p / 1h → 10.0
        #expect(EnvPatterns.drainRatePctPerHour(levels: [80, 70], windowSeconds: 3600) == 10.0)
        // 충전 중(올라감)은 소모율이 아니다
        #expect(EnvPatterns.drainRatePctPerHour(levels: [70, 80], windowSeconds: 3600) == nil)
        // 자료 부족
        #expect(EnvPatterns.drainRatePctPerHour(levels: [80], windowSeconds: 3600) == nil)
        #expect(EnvPatterns.drainRatePctPerHour(levels: [80, 70], windowSeconds: 100) == nil)
    }

    @Test func summarizeCounts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cells = [
            CellSample(at: now.addingTimeInterval(-100), ci: 1, pci: 10, rsrp: -95),
            CellSample(at: now.addingTimeInterval(-200), ci: 2, pci: 10, rsrp: -100),
            CellSample(at: now.addingTimeInterval(-8 * 24 * 3600), ci: 9, pci: 9, rsrp: -80),
        ]
        let drops = [
            drop(at: now.addingTimeInterval(-100)),
            drop(at: now.addingTimeInterval(-8 * 24 * 3600)),
        ]
        let s = EnvPatterns.summarize(
            cells: cells, dropEvents: drops,
            levels: [90, 80], windowSeconds: 3600,
            serial: "S", now: now
        )
        // 7일 내 2건 → 전이 1회 · 서로 다른 셀 2개 · 급락 1회 · 10%/h
        #expect(s.cellChanges7d == 1)
        #expect(s.distinctCells7d == 2)
        #expect(s.drops7d == 1)
        #expect(s.drainPctPerHour == 10.0)
        #expect(!s.isEmpty)
    }

    @Test func emptyWhenNothing() {
        let s = EnvPatterns.summarize(
            cells: [], dropEvents: [], levels: [], windowSeconds: nil,
            serial: "S", now: Date()
        )
        #expect(s.isEmpty)
    }
}
