import Foundation
import Testing
@testable import RelayConsole

/// 2단계(ADB 배치화) 회귀 테스트
///
/// 배칭의 위험은 두 가지다:
/// ① 출력이 섞이거나 잘려 **종전과 다른 값**이 파서에 들어간다 (데이터 손상)
/// ② 마커 프로토콜이 깨져 조용히 아무것도 못 읽는다 (조용한 실패)
/// 둘 다 여기서 고정한다. 기기 없이 순수 함수만 검증한다.
struct PollBatchTests {

    // MARK: - 마커 규약

    /// 마커는 `@@RLY<n>@@` 형식이어야 한다 (실기기에서 검증된 형식)
    @Test func markerFormatIsStable() {
        #expect(PollBatch.marker(0) == "@@RLY0@@")
        #expect(PollBatch.marker(19) == "@@RLY19@@")
    }

    /// 마커로 오인하면 안 되는 줄은 마커가 아니다
    @Test func markerParserRejectsNonMarkers() {
        #expect(PollBatch.parseMarker("@@RLY3@@") == 3)
        // 숫자가 없거나 섞여 있으면 마커 아님
        #expect(PollBatch.parseMarker("@@RLY@@") == nil)
        #expect(PollBatch.parseMarker("@@RLYx@@") == nil)
        // 앞뒤 접두·접미 불일치
        #expect(PollBatch.parseMarker("RLY3@@") == nil)
        #expect(PollBatch.parseMarker("@@RLY3") == nil)
        // 내용에 마커 문자열이 우연히 들어간 데이터 줄
        #expect(PollBatch.parseMarker("cpu  1 2 3") == nil)
        #expect(PollBatch.parseMarker("MemTotal: 123 kB") == nil)
    }

    // MARK: - build

    /// 모든 명령이 순서대로 마커와 함께 한 문자열에 들어간다
    @Test func buildEmitsMarkerForEveryCommandInOrder() {
        let s = PollBatch.build([.battery, .thermal, .loadavg])
        #expect(s.contains("echo \"@@RLY0@@\""))
        #expect(s.contains("echo \"@@RLY1@@\""))
        #expect(s.contains("echo \"@@RLY2@@\""))
        #expect(s.contains(PollBatch.Cmd.battery.shell))
        #expect(s.contains(PollBatch.Cmd.thermal.shell))
        #expect(s.contains(PollBatch.Cmd.loadavg.shell))
        // 마커 인덱스가 명령 순서와 일치
        let i0 = s.range(of: "@@RLY0@@")!.lowerBound
        let i1 = s.range(of: "@@RLY1@@")!.lowerBound
        let i2 = s.range(of: "@@RLY2@@")!.lowerBound
        #expect(i0 < i1)
        #expect(i1 < i2)
    }

    /// 빈 목록이면 빈 문자열 (adb 호출 자체를 하지 않는다)
    @Test func buildOfEmptyListIsEmpty() {
        #expect(PollBatch.build([]).isEmpty)
    }

    /// 마커를 구분자로 쓰므로 명령 사이에 `;` 가 있어야 한 명령이 나머지를 먹지 않는다
    @Test func buildSeparatesCommandsWithSemicolon() {
        let s = PollBatch.build([.battery, .thermal])
        #expect(s.contains("; "))
    }

    // MARK: - parse

    /// 마커로 잘라낸 결과가 종전 개별 호출과 **동일한 문자열**이어야 한다
    @Test func parseSplitsBatchOutputIntoPerCommandText() {
        let cmds: [PollBatch.Cmd] = [.battery, .loadavg, .procStat]
        let output = """
        @@RLY0@@
        Current Battery Service state:
          level: 80
        @@RLY1@@
        3.04 2.84 2.88 3/4736 8231
        @@RLY2@@
        cpu  1 2 3
        cpu0 4 5 6
        """
        let r = PollBatch.parse(output, into: cmds)
        #expect(r[.battery]?.contains("level: 80") == true)
        #expect(r[.loadavg] == "3.04 2.84 2.88 3/4736 8231")
        #expect(r[.procStat]?.contains("cpu0 4 5 6") == true)
    }

    /// 빈 출력을 가진 명령은 nil (= 종전 `try?` 실패와 동일 취급)
    @Test func parseTreatsEmptyChunkAsMissing() {
        let cmds: [PollBatch.Cmd] = [.battery, .gpuBusy, .gpuGpubusy]
        // GPU 경로가 없는 기기에서는 마커만 있고 내용이 비게 된다 (실기기에서 관측)
        let output = """
        @@RLY0@@
        level: 80
        @@RLY1@@

        @@RLY2@@

        """
        let r = PollBatch.parse(output, into: cmds)
        #expect(r[.battery] != nil)
        #expect(r[.gpuBusy] == nil)
        #expect(r[.gpuGpubusy] == nil)
    }

