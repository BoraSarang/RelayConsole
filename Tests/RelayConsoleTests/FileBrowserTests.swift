import Foundation
@testable import RelayConsole
import Testing

struct FileBrowserTests {

    private let sampleLs = """
    total 12345
    drwxrwx--x  2 root    sdcard_rw       4096 2026-08-25 11:28:20.728804402+0900 DCIM
    -rw-rw----  1 root    sdcard_rw     69602 2026-07-06 20:18:33.100000000+0900 My File.jpg
    lrwxrwxrwx  1 root    root              21 2026-01-01 00:00:00.000000000+0900 storage -> /storage/self/primary
    drwx------  2 u0_a123 u0_a123        4096 2026-01-02 03:04:05.000000000+0900 .
    drwx------  3 root    root            4096 2026-01-02 03:04:05.000000000+0900 ..
    ls: /sdcard/nope: No such file or directory
    """

    // MARK: ls 파싱

    @Test func parseLsSkipsTotalDotsAndErrors() {
        let items = FileBrowserLogic.parseLs(sampleLs, dir: "/sdcard")
        #expect(items.count == 3)
        let names = items.map(\.name)
        #expect(names == ["DCIM", "My File.jpg", "storage"])
        #expect(!names.contains("."))
        #expect(!names.contains(".."))
    }

    @Test func parseLsDirFileAndSymlinkFlags() {
        let items = FileBrowserLogic.parseLs(sampleLs, dir: "/sdcard")
        let dcim = items[0]
        #expect(dcim.isDir)
        #expect(dcim.path == "/sdcard/DCIM")
        #expect(dcim.modified != nil)
        let jpg = items[1]
        #expect(!jpg.isDir)
        #expect(jpg.size == 69602)
        #expect(jpg.path == "/sdcard/My File.jpg")  // 이름 내 공백 보존
        let storage = items[2]
        #expect(!storage.isDir)  // 심링크 -> 파일로 취급 (-> 타깃 제거)
        #expect(storage.name == "storage")
    }

    @Test func parseLsDedupesDuplicateNames() {
        let text = """
        -rw-r--r-- 1 root root 1 2026-01-01 00:00:00.000000000+0900 a.txt
        -rw-r--r-- 1 root root 1 2026-01-01 00:00:00.000000000+0900 a.txt
        """
        let items = FileBrowserLogic.parseLs(text, dir: "/sdcard")
        #expect(items.count == 1)
    }

    @Test func parseLsShortFormatWithoutTz() {
        // --full-time 미지원 구형: tz 필드 없음 (7번째 토큰이 곧 이름)
        let text = "-rw-r--r-- 1 root root 4096 2026-08-25 11:28 DCIM"
        let items = FileBrowserLogic.parseLs(text, dir: "/sdcard")
        #expect(items.count == 1)
        #expect(items[0].name == "DCIM")
        #expect(items[0].modified != nil)
    }

    @Test func parseLsEmptyAndGarbage() {
        #expect(FileBrowserLogic.parseLs("", dir: "/sdcard").isEmpty)
        #expect(FileBrowserLogic.parseLs("just some text\nnope", dir: "/sdcard").isEmpty)
    }

    // MARK: 시각 파싱

    @Test func parseDateTimeNanosecondAndTz() {
        let date = FileBrowserLogic.parseDateTime(
            date: "2026-08-25", time: "11:28:20.728804402", tz: "+0900"
        )
        #expect(date != nil)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 8
        comps.day = 25
        comps.hour = 11
        comps.minute = 28
        comps.second = 20
        comps.nanosecond = 728_804_402
        comps.timeZone = TimeZone(secondsFromGMT: 9 * 3600)
        let expected = Calendar(identifier: .gregorian).date(from: comps)
        #expect(date == expected)
    }

    @Test func parseDateTimeInvalidReturnsNil() {
        #expect(FileBrowserLogic.parseDateTime(date: "x", time: "11:28", tz: nil) == nil)
        #expect(FileBrowserLogic.parseDateTime(date: "2026-08-25", time: "x", tz: nil) == nil)
        #expect(FileBrowserLogic.parseDateTime(date: "2026/08/25", time: "11:28", tz: nil) == nil)
    }

    // MARK: 포맷

    @Test func formatSizeUnits() {
        #expect(FileBrowserLogic.formatSize(0) == "0 B")
        #expect(FileBrowserLogic.formatSize(1023) == "1023 B")
        #expect(FileBrowserLogic.formatSize(1024) == "1.0 KB")
        #expect(FileBrowserLogic.formatSize(69_602) == "68.0 KB")
        #expect(FileBrowserLogic.formatSize(1_572_864) == "1.5 MB")
        #expect(FileBrowserLogic.formatSize(-1) == "—")
    }

    // MARK: 정렬 · 필터

    @Test func sortDirsFirstByNameAscending() {
        let items = [
            mk("zebra.txt", dir: false),
            mk("apple", dir: true),
            mk("banana", dir: true),
            mk("aardvark.txt", dir: false)
        ]
        let sorted = FileBrowserLogic.sort(items, by: .name, ascending: true)
        #expect(sorted.map(\.name) == ["apple", "banana", "aardvark.txt", "zebra.txt"])
    }

    @Test func sortDirsFirstEvenWhenDescending() {
        let items = [
            mk("zebra.txt", dir: false),
            mk("apple", dir: true),
            mk("banana", dir: true)
        ]
        let sorted = FileBrowserLogic.sort(items, by: .name, ascending: false)
        #expect(sorted.map(\.name) == ["banana", "apple", "zebra.txt"])
    }

