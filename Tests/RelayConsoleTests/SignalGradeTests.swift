import Testing
@testable import RelayConsole

struct SignalGradeTests {
    @Test func rsrpScoreBands() {
        #expect(SignalGrade.rsrpScore(-70) == 5)
        #expect(SignalGrade.rsrpScore(-80) == 5)
        #expect(SignalGrade.rsrpScore(-81) == 4)
        #expect(SignalGrade.rsrpScore(-90) == 4)
        #expect(SignalGrade.rsrpScore(-99) == 3)
        #expect(SignalGrade.rsrpScore(-100) == 3)
        #expect(SignalGrade.rsrpScore(-105) == 2)
        #expect(SignalGrade.rsrpScore(-110) == 2)
        #expect(SignalGrade.rsrpScore(-125) == 1)
    }

    @Test func rsrqScoreBands() {
        #expect(SignalGrade.rsrqScore(-5) == 5)
        #expect(SignalGrade.rsrqScore(-8) == 5)
        #expect(SignalGrade.rsrqScore(-9) == 4)
        #expect(SignalGrade.rsrqScore(-10) == 4)
        #expect(SignalGrade.rsrqScore(-11) == 3)
        #expect(SignalGrade.rsrqScore(-12) == 3)
        #expect(SignalGrade.rsrqScore(-13) == 2)
        #expect(SignalGrade.rsrqScore(-15) == 2)
        #expect(SignalGrade.rsrqScore(-20) == 1)
    }

    @Test func sinrScoreBands() {
        #expect(SignalGrade.sinrScore(20) == 5)
        #expect(SignalGrade.sinrScore(15) == 5)
        #expect(SignalGrade.sinrScore(10) == 4)
        #expect(SignalGrade.sinrScore(8) == 4)
        #expect(SignalGrade.sinrScore(4) == 3)
        #expect(SignalGrade.sinrScore(0) == 3)
        #expect(SignalGrade.sinrScore(-3) == 2)
        #expect(SignalGrade.sinrScore(-5) == 2)
        #expect(SignalGrade.sinrScore(-10) == 1)
    }

    /// 실측 기기(KT · LTE) — 사용자 제공 표의 기준값
    @Test func overallMeasuredDeviceIsFair() {
        let g = SignalGrade.overall(rsrp: -99, rsrq: -12, sinr: 4)
        #expect(g == .fair)
    }

    @Test func overallStrongSignalIsExcellent() {
        #expect(SignalGrade.overall(rsrp: -70, rsrq: -6, sinr: 20) == .excellent)
    }

    @Test func overallWeakSignalIsBad() {
        #expect(SignalGrade.overall(rsrp: -120, rsrq: -20, sinr: -12) == .bad)
    }

    @Test func overallMissingMetricReturnsNil() {
        #expect(SignalGrade.overall(rsrp: nil, rsrq: -12, sinr: 4) == nil)
        #expect(SignalGrade.overall(rsrp: -99, rsrq: nil, sinr: 4) == nil)
        #expect(SignalGrade.overall(rsrp: -99, rsrq: -12, sinr: nil) == nil)
    }

    @Test func fromScoreMapsAllLevels() {
        #expect(SignalGrade.from(score: 5) == .excellent)
        #expect(SignalGrade.from(score: 4) == .good)
        #expect(SignalGrade.from(score: 3) == .fair)
        #expect(SignalGrade.from(score: 2) == .poor)
        #expect(SignalGrade.from(score: 1) == .bad)
        #expect(SignalGrade.from(score: 0) == .bad)
        #expect(SignalGrade.from(score: 99) == .excellent)
    }
}
