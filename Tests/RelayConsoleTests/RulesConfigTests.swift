import Foundation
import Testing
@testable import RelayConsole

/// S3 Rules as Code — 파서·검증기 (2026-09-28 · PLAN_rules_yaml)
///
/// ## 이 테스트들이 지키는 것 (순서가 중요)
/// ① **크래시** — 사용자가 쓴 파일로 앱이 죽으면 안 된다
/// ② **무결성** — 파일이 없으면 지금과 정확히 동일하게 동작한다
/// ③ **정직성** — 모르는 것·잘못된 것은 **사유와 함께** 알려져야 한다
struct RulesConfigTests {
    // MARK: - ① 크래시 회귀 (이 작업의 1순위)

    /// ★ `ThresholdGate.init` 의 `precondition(enter > clear)` 이 죽는 값을 그대로 넣는다.
    /// 검증기가 막지 않으면 **테스트 프로세스가 죽는다** — 그래서 이 테스트는 통과가 아니라
    /// "죽지 않음" 이 기대값이다.
    @Test func hysteresisViolationIsRejectedNotFatal() {
        let yaml = """
        version: 1
        rules:
          throttling: { enter: 3, clear: 5, cooldown: 60 }
          memoryLow:   { enter: 10, clear: 90, cooldown: 60 }
        """
        guard case .ok(let cfg) = RulesConfig.parse(yaml) else {
            Issue.record("파싱은 성공해야 한다 (값이 틀린 것 ≠ 문법이 틀린 것)")
            return
        }
        #expect(cfg.rejected.count == 2, "둘 다 검증에서 걸려야 한다")
        // **적용되지 않았다** — 기본값으로 돌아간다
        #expect(cfg.rule(.throttling).enter == 3, "기본값이어야 한다")
        #expect(cfg.rule(.memoryLow).enter == 90)
        // 그리고 최종 게이트용 값은 언제나 유효하다
        #expect(cfg.safeRule(.throttling).isValid)
        #expect(cfg.safeRule(.memoryLow).isValid)
    }

    /// 같은 값 (enter == clear) 도 죽는다
    @Test func equalThresholdsAreRejected() {
        let yaml = "version: 1\nrules:\n  psiPressure: { enter: 5, clear: 5, cooldown: 120 }\n"
        guard case .ok(let cfg) = RulesConfig.parse(yaml) else {
            Issue.record("파싱 성공 기대"); return
        }
        #expect(cfg.rejected.count == 1)
        #expect(cfg.safeRule(.psiPressure).isValid, "생성 직전 재확인에서 기본값으로 돌아간다")
    }

    /// NaN·Inf·음수 쿨다운
    @Test func nonFiniteAndNegativeValuesAreRejected() {
        for bad in [
            "enter: .nan, clear: 0, cooldown: 60",
            "enter: inf, clear: 0, cooldown: 60",
            "enter: 5, clear: 1, cooldown: -1",
        ] {
            let yaml = "version: 1\nrules:\n  memoryLow: { \(bad) }\n"
            guard case .ok(let cfg) = RulesConfig.parse(yaml) else {
                Issue.record("문법은 성공해야 한다: \(bad)"); return
            }
            #expect(cfg.rejected.count == 1, "걸려야 한다: \(bad)")
            #expect(cfg.safeRule(.memoryLow).isValid)
        }
    }

    /// **모든 규칙·모든 조합**이 유효한 게이트 값만 낸다 — 성질 검사
    @Test func everyConfigProducesOnlyValidRules() {
        // 사용자가 만들 수 있는 극단값을 훑는다
        let candidates: [Double] = [0, 0.0001, 1, 50, 90, 100, 1000]
        for enter in candidates {
            for clear in candidates {
                let cfg = RulesConfig(overrides: [
                    .memoryLow: RulesConfig.Rule(enter: enter, clear: clear, cooldown: 60)
                ], fileMissing: false)
                let r = cfg.safeRule(.memoryLow)
                #expect(r.isValid, "enter=\(enter) clear=\(clear) 에서 무효한 값이 새어나왔다")
                #expect(r.enter > r.clear)
            }
        }
    }

