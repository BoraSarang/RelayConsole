import Foundation
import Testing
@testable import RelayConsole

/// 2단계 — 실제 폴링 주기 정직성 테스트
///
/// 종전 `DroidMetrics`는 "5s × 60 = 5분" 이라는 주석과 달리 실제로는
/// `sleep(5s) + tick 소요시간`이 주기라 60칸이 조용히 늘어나 있었다.
/// 이제 실제 창을 측정해 기록한다.
struct DroidMetricsWindowTests {

    /// 설계상 목표 주기는 5초 — 주석과 실제 값이 어긋나지 않게 고정
    @Test func nominalIntervalIsFiveSeconds() {
        #expect(DroidMetrics.nominalInterval == 5)
    }

    /// 링 용량은 60 유지 (기존 동작 보존)
    @Test func capacityIsUnchangedAtSixty() {
        #expect(DroidMetrics.capacity == 60)
    }

    /// 샘플 1개뿐이면 실제 창을 알 수 없다 — 거짓 수치를 만들지 않는다
    @Test func singleSampleHasNoWindow() {
        var m = DroidMetrics()
        m.push(cpu: 10, at: Date(timeIntervalSince1970: 1000))
        #expect(m.windowSeconds == nil)
        #expect(m.actualInterval == nil)
    }

    /// 주기가 정확히 5초면 실제 창이 60샘플 기준 295초 (5분 - 1구간)
    @Test func regularFiveSecondCadenceReportsRealWindow() {
        var m = DroidMetrics()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<60 {
            m.push(cpu: Double(i), at: t0.addingTimeInterval(Double(i) * 5))
        }
        #expect(m.cpuHistory.count == 60)
        let w = try? #require(m.windowSeconds)
        #expect(w == 295)   // 59구간 × 5초
        let iv = try? #require(m.actualInterval)
        #expect(abs((iv ?? 0) - 5) < 0.001)
    }

    /// **정직성 핵심** — tick 이 느려 실제 주기가 9초면 9초를 보고해야 한다
    /// 종전에는 "5분"이라고 잘못 표시될 뻔했다.
    @Test func slowCadenceIsReportedHonestlyNotAsFiveMinutes() {
        var m = DroidMetrics()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<60 {
            m.push(cpu: Double(i), at: t0.addingTimeInterval(Double(i) * 9))
        }
        let iv = try? #require(m.actualInterval)
        #expect(abs((iv ?? 0) - 9) < 0.001)
        let w = try? #require(m.windowSeconds)
        // 60샘플이 9분(540초)이므로 "5분"이 아니다
        #expect((w ?? 0) > 500)
    }

    /// 링이 가득 차도 firstAt 은 최초 샘플을 유지해 실제 창이 확장된다
    @Test func windowKeepsGrowingAfterRingWraps() {
        var m = DroidMetrics()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<200 {
            m.push(cpu: Double(i % 60), at: t0.addingTimeInterval(Double(i) * 5))
        }
        #expect(m.cpuHistory.count == DroidMetrics.capacity)
        // 200샘플 × 5초 = 995초 창
        let w = try? #require(m.windowSeconds)
        #expect(w == 995)
    }

    /// 값이 없는 push도 시각은 갱신되어야 창이 실제 폴링 주기를 반영한다
    @Test func timestampAdvancesEvenWhenMetricIsNil() {
        var m = DroidMetrics()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        m.push(cpu: 1, at: t0)
        m.push(cpu: nil, at: t0.addingTimeInterval(5))
        m.push(cpu: 2, at: t0.addingTimeInterval(10))
        #expect(m.cpuHistory.count == 2)
        let w = try? #require(m.windowSeconds)
        #expect(w == 10)
    }
}
