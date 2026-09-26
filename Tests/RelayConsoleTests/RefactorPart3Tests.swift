import Foundation
import Testing
@testable import RelayConsole

/// 3단계(신선도·정직성) 회귀 테스트
///
/// 핵심은 **"측정하지 못했는데 측정했다고 말하지 않는 것"** 이다.
/// 종전엔 `pollDevice` 가 `isOnline = true` 를 무조건 세팅하고
/// `DeviceInventory.merge` 가 그걸 보고 `lastSampleAt` 을 갱신했다.
/// 결과: adb 가 전부 죽어도 화면은 전부 정상값 + "방금 측정" 으로 표시됐다.
struct RefactorPart3Tests {

    // MARK: - 신선도 정직성

    /// 실제 응답(measuredAt)이 있을 때만 신선도가 올라간다
    @Test func lastSampleAtAdvancesOnlyWhenMeasured() {
        var inv = DeviceInventory()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        var ok = DeviceSnapshot()
        ok.serial = "s1"
        ok.isOnline = true
        ok.measuredAt = t0
        inv.merge(ok, now: t0)
        #expect(inv.device(serial: "s1")?.lastSampleAt == t0)

        // 5분 뒤 adb 무응답 스냅샷 — isOnline 이 true 여도 신선도는 **올라가지 않는다**
        let t1 = t0.addingTimeInterval(300)
        var failed = DeviceSnapshot()
        failed.serial = "s1"
        failed.isOnline = true          // 종전의 함정: 이게 항상 true 였다
        failed.measuredAt = nil         // 실제 응답 없음
        inv.merge(failed, now: t1)
        #expect(inv.device(serial: "s1")?.lastSampleAt == t0, "무응답인데 신선도가 올랐다")
    }

    /// 신규 등록도 measuredAt 없으면 신선도를 찍지 않는다
    @Test func newDeviceWithoutMeasurementHasNoSampleTime() {
        var inv = DeviceInventory()
        var s = DeviceSnapshot()
        s.serial = "ghost"
        s.isOnline = true
        s.measuredAt = nil
        inv.merge(s, now: Date(timeIntervalSince1970: 1000))
        #expect(inv.device(serial: "ghost")?.lastSampleAt == nil)
    }

    /// 응답이 돌아오면 신선도가 다시 올라간다 (실패 후 회복)
    @Test func freshnessRecoversAfterFailure() {
        var inv = DeviceInventory()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var ok = DeviceSnapshot()
        ok.serial = "s1"
        ok.isOnline = true
        ok.measuredAt = t0
        inv.merge(ok, now: t0)

        var bad = DeviceSnapshot()
        bad.serial = "s1"
        bad.isOnline = true
        bad.measuredAt = nil
        inv.merge(bad, now: t0.addingTimeInterval(60))
        #expect(inv.device(serial: "s1")?.lastSampleAt == t0)

        let t2 = t0.addingTimeInterval(120)
        var recovered = DeviceSnapshot()
        recovered.serial = "s1"
        recovered.isOnline = true
        recovered.measuredAt = t2
        inv.merge(recovered, now: t2)
        #expect(inv.device(serial: "s1")?.lastSampleAt == t2)
        #expect(inv.device(serial: "s1")?.offlineSince == nil, "재접속 시 오프라인 경과가 남았다")
    }

    /// 연속 실패 횟수는 스냅샷을 통과한다 (성공 시 0 으로 리셋되는 것은 폴러가 담당)
    @Test func failureStreakTravelsWithSnapshot() {
        var snap = DeviceSnapshot()
        #expect(snap.failureStreak == 0)
        snap.failureStreak = 7
        #expect(snap.failureStreak == 7)
    }

    // MARK: - 오프라인 기기 제거 (R1 의 "온라인 수만 표시" 근본)