    // MARK: - ② 무결성 (파일이 없으면 지금과 동일)

    /// 파일이 없으면 **오류가 아니다** — 선택 사항이다
    @Test func missingFileIsNotAnError() {
        guard case .missing = RulesConfig.load(from: URL(fileURLWithPath: "/nonexistent/rules.yaml")) else {
            Issue.record("없는 파일은 .missing 여야 한다"); return
        }
    }

    /// 기본 구성은 **지금 코드에 박힌 값과 동일**해야 한다
    @Test func builtInMatchesCurrentHardcodedValues() {
        let c = RulesConfig.builtInConfig
        #expect(c.rule(.throttling) == .init(enter: 3, clear: 2, cooldown: 60))
        #expect(c.rule(.psiPressure) == .init(enter: 5.0, clear: 3.0, cooldown: 120))
        #expect(c.rule(.memoryLow) == .init(enter: 90, clear: 80, cooldown: 60))
        #expect(c.rule(.chargeChanged).cooldown == 5)
        #expect(c.rule(.protectionChanged).cooldown == 10)
        #expect(c.rule(.lowPowerChanged).cooldown == 10)
    }

    /// `loadSpike` 는 유일하게 **파생값**(코어수×2)을 쓴다
    @Test func loadSpikeDefaultsToCoreDerivedValue() {
        let c = RulesConfig.builtInConfig
        #expect(c.rule(.loadSpike, cores: 8) == .init(enter: 16, clear: 8, cooldown: 60))
        #expect(c.rule(.loadSpike, cores: 1) == .init(enter: 2, clear: 1, cooldown: 60))
        // 코어수가 0 이면 나눗셈·0 게이트가 된다 → 1로 본다
        #expect(c.rule(.loadSpike, cores: 0).enter == 2)
    }

    /// 사용자가 절대값을 주면 파생값을 대체한다
    @Test func loadSpikeOverrideWinsOverDerived() {
        let yaml = "version: 1\nrules:\n  loadSpike: { enter: 8, clear: 4, cooldown: 90 }\n"
        guard case .ok(let c) = RulesConfig.parse(yaml) else { Issue.record("파싱 실패"); return }
        #expect(c.rule(.loadSpike, cores: 8) == .init(enter: 8, clear: 4, cooldown: 90))
    }

    // MARK: - ③ 정직성 (모르는 것·잘못된 것을 알린다)

    @Test func unknownTopLevelKeyIsReported() {
        let yaml = "version: 1\nwhatever: 1\nrules:\n  memoryLow: { enter: 90, clear: 80, cooldown: 60 }\n"
        guard case .failed(let why) = RulesConfig.parse(yaml) else {
            Issue.record("모르는 키는 조용히 넘기면 안 된다"); return
        }
        #expect(why.contains("whatever"))
    }

    @Test func unknownRuleIsReported() {
        let yaml = "version: 1\nrules:\n  batteryLife: { enter: 5, clear: 1, cooldown: 60 }\n"
        guard case .failed(let why) = RulesConfig.parse(yaml) else {
            Issue.record("모르는 규칙은 오류여야 한다"); return
        }
        #expect(why.contains("batteryLife"))
    }

    /// 규칙 안의 모르는 키 — 사용자가 오타 냈다 (e.g. `colldown`)
    @Test func typoInsideRuleIsReported() {
        let yaml = "version: 1\nrules:\n  memoryLow: { enter: 90, clear: 80, colldown: 60 }\n"
        guard case .ok(let c) = RulesConfig.parse(yaml) else {
            // 통째로 실패해도acceptable — 사유만 있으면 된다
            return
        }
        #expect(c.rejected.first?.contains("colldown") == true, "오타 키는 사유로 알려야 한다")
    }