    @Test func sortByKeySizeAndModified() {
        let big = mk("big", dir: false, size: 1000)
        let small = mk("small", dir: false, size: 10)
        let dirA = mk("dir", dir: true, size: 5)
        let sorted = FileBrowserLogic.sort([big, small, dirA], by: .size, ascending: true)
        #expect(sorted.map(\.name) == ["dir", "small", "big"])
    }

    @Test func filterCaseInsensitive() {
        let items = [mk("Debug_Screen.png", dir: false), mk("shot.jpg", dir: false)]
        #expect(FileBrowserLogic.filter(items, query: "").count == 2)
        #expect(FileBrowserLogic.filter(items, query: "debug").count == 1)
        #expect(FileBrowserLogic.filter(items, query: "zzz").isEmpty)
    }

    // MARK: 경로

    @Test func parentPathRules() {
        #expect(FileBrowserLogic.parentPath("/sdcard/Download") == "/sdcard")
        #expect(FileBrowserLogic.parentPath("/sdcard") == "/")
        #expect(FileBrowserLogic.parentPath("/sdcard/Download/") == "/sdcard")
        #expect(FileBrowserLogic.parentPath("/") == nil)
    }

    @Test func joinPath() {
        #expect(FileBrowserLogic.join(dir: "/sdcard", name: "a.png") == "/sdcard/a.png")
        #expect(FileBrowserLogic.join(dir: "/sdcard/", name: "a.png") == "/sdcard/a.png")
        #expect(FileBrowserLogic.join(dir: "/", name: "a") == "/a")
    }

    // MARK: adb 인자 (심링크 함정)

    @Test func listArgsTrailingSlashForSymlinkDir() {
        // /sdcard는 심링크 — trailing slash 없으면 ls가 링크 자체를 반환 (RESEARCH §2)
        // + 공백/한글 경로: adb는 argv 인용 없음 → 셸 인용한 단일 명령 1 argv (실측 E1/E2)
        #expect(FileBrowserLogic.listArgs(dir: "/sdcard") == [
            "shell", "ls -la --full-time '/sdcard/'"
        ])
        #expect(FileBrowserLogic.listArgs(dir: "/sdcard/") == [
            "shell", "ls -la --full-time '/sdcard/'"
        ])
        #expect(FileBrowserLogic.listArgs(dir: "/") == [
            "shell", "ls -la --full-time '/'"
        ])
    }

    @Test func listArgsQuotesSpacesAndUnicode() {
        #expect(FileBrowserLogic.listArgs(dir: "/sdcard/Download/DroidRelay/Windows 11") == [
            "shell", "ls -la --full-time '/sdcard/Download/DroidRelay/Windows 11/'"
        ])
        #expect(FileBrowserLogic.listArgs(dir: "/sdcard/테스트 폴더/サブ フォルダ") == [
            "shell", "ls -la --full-time '/sdcard/테스트 폴더/サブ フォルダ/'"
        ])
        #expect(FileBrowserLogic.listArgs(dir: "/sdcard/O'Brien's Files") == [
            "shell", "ls -la --full-time '/sdcard/O'\\''Brien'\\''s Files/'"
        ])
        #expect(FileBrowserLogic.shellQuote("a'b") == "'a'\\''b'")
    }

    @Test func pushArgsTrailingSlash() {
        #expect(FileBrowserLogic.pushArgs(local: "/tmp/a.png", remoteDir: "/sdcard/Download") == [
            "push", "/tmp/a.png", "/sdcard/Download/"
        ])
        #expect(FileBrowserLogic.pullArgs(remote: "/sdcard/a.png", local: "/tmp/out.png") == [
            "pull", "/sdcard/a.png", "/tmp/out.png"
        ])
    }

    // MARK: 중복 회피 · 미리보기 가드

    @Test func uniqueDestCollisions() {
        let taken: Set<String> = ["/tmp/d/a.png", "/tmp/d/a (1).png"]
        let dest = FileBrowserLogic.uniqueDest(dir: "/tmp/d", name: "a.png") { taken.contains($0) }
        #expect(dest == "/tmp/d/a (2).png")
        let fresh = FileBrowserLogic.uniqueDest(dir: "/tmp/d", name: "b.png") { taken.contains($0) }
        #expect(fresh == "/tmp/d/b.png")
        let noExt = FileBrowserLogic.uniqueDest(dir: "/tmp/d", name: "README") {
            $0 == "/tmp/d/README"
        }
        #expect(noExt == "/tmp/d/README (1)")
    }

    @Test func previewAllows50MBGuard() {
        #expect(FileBrowserLogic.previewAllows(size: 0))
        #expect(FileBrowserLogic.previewAllows(size: FileBrowserLogic.previewMaxBytes))
        #expect(!FileBrowserLogic.previewAllows(size: FileBrowserLogic.previewMaxBytes + 1))
        #expect(!FileBrowserLogic.previewAllows(size: -1))
    }

    // MARK: 헬퍼

    private func mk(_ name: String, dir: Bool, size: Int64 = 0) -> FileBrowserLogic.Item {
        FileBrowserLogic.Item(
            name: name,
            path: "/sdcard/" + name,
            isDir: dir,
            size: size,
            modified: nil,
            perms: dir ? "drwxr-xr-x" : "-rw-r--r--"
        )
    }
}
