import Foundation
import Testing
@testable import RelayConsole

/// dropbox 파싱·회수 선별 — 실기기 출력 형식 고정
///
/// 픽스처는 **실측 출력**(2026-10-18 · SM-A908N Android 12 `dumpsys dropbox --print '2026-10-18 04:50:23'`,
/// SM-S901N Android 16 `dumpsys dropbox`)에서 그대로 가져왔다. 형식을 지어내면
/// 파서가 통과해도 실기기에서 0건이 된다.
struct DropboxLogTests {
    // MARK: - 픽스처 (실측)

    /// SM-A908N Android 12 — 실제 `dumpsys dropbox --print '<시각>'`
    static let printFixture = """
    Drop box contents: 75 entries
    Max entries: 1000
    Low priority rate limit period: 2000 ms
    Low priority tags: {data_app_wtf, keymaster, system_server_wtf, netstats}
    Searching for: 2026-10-18 04:50:23

    ========================================
    2026-10-18 04:50:23 data_app_crash (text, 1871 bytes)
    Process: com.borasarang.zenfreeproxy
    PID: 6633
    UID: 10327
    Flags: 0x20c83e46
    Package: com.borasarang.zenfreeproxy v1 (0.1.0)
    Foreground: Yes
    Process-Runtime: 16555017
    Build: samsung/r3qks/r3q:12/SP1A.210812.016/A908NKSU5EXE1:user/release-keys
    Loading-Progress: 1.0

    java.util.IllegalFormatConversionException: d != java.lang.String
    \tat java.util.Formatter$FormatSpecifier.failConversion(Formatter.java:4403)
    """

    /// 목록 — 헤더 + 미리보기 줄 포함 (실측 형식)
    static let listFixture = """
    Drop box contents: 33 entries
    Max entries: 1000
    Low priority rate limit period: 2000 ms
    Low priority tags: {data_app_wtf, keymaster}

    2026-10-17 23:58:41 storage_trim (text, 25 bytes)
        unknown 19320832 10824428
    2026-10-18 04:50:23 data_app_crash (text, 1871 bytes)
        Process: com.borasarang.zenfreeproxy
    2026-10-18 04:51:31 system_app_anr (compressed text, 21400 bytes)
        Subject: Input dispatching timed out
    2026-10-18 05:02:00 SYSTEM_BOOT (text, 572 bytes)
    """

    /// ANR 본문 — `Subject:` 가 사유다 (크래시와 달리 예외 머리가 없다)
    static let anrBlockFixture = """
    ========================================
    2026-10-18 04:51:31 system_app_anr (compressed text, 21400 bytes)
    Process: com.borasarang.zenfreeproxy
    Package: com.borasarang.zenfreeproxy v1 (0.1.0)
    Foreground: Yes
    Subject: Input dispatching timed out (Waiting to send key event)
    """

    // MARK: - 시각

    @Test func stampRoundTripsThroughFormatter() throws {
        let date = try #require(DropboxLogLogic.date(fromStamp: "2026-10-18 04:50:23"))
        #expect(DropboxLogLogic.stamp(from: date) == "2026-10-18 04:50:23")
    }

    @Test func stampValidationRejectsNonStamps() {
        #expect(DropboxLogLogic.isValidStamp("2026-10-18 04:50:23"))
        #expect(!DropboxLogLogic.isValidStamp("2026-10-18 04:50"))       // 짧다
        #expect(!DropboxLogLogic.isValidStamp("2026/10/18 04:50:23"))    // 구분자
        #expect(!DropboxLogLogic.isValidStamp("Drop box contents: 33"))  // 헤더
        #expect(!DropboxLogLogic.isValidStamp("10-18 04:50:23.123"))     // logcat 형식(연도 없음)
    }

    // MARK: - 목록 파싱

