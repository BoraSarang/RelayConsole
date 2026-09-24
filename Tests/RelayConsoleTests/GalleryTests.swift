import Foundation
@testable import RelayConsole
import Testing

struct GalleryTests {
    @Test func imageExtensions() {
        #expect(GalleryLogic.isImage("a.PNG"))
        #expect(GalleryLogic.isImage("shot.jpg"))
        #expect(GalleryLogic.isImage("x.webp"))
        #expect(!GalleryLogic.isImage("movie.mp4"))
        #expect(!GalleryLogic.isImage("note.txt"))
        #expect(!GalleryLogic.isImage("noext"))
    }

    @Test func filterImagesAndQuery() {
        let names = ["a.png", "b.mp4", "c.JPG", "d.txt", "Debug_Screen.png"]
        let all = GalleryLogic.filter(names, query: "")
        #expect(all == ["a.png", "c.JPG", "Debug_Screen.png"])
        let hit = GalleryLogic.filter(names, query: "debug")
        #expect(hit == ["Debug_Screen.png"])
        let miss = GalleryLogic.filter(names, query: "zzz")
        #expect(miss.isEmpty)
    }

    @Test func parseLsDedupesAndSkipsDots() {
        let text = """
        .
        ..
        Shot_1.png

        Shot_1.png
        Shot_2.jpg

        """
        let out = GalleryLogic.parseLs(text)
        #expect(out == ["Shot_1.png", "Shot_2.jpg"])
    }

    @Test func localFileNameSafeAndOrdered() {
        let cal = Calendar(identifier: .gregorian)
        let at = cal.date(from: DateComponents(
            year: 2026, month: 9, day: 24, hour: 12, minute: 5, second: 3
        ))!
        let name = GalleryLogic.localFileName(source: "capture", serial: "AB:C/1", at: at)
        #expect(name.hasPrefix("20260924-120503-capture-"))
        #expect(name.hasSuffix(".png"))
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    @Test func listAndPullArgs() {
        #expect(GalleryLogic.listArgs(remoteDir: "/sdcard/DCIM/Screenshots") == [
            "shell", "ls", "-1", "/sdcard/DCIM/Screenshots"
        ])
        #expect(GalleryLogic.pullArgs(remoteDir: "/sdcard/Pictures/Screenshots", file: "a.png") == [
            "pull", "/sdcard/Pictures/Screenshots/a.png"
        ])
    }

    @Test func serialFromFileName() {
        #expect(GalleryStore.serialFromFileName("20260924-120000-capture-AB12.png") == "AB12")
        #expect(GalleryStore.serialFromFileName("20260924-120000-pull-10.0.0.1:5555.png") == "10.0.0.1:5555")
        #expect(GalleryStore.serialFromFileName("random.png") == nil)
        #expect(GalleryStore.sourceFromFileName("20260924-120000-pull-AB12.png") == "pull")
        #expect(GalleryStore.sourceFromFileName("20260924-120000-capture-AB12.png") == "capture")
    }

    @Test func remoteDirsAreStandardOnly() {
        #expect(GalleryLogic.remoteDirs.contains("/sdcard/DCIM/Screenshots"))
        #expect(GalleryLogic.remoteDirs.contains("/sdcard/Pictures/Screenshots"))
        #expect(GalleryLogic.remoteDirs.allSatisfy { $0.hasPrefix("/sdcard/") })
    }
}
