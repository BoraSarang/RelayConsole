import Foundation
import Testing
@testable import RelayConsole

struct ThresholdGateTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - ThresholdGate (hysteresis)

    @Test func enterFiresOnceAtThreshold() {
        var gate = ThresholdGate(enter: 3, clear: 1, cooldown: 60)
        #expect(gate.evaluate(value: 2, now: t0) == .none)
        #expect(gate.evaluate(value: 3, now: t0) == .enter)
        #expect(gate.active)
        // 이미 active — 재진입 없음
        #expect(gate.evaluate(value: 4, now: t0) == .none)
    }

    @Test func hysteresisBlocksFlapping() {
        var gate = ThresholdGate(enter: 3, clear: 1, cooldown: 60)
        _ = gate.evaluate(value: 3, now: t0) // enter
        // 3↔2 flap: clear는 1 이하여야 해제
        #expect(gate.evaluate(value: 2, now: t0) == .none)
        #expect(gate.evaluate(value: 3, now: t0) == .none)
        #expect(gate.active)
    }

    @Test func clearBelowHysteresisThenCooldown() {
        var gate = ThresholdGate(enter: 3, clear: 1, cooldown: 60)
        _ = gate.evaluate(value: 3, now: t0)
        #expect(gate.evaluate(value: 1, now: t0) == .clear)
        #expect(!gate.active)
        // cooldown 중 재진입 불가
        #expect(gate.evaluate(value: 5, now: t0.addingTimeInterval(30)) == .none)
        // cooldown 만료 후 재진입
        #expect(gate.evaluate(value: 5, now: t0.addingTimeInterval(61)) == .enter)
    }

    @Test func cooldownOnlyAfterClear() {
        // enter 직후 active 중에는 cooldown 제약 없음 (상태가 active)
        var gate = ThresholdGate(enter: 3, clear: 1, cooldown: 60)
        _ = gate.evaluate(value: 3, now: t0)
        #expect(gate.evaluate(value: 4, now: t0.addingTimeInterval(1)) == .none)
        #expect(gate.evaluate(value: 0, now: t0.addingTimeInterval(2)) == .clear)
    }

    @Test func resetClearsState() {
        var gate = ThresholdGate(enter: 3, clear: 1, cooldown: 60)
        _ = gate.evaluate(value: 5, now: t0)
        gate.reset()
        #expect(!gate.active)
        #expect(gate.evaluate(value: 5, now: t0.addingTimeInterval(1)) == .enter)
    }

    // MARK: - TransitionGate (bool 전이)

    @Test func transitionFirstTickIsBaselineOnly() {
        var g = TransitionGate(cooldown: 5)
        #expect(g.evaluate(current: true, now: t0) == .none)
        #expect(g.evaluate(current: true, now: t0) == .none)
    }

    @Test func transitionFiresOnChangeOnce() {
        var g = TransitionGate(cooldown: 5)
        _ = g.evaluate(current: false, now: t0)
        #expect(g.evaluate(current: true, now: t0) == .enter)
        #expect(g.evaluate(current: true, now: t0.addingTimeInterval(1)) == .none)
        // 해제(false)는 쿨다운 무시 — 즉시 fire (clear 삼킴 방지)
        #expect(g.evaluate(current: false, now: t0.addingTimeInterval(2)) == .enter)
        #expect(g.problemActive == false)
        // 직후 ON은 쿨다운 중 — enter 스킵
        #expect(g.evaluate(current: true, now: t0.addingTimeInterval(3)) == .none)
        #expect(g.evaluate(current: false, now: t0.addingTimeInterval(6)) == .enter)
        #expect(g.evaluate(current: true, now: t0.addingTimeInterval(7)) == .none)
    }

    @Test func transitionClearIgnoresCooldown() {
        var g = TransitionGate(cooldown: 10)
        _ = g.evaluate(current: false, now: t0)
        #expect(g.evaluate(current: true, now: t0.addingTimeInterval(1)) == .enter)
        #expect(g.problemActive)
        // enter 직후 1초 만에 OFF — clear가 삼켜지면 후속조치 영구잔류
        #expect(g.evaluate(current: false, now: t0.addingTimeInterval(2)) == .enter)
        #expect(g.problemActive == false)
    }

    @Test func transitionResetForgetsBaseline() {
        var g = TransitionGate(cooldown: 5)
        _ = g.evaluate(current: false, now: t0)
        g.reset()
        #expect(g.evaluate(current: true, now: t0) == .none) // 새 baseline
    }
}