    @Test func parseListKeepsEntriesAndDropsHeadersAndPreviews() {
        let entries = DropboxLogLogic.parseList(Self.listFixture)
        // 헤더 4줄·들여쓴 미리보기 3줄은 항목이 아니다 — 시각으로 시작하는 4줄만 남는다
        #expect(entries.count == 4)
        #expect(entries.map(\.tag) == ["storage_trim", "data_app_crash", "system_app_anr", "SYSTEM_BOOT"])
        #expect(entries[1].stamp == "2026-10-18 04:50:23")
        #expect(entries[1].bytes == 1871)
        // `(compressed text, 21400 bytes)` 도 숫자를 읽는다
        #expect(entries[2].bytes == 21400)
    }

    @Test func parseListOnGarbageIsEmpty() {
        #expect(DropboxLogLogic.parseList("").isEmpty)
        #expect(DropboxLogLogic.parseList("Drop box contents: 0 entries\n").isEmpty)
    }

    // MARK: - 본문 파싱

    @Test func parseBlocksReadsHeaderAndBody() throws {
        let blocks = DropboxLogLogic.parseBlocks(Self.printFixture)
        let block = try #require(blocks.first)
        #expect(blocks.count == 1)
        #expect(block.tag == "data_app_crash")
        #expect(block.stamp == "2026-10-18 04:50:23")
        #expect(block.body.contains("Package: com.borasarang.zenfreeproxy"))
        // 구분선 이전 헤더/`Searching for:` 는 본문에 들어오지 않는다
        #expect(!block.body.contains("Searching for"))
        #expect(!block.body.contains("Drop box contents"))
    }

    @Test func parseBlocksSplitsOnSeparators() {
        let text = Self.printFixture + "\n" + Self.anrBlockFixture
        let blocks = DropboxLogLogic.parseBlocks(text)
        #expect(blocks.count == 2)
        #expect(blocks.map(\.tag) == ["data_app_crash", "system_app_anr"])
    }

    @Test func parseBlocksWithoutSeparatorStillReadsOneBlock() {
        // 구분선 없는 출력(단일 항목을 붙여넣은 경우)도 헤더 줄에서 블록을 연다
        let text = """
        2026-10-18 04:50:23 data_app_crash (text, 12 bytes)
        Package: com.x
        """
        let blocks = DropboxLogLogic.parseBlocks(text)
        #expect(blocks.count == 1)
        #expect(blocks[0].body.contains("Package: com.x"))
    }

    // MARK: - 태그 해석

    @Test func kindForTagCoversSystemAndLegacyForms() {
        #expect(DropboxLogLogic.kind(forTag: "data_app_anr") == .anr)
        #expect(DropboxLogLogic.kind(forTag: "system_app_anr") == .anr)
        #expect(DropboxLogLogic.kind(forTag: "data_app_crash") == .crash)
        #expect(DropboxLogLogic.kind(forTag: "system_app_crash") == .crash)
        // 레거시 `<pkg>.crash` / `<pkg>.anr`
        #expect(DropboxLogLogic.kind(forTag: "com.borasarang.droidrelay.crash") == .crash)
        #expect(DropboxLogLogic.kind(forTag: "com.borasarang.droidrelay@123.anr") == .anr)
        // 잡음·범위 밖
        #expect(DropboxLogLogic.kind(forTag: "storage_trim") == nil)
        #expect(DropboxLogLogic.kind(forTag: "SYSTEM_BOOT") == nil)
        #expect(DropboxLogLogic.kind(forTag: "data_app_wtf") == nil)
        #expect(DropboxLogLogic.kind(forTag: "SYSTEM_TOMBSTONE") == nil) // 네이티브 — 다음 후보
    }

    @Test func packageNameFromLegacyTagStripsAtSuffix() {
        #expect(DropboxLogLogic.packageName(forTag: "com.borasarang.droidrelay.crash") == "com.borasarang.droidrelay")
        #expect(DropboxLogLogic.packageName(forTag: "com.borasarang.droidrelay@123.anr") == "com.borasarang.droidrelay")
        // 종류 이름 태그는 패키지가 아니다
        #expect(DropboxLogLogic.packageName(forTag: "data_app_anr") == nil)
        #expect(DropboxLogLogic.packageName(forTag: "system_app_crash") == nil)
    }