    /// 마커가 하나도 없으면 **전부 nil** — 배치가 깨졌을 때 조용한 오염을 만들지 않는다
    @Test func parseWithoutAnyMarkerYieldsNothing() {
        let cmds: [PollBatch.Cmd] = [.battery, .loadavg]
        let r = PollBatch.parse("dumpsys battery\nno marker at all", into: cmds)
        #expect(r.isEmpty)
    }

    /// 인덱스가 범위를 벗어난 마커는 무시된다 (명령 수 불일치 안전망)
    @Test func parseIgnoresOutOfRangeMarker() {
        let cmds: [PollBatch.Cmd] = [.battery]
        let output = """
        @@RLY0@@
        level: 80
        @@RLY9@@
        없는 명령
        """
        let r = PollBatch.parse(output, into: cmds)
        #expect(r[.battery] != nil)
        #expect(r.count == 1)
    }

    /// 데이터 줄이 마커처럼 보이면 마커로 오인하지 않아야 한다 (엄격한 파싱)
    @Test func parseDoesNotSplitOnDataThatLooksLikeMarker() {
        let cmds: [PollBatch.Cmd] = [.netstats]
        // 실제 dumpsys netstats 안에 숫자로만 된 줄이 있을 수 있다 — 마커 접두가 없으면 안전
        let output = """
        @@RLY0@@
        uid=10123 tag=0x0 set=DEFAULT
        12345 67890
        """
        let r = PollBatch.parse(output, into: cmds)
        #expect(r[.netstats]?.contains("uid=10123") == true)
        #expect(r[.netstats]?.contains("12345 67890") == true)
    }

    /// 첫 명령이 빈 출력인 경우에도 이후 명령 파싱이 유지된다
    @Test func parseHandlesLeadingEmptyChunk() {
        let cmds: [PollBatch.Cmd] = [.gpuBusy, .loadavg]
        let output = """
        @@RLY0@@

        @@RLY1@@
        1.0 1.0 1.0
        """
        let r = PollBatch.parse(output, into: cmds)
        #expect(r[.gpuBusy] == nil)
        #expect(r[.loadavg] == "1.0 1.0 1.0")
    }

    // MARK: - 명령 카탈로그 정합성

    /// fast 는 slow 의 접두 — slow 틱이 fast 항목을 빠뜨리면 안 된다
    @Test func slowListStartsWithFastList() {
        #expect(PollBatch.slow.count > PollBatch.fast.count)
        #expect(Array(PollBatch.slow.prefix(PollBatch.fast.count)) == PollBatch.fast)
    }

    /// slow 배치의 기대 효과 — 종전 25회 → 1회
    @Test func slowBatchCollapsesManyCallsIntoOne() {
        #expect(PollBatch.slow.count == 25)
        // 실제 adb 호출은 fast/slow 무관하게 1회
        #expect(PollBatch.build(PollBatch.slow).contains("; ") == true)
    }

    /// 모든 명령 문자열이 비어있지 않고, 위험한 셸 제어문자가 섞이지 않았는지
    @Test func everyCommandIsNonEmptyAndBalanced() {
        for c in PollBatch.Cmd.allCases {
            #expect(!c.shell.isEmpty, "\(c) 셸 문자열이 비었다")
            // 마커 문자열을 명령에 섞으면 파싱이 깨진다
            #expect(!c.shell.contains(PollBatch.markerPrefix), "\(c) 가 마커 접두를 포함")
            // `&&` 는 앞 명령 실패 시 뒤가 건너뛰어진다 — `;` 만 사용
            #expect(!c.shell.contains("&&"), "\(c) 가 && 를 사용")
        }
    }

    /// 경로에 공백이 있는 명령이 배칭으로 깨지지 않는지 (파일 탐색기 1.16.0 함정 회귀)
    @Test func commandsWithSpacesStillBatchSafely() {
        let s = PollBatch.build([.ps])
        // ps 는 -o "PID,RSS,NAME,ARGS" 에 공백이 있는 유일한 명령
        #expect(s.contains("ps -A -o PID,RSS,NAME,ARGS --sort=-rss"))
        // 마커는 따옴표로 감싸져 경로와 무관하게 정확히 출력된다
        #expect(s.contains("echo \"@@RLY0@@\""))
    }
}