    @Test func nonNumericValueIsReported() {
        let yaml = "version: 1\nrules:\n  memoryLow: { enter: 높음, clear: 80, cooldown: 60 }\n"
        guard case .ok(let c) = RulesConfig.parse(yaml) else { return }
        #expect(c.rejected.count == 1)
        #expect(c.safeRule(.memoryLow).isValid)
    }

    @Test func missingRulesBlockIsReported() {
        guard case .failed(let why) = RulesConfig.parse("version: 1\n") else {
            Issue.record("rules 블록이 없으면 실패여야 한다"); return
        }
        #expect(why.contains("rules"))
    }

    @Test func unsupportedVersionIsReported() {
        guard case .failed(let why) = RulesConfig.parse("version: 99\nrules:\n  memoryLow: { enter: 9, clear: 8, cooldown: 6 }\n") else {
            Issue.record("버전 불일치는 오류여야 한다"); return
        }
        #expect(why.contains("99"))
    }

    // MARK: - 파일 전체 (주석·공백·전이 전용)

    @Test func commentsAndBlankLinesAreIgnored() {
        let yaml = """
        # 내 규칙
        version: 1

        rules:
          # 발열
          throttling: { enter: 4, clear: 1, cooldown: 30 }   # 더 민감하게
          chargeChanged: { cooldown: 2 }        # 전이 전용 — enter/clear 불필요
        """
        guard case .ok(let c) = RulesConfig.parse(yaml) else {
            Issue.record("주석이 섞여 있어도 파싱되어야 한다"); return
        }
        #expect(c.rejected.isEmpty, "기각 사유가 있으면 안 된다: \(c.rejected)")
        #expect(c.rule(.throttling) == .init(enter: 4, clear: 1, cooldown: 30))
        #expect(c.rule(.chargeChanged).cooldown == 2)
    }

    @Test func oversizedFileIsRejected() {
        let filler = String(repeating: "# padding\n", count: (RulesConfig.maxBytes / 10) + 10)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rules_oversize.yaml")
        try? Data(filler.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .failed(let why) = RulesConfig.load(from: url) else {
            Issue.record("크기 상한은 지켜야 한다"); return
        }
        #expect(why.contains("너무 큼"))
    }
}

/// S3 — **엔진이 실제로 설정을 따르는가** (격리 인스턴스)
///
/// 1단계(파서)만으로는 충분하지 않다. "파싱은 되는데 엔진이 안 읽는다" 가
/// **가장 조용한 실패**라 — 게이트를 실제로 만들어 판정이 바뀌는지 본다.
@MainActor
struct WatchEngineRulesTests {
    /// 기준선 — 설정이 없으면 **지금과 정확히 같은 판정**이어야 한다 (throttling enter ≥3)
    @Test func defaultConfigBehavesExactlyAsBefore() {
        let e = WatchEngine()
        let t0 = Date()
        #expect(e.feedThermal(serial: "S", status: 2, now: t0) == nil, "2는 아무 일도 없다")
        #expect(e.feedThermal(serial: "S", status: 3, now: t0)?.kind == .throttling, "3부터 발화")
    }

    @Test func defaultMemoryGateStillFiresAt90() {
        let e = WatchEngine()
        let t0 = Date()
        #expect(e.feedMemory(serial: "S", usedPct: 89, now: t0) == nil)
        #expect(e.feedMemory(serial: "S", usedPct: 90, now: t0)?.kind == .memoryLow)
    }

    /// YAML 로 임계값을 낮추면 **더 일찍 발화**한다 — 설정이 실제 판정에 쓰인다
    @Test func overrideActuallyChangesTheThreshold() {
        let e = WatchEngine()
        guard case .ok(let cfg) = RulesConfig.parse(
            "version: 1\nrules:\n  throttling: { enter: 5, clear: 4, cooldown: 60 }\n") else {
            Issue.record("파싱 실패"); return
        }
        e.setRules(cfg)
        let t0 = Date()
        #expect(e.feedThermal(serial: "S", status: 3, now: t0) == nil, "3은 이제 발화하지 않는다")
        #expect(e.feedThermal(serial: "S", status: 5, now: t0)?.kind == .throttling, "5부터 발화")
    }

