import Foundation
import Testing
@testable import RelayConsole

/// 크래시 자동 진단 — 파서·빈도·저장 (PLAN_auto_diagnose Phase 1)
/// Runner 발동 조건(package·exception·지문)은 ConsoleStore 가드 — 순수 부분만 고정한다.
struct CrashDiagnoseTests {
    private let dropboxSample = """
        Drop box contents: 33 entries
        Searching for: data_app_crash

        ========================================
        2026-10-05 01:23:06 data_app_crash (text, 2348 bytes)
        SystemUptimeMs: 60916
        Process: com.example.app
        PID: 9641
        UID: 10273
        Frozen: false
        Package: com.example.app v4 (0.3.1)
        Foreground: Yes
        Timestamp: 2026-10-05 01:23:06.265+0900

        java.lang.RuntimeException: Unable to create service com.example.app.service.Foo: blah
        \tat android.app.ActivityThread.handleCreateService(ActivityThread.java:5929)
        \tat android.os.Handler.dispatchMessage(Handler.java:110)

        ========================================
        2026-10-05 09:32:46 data_app_crash (text, 2713 bytes)
        Process: com.other.app
        Package: com.other.app v1 (1)
        Foreground: No
        Timestamp: 2026-10-05 09:32:46.000+0900

        java.lang.NullPointerException: Attempt to invoke virtual method on a null object reference
        \tat com.other.app.Main.onCreate(Main.java:10)
        """

    @Test func parsesDropboxEntries() {
        let entries = CrashDropboxParser.parse(dropboxSample)
        #expect(entries.count == 2)
        #expect(entries[0].package == "com.example.app")
        #expect(entries[0].foreground == true)
        #expect(entries[0].at == "2026-10-05 01:23:06")
        #expect(entries[0].exceptionHead?.hasPrefix("java.lang.RuntimeException:") == true)
        #expect(entries[1].package == "com.other.app")
        #expect(entries[1].foreground == false)
    }

    @Test func stackLinesAreNotExceptions() {
        #expect(!CrashDropboxParser.looksLikeException("at android.app.ActivityThread.handleCreateService(ActivityThread.java:5929)"))
        #expect(CrashDropboxParser.looksLikeException("java.lang.RuntimeException: x"))
        #expect(CrashDropboxParser.looksLikeException("android.app.ForegroundServiceStartNotAllowedException: y"))
        #expect(!CrashDropboxParser.looksLikeException("Process: com.example.app"))
    }

    @Test func emptyOrForeignTextYieldsNothing() {
        #expect(CrashDropboxParser.parse("").isEmpty)
        #expect(CrashDropboxParser.parse("some log without entries").isEmpty)
    }

    private func crash(
        package: String?,
        exception: String?,
        at: Date,
        isClear: Bool = false
    ) -> WatchEvent {
        WatchEvent(
            kind: .crash,
            severity: .critical,
            serial: "S1",
            title: "T",
            detail: "D",
            at: at,
            isClear: isClear,
            packageName: package,
            exceptionClass: exception
        )
    }

    @Test func frequencyCountsSamePackageAndException() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            crash(package: "com.a", exception: "E1", at: now.addingTimeInterval(-100)),
            crash(package: "com.a", exception: "E1", at: now.addingTimeInterval(-200)),
            crash(package: "com.a", exception: "E2", at: now.addingTimeInterval(-300)),
            crash(package: "com.b", exception: "E1", at: now.addingTimeInterval(-400)),
            crash(package: "com.a", exception: "E1", at: now.addingTimeInterval(-8 * 24 * 3600)),
            crash(package: "com.a", exception: "E1", at: now.addingTimeInterval(-500), isClear: true),
        ]
        let r = CrashFrequency.summarize(events: events, package: "com.a", exception: "E1", now: now)
        // 동일 패키지+예외 2건만 — 다른 예외·다른 패키지·8일 전·clear 제외
        #expect(r.count == 2)
        #expect(r.first == now.addingTimeInterval(-200))
    }
}

@MainActor
struct DiagnoseStoreTests {
    @Test func roundTrip() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-diagnose-test-\(UUID().uuidString)")
        let store = DiagnoseStore(url: dir.appendingPathComponent("diagnoses.json"))
        #expect(store.get(fingerprint: "fp1") == nil)
        let d = CrashDiagnose(
            fingerprint: "fp1", package: "com.a", exception: "E1",
            foreground: true, count7d: 2, dropboxAt: "2026-10-05 01:23:06",
            diagnosedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        store.put(d)
        // queue 비동기 저장이 끝나길 기다린다 (소형 파일이라 즉시 수준)
        Thread.sleep(forTimeInterval: 0.5)
        let reloaded = DiagnoseStore(url: dir.appendingPathComponent("diagnoses.json"))
        #expect(reloaded.get(fingerprint: "fp1") == d)
        try? FileManager.default.removeItem(at: dir)
    }
}