    @Test func packageNameFromBodyPrefersPackageLine() throws {
        let crashBlock = try #require(DropboxLogLogic.parseBlocks(Self.printFixture).first)
        #expect(DropboxLogLogic.packageName(inBlock: crashBlock.body) == "com.borasarang.zenfreeproxy")
        // `Package:` 가 없으면 `Process:` 로 내려간다
        let processOnly = """
        Process: com.foo.bar
        PID: 1
        """
        #expect(DropboxLogLogic.packageName(inBlock: processOnly) == "com.foo.bar")
        #expect(DropboxLogLogic.packageName(inBlock: "PID: 1\nBuild: x") == nil)
    }

    @Test func reasonUsesSubjectThenExceptionHead() throws {
        // ANR — `Subject:` (실제 호출부처럼 헤더를 떼낸 블록 본문을 쓴다)
        let anrBlock = try #require(DropboxLogLogic.parseBlocks(Self.anrBlockFixture).first)
        #expect(
            DropboxLogLogic.reason(inBlock: anrBlock.body)
                == "Input dispatching timed out (Waiting to send key event)"
        )
        // 크래시 — 메타 블록(`Key: value`) 뒤 첫 줄 = 예외 머리
        let crashBlock = try #require(DropboxLogLogic.parseBlocks(Self.printFixture).first)
        #expect(
            DropboxLogLogic.reason(inBlock: crashBlock.body)
                == "java.util.IllegalFormatConversionException: d != java.lang.String"
        )
        // 메타만 있으면 사유 없음 (지어내지 않는다)
        #expect(DropboxLogLogic.reason(inBlock: "Process: com.x\nPID: 1") == nil)
    }

    @Test func metaLineRecognizesKeys() {
        #expect(DropboxLogLogic.isMetaLine("Process: com.x"))
        #expect(DropboxLogLogic.isMetaLine("Loading-Progress: 1.0"))
        #expect(!DropboxLogLogic.isMetaLine("java.lang.IllegalStateException: boom"))
        #expect(!DropboxLogLogic.isMetaLine("at com.x.Y(Z.java:1)"))
    }

    @Test func reasonIsTruncated() {
        let long = "Subject: " + String(repeating: "a", count: 500)
        let reason = DropboxLogLogic.reason(inBlock: long)
        #expect(reason?.count == 201) // 200 + 말줄임표
        #expect(reason?.hasSuffix("…") == true)
    }

    // MARK: - 회수 선별

    @Test func firstScanOnlySetsWatermark() {
        let entries = DropboxLogLogic.parseList(Self.listFixture)
        let plan = DropboxLogLogic.recoveryPlan(entries: entries, since: nil)
        // 첫 스캔은 **아무것도 발행하지 않는다** — 과거 전건이 쏟아지면 안 된다
        #expect(plan.stamps.isEmpty)
        #expect(plan.watermark == "2026-10-18 04:51:31")
    }

    @Test func onlyNewerMatchingEntriesAreReturned() {
        let entries = DropboxLogLogic.parseList(Self.listFixture)
        let plan = DropboxLogLogic.recoveryPlan(entries: entries, since: "2026-10-18 04:50:23")
        #expect(plan.stamps == ["2026-10-18 04:51:31"])
        #expect(plan.watermark == "2026-10-18 04:51:31")
    }

    @Test func watermarkDoesNotAdvanceOnNoiseOnly() {
        let entries = DropboxLogLogic.parseList(Self.listFixture)
        let plan = DropboxLogLogic.recoveryPlan(entries: entries, since: "2026-10-18 04:51:31")
        #expect(plan.stamps.isEmpty)
        // 잡음(`SYSTEM_BOOT`)이 더 최신이어도 기준선은 **해당 태그** 기준으로만 움직인다
        #expect(plan.watermark == "2026-10-18 04:51:31")
    }

    @Test func recoveryIsNewestFirstAndCapped() {
        var lines = ["Drop box contents: 9 entries", ""]
        for i in 1...5 {
            lines.append("2026-10-18 05:0\(i):00 data_app_anr (text, 10 bytes)")
        }
        let plan = DropboxLogLogic.recoveryPlan(
            entries: DropboxLogLogic.parseList(lines.joined(separator: "\n")),
            since: "2026-10-18 05:00:00"
        )
        #expect(plan.stamps == ["2026-10-18 05:05:00", "2026-10-18 05:04:00", "2026-10-18 05:03:00"])
        #expect(plan.watermark == "2026-10-18 05:05:00")
    }

    @Test func sameSecondEntriesCollapseToOneFetch() {
        let text = """
        2026-10-18 05:00:00 data_app_anr (text, 10 bytes)
        2026-10-18 05:00:00 data_app_crash (text, 10 bytes)
        """
        let plan = DropboxLogLogic.recoveryPlan(
            entries: DropboxLogLogic.parseList(text),
            since: "2026-10-18 04:00:00"
        )
        // `--print '<시각>'` 은 그 초의 항목을 **모두** 뱉으므로 1회 조회로 함께 처리한다
        #expect(plan.stamps == ["2026-10-18 05:00:00"])
    }

    @Test func emptyDropboxKeepsPreviousWatermark() {
        let plan = DropboxLogLogic.recoveryPlan(entries: [], since: "2026-10-18 04:00:00")
        #expect(plan.stamps.isEmpty)
        #expect(plan.watermark == "2026-10-18 04:00:00")
    }

    // MARK: - 번들 첨부 선별

    @Test func selectEntriesUsesEventWindow() throws {
        let eventAt = try #require(DropboxLogLogic.date(fromStamp: "2026-10-18 04:52:00"))
        let entries = DropboxLogLogic.parseList(Self.listFixture)
        let picked = DropboxLogLogic.selectEntries(entries, kind: .crash, eventAt: eventAt)
        #expect(picked.map(\.stamp) == ["2026-10-18 04:50:23"])
        // 종류가 다르면 걸리지 않는다
        let anr = DropboxLogLogic.selectEntries(entries, kind: .anr, eventAt: eventAt)
        #expect(anr.map(\.stamp) == ["2026-10-18 04:51:31"])
    }

    @Test func selectEntriesExcludesOutOfWindow() throws {
        let eventAt = try #require(DropboxLogLogic.date(fromStamp: "2026-10-18 06:00:00"))
        let entries = DropboxLogLogic.parseList(Self.listFixture)
        #expect(DropboxLogLogic.selectEntries(entries, kind: .crash, eventAt: eventAt).isEmpty)
    }

    @Test func captureTextKeepsOnlyMatchingKind() throws {
        let blocks = DropboxLogLogic.parseBlocks(Self.printFixture + "\n" + Self.anrBlockFixture)
        let text = try #require(DropboxLogLogic.captureText(blocks: blocks, kind: .crash))
        #expect(text.contains("data_app_crash"))
        #expect(!text.contains("system_app_anr"))
        #expect(text.contains("java.util.IllegalFormatConversionException"))
        // 맞는 종류가 없으면 nil = 첨부 생략
        #expect(DropboxLogLogic.captureText(blocks: DropboxLogLogic.parseBlocks(Self.printFixture), kind: .anr) == nil)
    }

    // MARK: - 조회 커맨드

    @Test func printCommandQuotesStampWithSpace() {
        let command = DropboxLogLogic.dropboxPrintCommand(stamp: "2026-10-18 04:50:23")
        // 인용하지 않으면 기기 셸이 두 인자로 쪼갠다 (폰 찾기에서 겪은 함정과 동일)
        #expect(command.contains("--print '2026-10-18 04:50:23'"))
        #expect(command.contains("head -c 200000"))
    }

    @Test func listCommandIsPlainDumpsys() {
        #expect(DropboxLogLogic.dropboxListCommand == "dumpsys dropbox")
    }
}