    @Test func offlineDeviceIsRetainedBeforeRetentionWindow() {
        var inv = DeviceInventory()
        var s = DeviceSnapshot()
        s.serial = "s1"
        s.isOnline = true
        inv.merge(s)
        inv.markOffline(serial: "s1", now: Date(timeIntervalSince1970: 1000))
        inv.pruneOffline(olderThan: 1800, now: Date(timeIntervalSince1970: 1000 + 1799))
        #expect(inv.devices.count == 1, "보관 기간 전인데 제거됐다")
        #expect(inv.devices[0].isOnline == false)
    }

    @Test func offlineDeviceIsPrunedAfterRetentionWindow() {
        var inv = DeviceInventory()
        var s = DeviceSnapshot()
        s.serial = "s1"
        s.isOnline = true
        inv.merge(s)
        inv.markOffline(serial: "s1", now: Date(timeIntervalSince1970: 1000))
        inv.pruneOffline(olderThan: 1800, now: Date(timeIntervalSince1970: 1000 + 1800))
        #expect(inv.devices.isEmpty)
    }

    /// 온라인 기기는 절대 제거되면 안 된다 (오프라인 시각이 없어서 걸러짐)
    @Test func onlineDevicesAreNeverPruned() {
        var inv = DeviceInventory()
        for i in 0..<3 {
            var s = DeviceSnapshot()
            s.serial = "s\(i)"
            s.isOnline = true
            inv.merge(s)
        }
        inv.pruneOffline(olderThan: 1, now: Date(timeIntervalSince1970: 999_999))
        #expect(inv.devices.count == 3)
    }

    /// 반복 오프라인 전환에서 시각이 갱신되지 않아야 prune 시점이 밀리지 않는다
    @Test func offlineSinceIsNotResetByRepeatedMarkOffline() {
        var inv = DeviceInventory()
        var s = DeviceSnapshot()
        s.serial = "s1"
        s.isOnline = true
        inv.merge(s)

        let t0 = Date(timeIntervalSince1970: 1000)
        inv.markOffline(serial: "s1", now: t0)
        // 이미 오프라인인 상태에서 다시 호출 (헛짓 경로)
        inv.markOffline(serial: "s1", now: t0.addingTimeInterval(100))
        #expect(inv.devices[0].offlineSince == t0, "오프라인 시각이 갱신됐다 — prune 시점이 밀린다")
    }

    /// 무선 ADB 의 IP 변경 시나리오 — 옛 항목이 결국 정리되어야 목록이 무한 증가하지 않는다
    @Test func staleWirelessEntriesDoNotAccumulateForever() {
        var inv = DeviceInventory()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<10 {
            var s = DeviceSnapshot()
            s.serial = "192.168.0.\(i):5555"     // DHCP 로 IP 가 계속 바뀐 상황
            s.isOnline = true
            inv.merge(s, now: base.addingTimeInterval(Double(i) * 60))
            inv.markOffline(serial: s.serial, now: base.addingTimeInterval(Double(i) * 60))
            inv.pruneOffline(olderThan: 1800, now: base.addingTimeInterval(Double(i) * 60))
        }
        // 10분간 10개 IP → 보관기간(30분) 안이므로 전부 남아야 한다 (보존 우선)
        #expect(inv.devices.count == 10)
        // 충분히 시간이 지나면 정리된다
        inv.pruneOffline(olderThan: 1800, now: base.addingTimeInterval(3600))
        #expect(inv.devices.isEmpty, "오래된 IP 항목이 정리되지 않았다")
    }

    // MARK: - logcat 키워드 1회 스캔 (기존 여러 번 스캔과 결과 동일)

    /// 한 번의 스캔이 여러 집합을 각각 정확히 센다
    @Test func keywordScanCountsEachSet() {
        let text = """
        09-26 10:00:00.000  100  200 E AndroidRuntime: FATAL EXCEPTION: main
        09-26 10:00:01.000  100  200 D Other: ANR in com.example.app
        09-26 10:00:02.000  100  200 I Tag: nothing to see
        09-26 10:00:03.000  100  200 W Watch: ANR
        """
        let r = AdbClient.logcatKeywordScan(
            text,
            sets: [
                .anr: ["ANR"],
                .crash: ["FATAL EXCEPTION"],
            ]
        )
        #expect(r.counts[.anr] == 2)      // "ANR in com.example.app" + "ANR"
        #expect(r.counts[.crash] == 1)
        #expect(r.breakdowns[.crash]?["FATAL EXCEPTION"] == 1)
    }

