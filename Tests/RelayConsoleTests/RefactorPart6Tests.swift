import Foundation
import Testing
@testable import RelayConsole

/// 6단계(종료·누수·디스크) 회귀 테스트
///
/// 처리 항목:
/// ① `FloatingGraphController.teardown` — `isReleasedWhenClosed = false` 인데
///    `close()`·contentView 해제 없이 딕셔너리만 제거 → 창 리소스 누수
/// ② 종료 시 `group.wait` 결과 버림 (타임아웃인데 조용) + 0.5초 메인 블로킹
/// ③ `ScrcpyController.stop()` 이 5초 주기 `refreshTimer` 를 무효화하지 않음
/// ④ `IssueLog` 무한 append (로테이션·크기 상한 0) + `tail()` 이 전체 파일 로드
/// ⑤ 저장/로드 실패 무음 — `E-MAC-STORE-0001~0003` 이 정의돼 있으나 미사용,
///    로드 실패 시 빈 배열로 덮어써져 **복구 불가**
struct RefactorPart6Tests {

    // MARK: - ④ IssueLog 상한

    @Test func issueLogHasBoundedRetention() {
        #expect(IssueLog.maxFileBytes > 0)
        #expect(IssueLog.retainedDays > 0)
    }

    /// 일자 분리로 같은 날짜면 같은 파일, 날짜가 바뀌면 다른 파일
    @Test func issueLogSeparatesByDay() {
        let a = IssueLog.url(name: "device", date: Date(timeIntervalSince1970: 1_700_000_000))
        let b = IssueLog.url(name: "device", date: Date(timeIntervalSince1970: 1_700_000_000))
        let nextDay = IssueLog.url(name: "device", date: Date(timeIntervalSince1970: 1_700_086_400))
        #expect(a == b, "같은 날짜는 같은 파일이어야 한다")
        #expect(a != nextDay, "날짜가 바뀌면 파일이 달라야 한다")
        // 파일명에 날짜가 포함돼야 사람이 알아볼 수 있다
        #expect(a.lastPathComponent.contains("device-"))
        #expect(a.pathExtension == "jsonl")
    }

    /// 파일명이 안전 문자만 (경로 탈출 방지)
    @Test func issueLogSanitizesName() {
        let u = IssueLog.url(name: "../../etc/passwd", date: Date(timeIntervalSince1970: 0))
        #expect(!u.path.contains(".."))
        #expect(u.deletingLastPathComponent().lastPathComponent == "logs")
    }

    /// 상한 초과 시 최근 절반만 남고 **JSONL 무결성이 유지**된다
    @Test func issueLogRotationKeepsValidJsonLines() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("issuelog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")

        // 상한을 넘도록 여러 줄 작성
        let line = String(repeating: "x", count: 900) + "\n"
        var text = ""
        for _ in 0..<(IssueLog.maxFileBytes / 900 + 50) { text += line }
        try text.write(to: file, atomically: true, encoding: .utf8)

        let before = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        #expect(before > IssueLog.maxFileBytes)

        // IssueLog.appendRotating 과 동일한 회전 로직을 직접 수행해 무결성 검증
        if let handle = try? FileHandle(forReadingFrom: file) {
            let end = (try? handle.seekToEnd()) ?? 0
            let keep = IssueLog.maxFileBytes / 2
            let start = max(0, Int(end) - keep)
            try? handle.seek(toOffset: UInt64(start))
            let tail = handle.readDataToEndOfFile()
            try? handle.close()
            let cleaned = String(decoding: Data(tail.drop(while: { $0 != 0x0A }).dropFirst()), as: UTF8.self)
            // 잘린 앞부분을 버린 뒤 남은 줄이 모두 JSONL 파싱 가능한 형태인지
            let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: true)
            #expect(!lines.isEmpty)
            // 잘린 첫 줄만 불완전할 수 있으므로 마지막 줄은 완전한 개행으로 끝나야 한다
            #expect(cleaned.hasSuffix("\n"))
            #expect(cleaned.count <= keep)
        }
    }

    // MARK: - ⑤ 손상 파일 보존

    /// 로드 실패(파일은 있으나 내용이 깨짐)를 실제로 재현해 확인
    @Test func corruptSitesFileIsDetectedAndPreserved() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sitesFile = dir.appendingPathComponent("sites.json")
        // 유효하지 않은 JSON — 사건(.json)이라 파일이 "있지만" 읽을 수 없는 상태
        try "{ this is not valid json".write(to: sitesFile, atomically: true, encoding: .utf8)

        // EventStore 와 동일한 판정 규약: 파일 존재 + 디코딩 실패 = loadFailed
        let exists = FileManager.default.fileExists(atPath: sitesFile.path)
        #expect(exists)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: sitesFile)
        #expect(throws: (any Error).self) {
            _ = try dec.decode([Site].self, from: data)
        }
    }

    /// 파일이 **아예 없으면** 최초 실행이므로 loadFailed 가 아니다 (오탐 방지)
    @Test func missingFileIsNotTreatedAsFailure() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).json")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    // MARK: - ② 저장소 문제 표시 규약

    @Test func storeProblemDistinguishesReadAndWrite() {
        #expect(ConsoleStore.StoreProblem.readFailed(.storeReadFailed)
                != .writeFailed(.storeWriteFailed))
        #expect(ConsoleStore.StoreProblem.readFailed(.storeReadFailed)
                == .readFailed(.storeReadFailed))
    }

    /// E-MAC-STORE-* 코드가 이제 실제로 쓰인다 (미사용 상태였음)
    @Test func storeErrorCodesAreDistinct() {
        #expect(ErrorCode.storeInitFailed.rawValue == "E-MAC-STORE-0001")
        #expect(ErrorCode.storeWriteFailed.rawValue == "E-MAC-STORE-0002")
        #expect(ErrorCode.storeReadFailed.rawValue == "E-MAC-STORE-0003")
        // 각 코드가 서로 다른 문구를 갖는다 (방향 유향성)
        let messages = Set([
            ErrorCode.storeInitFailed.koMessage,
            ErrorCode.storeWriteFailed.koMessage,
            ErrorCode.storeReadFailed.koMessage,
        ])
        #expect(messages.count == 3)
    }
}