    /// ★ 게이트를 **반복 생성해도 죽지 않는다** — 사용자가 여러 기기·여러 틱에서 같은 규칙을 쓴다
    @Test func repeatedGateCreationNeverTraps() {
        let e = WatchEngine()
        for serial in (0..<50).map({ "dev-\($0)" }) {
            _ = e.feedThermal(serial: serial, status: 3, now: Date())
            _ = e.feedMemory(serial: serial, usedPct: 95, now: Date())
        }
    }

    /// 나쁜 값이 들어온 설정이어도 **생성 시점에 죽지 않는다** (안전장치 경로)
    @Test func invalidConfigCannotProduceTrappingGate() {
        // 검증기를 통과하지 못한 값을 직접 밀어넣는다 (파서가 막아야 했지만 방어 심층도 확인)
        let bad = RulesConfig(overrides: [
            .throttling: RulesConfig.Rule(enter: 1, clear: 99, cooldown: 60)
        ], fileMissing: false)
        let e = WatchEngine()
        e.setRules(bad)
        let t0 = Date()
        _ = e.feedThermal(serial: "S", status: 3, now: t0)   // 죽지 않아야 한다
    }
}

/// S3 — **실제 파일** 경로 (파서만 말고 I/O 포함)
struct RulesConfigFileTests {
    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("relay-rules-\(name).yaml")
    }

    private func write(_ text: String, _ name: String) -> URL {
        let url = tempURL(name)
        try? Data(text.utf8).write(to: url)
        return url
    }

    /// 파일이 없으면 `.missing` — **오류가 아니다** (선택 사항)
    @Test func absentFileYieldsMissing() {
        let url = tempURL("absent.yaml")
        try? FileManager.default.removeItem(at: url)
        #expect(RulesConfig.load(from: url) == .missing)
    }

    /// 정상 파일이 실제로 읽혀 임계값에 반영된다
    @Test func validFileIsApplied() throws {
        let url = write("""
        version: 1
        rules:
          memoryLow: { enter: 95, clear: 90, cooldown: 45 }
        """, "valid.yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .ok(let c) = RulesConfig.load(from: url) else {
            Issue.record("정상 파일이 실패했다"); return
        }
        #expect(c.fileMissing == false)
        #expect(c.rejected.isEmpty)
        #expect(c.rule(.memoryLow) == .init(enter: 95, clear: 90, cooldown: 45))
    }

    /// ★ 크래시 값을 담은 실제 파일 — 앱이 죽지 않아야 한다
    @Test func realFileWithInvertedThresholdsDoesNotTrap() throws {
        let url = write("""
        version: 1
        rules:
          throttling: { enter: 3, clear: 5, cooldown: 60 }
        """, "inverted.yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .ok(let c) = RulesConfig.load(from: url) else {
            Issue.record("문법은 성공해야 한다 — 값 판정은 검증기의 몫"); return
        }
        #expect(c.rejected.count == 1)
        // 파일에 적힌 값이 **적용되지 않았음**을 확인 (기본값 3/2)
        #expect(c.rule(.throttling).enter == 3)
        #expect(c.rule(.throttling).clear == 2)
        #expect(c.safeRule(.throttling).isValid)
    }

    /// 깨진 파일은 사유와 함께 실패 — 조용히 기본값으로 넘어가지 않는다
    @Test func brokenFileReportsReason() throws {
        let url = write("version: 1\nrules:\n  nope: { enter: 1, clear: 0, cooldown: 5 }\n", "broken.yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .failed(let why) = RulesConfig.load(from: url) else {
            Issue.record("깨진 파일은 .failed 여야 한다"); return
        }
        #expect(why.contains("nope"))
    }
}