    /// 키워드는 **부분 문자열**로 매칭된다 — "ANR in" 키워드로 "ANR" 단독 라인은 잡히지 않는다
    @Test func keywordScanUsesSubstringMatchingNotTokenization() {
        let text = """
        09-26 10:00:01.000  1  2 D Other: ANR in com.example.app
        09-26 10:00:03.000  1  2 W Watch: ANR
        """
        let strict = AdbClient.logcatKeywordScan(text, sets: [.anr: ["ANR in"]]).counts[.anr] ?? 0
        let loose = AdbClient.logcatKeywordScan(text, sets: [.anr: ["ANR"]]).counts[.anr] ?? 0
        #expect(strict == 1, "\"ANR in\" 은 단독 \"ANR\" 를 잡지 않는다")
        #expect(loose == 2)
    }

    /// 같은 라인이 두 집합에 모두 걸려도 **집합별로** 각각 센다 (집합 간 중복 허용)
    @Test func keywordScanCountsPerSetIndependently() {
        let text = "09-26 10:00:00.000  1  2 E X: FATAL EXCEPTION ANR"
        let r = AdbClient.logcatKeywordScan(
            text,
            sets: [.anr: ["ANR"], .crash: ["FATAL EXCEPTION"]]
        )
        #expect(r.counts[.anr] == 1)
        #expect(r.counts[.crash] == 1)
    }

    /// 1회 스캔 결과가 기존 `countLogcatHits` 와 **동일**해야 한다 (리팩토링 정합성)
    @Test func keywordScanMatchesLegacyCounter() {
        let text = """
        09-26 10:00:00.000  1  2 E AndroidRuntime: FATAL EXCEPTION: main
        09-26 10:00:01.000  1  2 E ActivityManager: ANR in com.example.app
        09-26 10:00:02.000  1  2 I Tag: plain line
        09-26 10:00:03.000  1  2 W Watch: ANR detected
        09-26 10:00:04.000  1  2 E AndroidRuntime: FATAL EXCEPTION: again
        """
        let keywords = ["ANR", "FATAL EXCEPTION"]
        let legacy = AdbClient.countLogcatHits(text, keywords: keywords)
        let scanned = AdbClient.logcatKeywordScan(text, sets: [.logcat: keywords]).counts[.logcat] ?? 0
        #expect(scanned == legacy)
    }

    /// cutoff 이후 라인만 세야 한다 (cursor 이전 로그 오인 방지)
    @Test func keywordScanRespectsCutoff() {
        let text = """
        09-26 10:00:00.000  1  2 E A: ANR
        09-26 10:00:05.000  1  2 E A: ANR
        """
        let all = AdbClient.logcatKeywordScan(text, sets: [.anr: ["ANR"]]).counts[.anr] ?? 0
        let after = AdbClient.logcatKeywordScan(
            text,
            sets: [.anr: ["ANR"]],
            afterTimestamp: "09-26 10:00:01.000"
        ).counts[.anr] ?? 0
        #expect(all == 2)
        #expect(after == 1)
    }

    /// 빈 입력에서도 크래시하지 않고 0 을 준다
    @Test func keywordScanOnEmptyInputIsSafe() {
        let r = AdbClient.logcatKeywordScan("", sets: [.anr: ["ANR"]])
        #expect(r.counts[.anr] == nil)
        #expect(r.counts[.anr] ?? 0 == 0)
        let noSets = AdbClient.logcatKeywordScan("ANR", sets: [:])
        #expect(noSets.counts.isEmpty)
    }
}
