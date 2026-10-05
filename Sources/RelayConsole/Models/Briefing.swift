import Foundation

/// 아침 브리핑 스냅숏 — 팝오버 헤더 한 줄 데이터 (기기 전용)
struct BriefingSnapshot: Equatable, Sendable {
    let onlinePhones: Int
    let totalPhones: Int
    let activeCriticals: Int

    /// critical > 폰 오프라인 > 정상
    enum Tone: Equatable, Sendable {
        case ok, warn, bad
    }

    var tone: Tone {
        if activeCriticals > 0 { return .bad }
        if onlinePhones < totalPhones { return .warn }
        return .ok
    }

    /// L10n.format("briefing.line", …) 인자 — 순서 고정
    var formatArgs: [CVarArg] {
        [onlinePhones, totalPhones, activeCriticals]
    }
}

/// 순수 브리핑 계산 — 단위 테스트 대상
enum BriefingLogic {
    static func snapshot(
        androidOnline: Int,
        androidTotal: Int,
        appleOnline: Int,
        appleTotal: Int,
        events: [WatchEvent]
    ) -> BriefingSnapshot {
        let online = androidOnline + appleOnline
        let total = androidTotal + appleTotal
        return BriefingSnapshot(
            onlinePhones: online,
            totalPhones: total,
            activeCriticals: activeCriticalCount(events)
        )
    }

    /// `ConsoleStore.hasActiveCritical` count 버전 — **지문당 1개**로 센다
    ///
    /// ## 왜 enter 를 하나씩 세지 않는가 (2026-09-28 실측 결함)
    /// 이 함수는 전까지 `enter` **이벤트 개수**를 세고 있었다. 그런데
    /// `ThresholdGate` 는 쿨다운이 끝날 때마다 **같은 조건이면 다시 enter 를 낸다.**
    /// 게다가 기기 상태가 임계에 **머물면**(예: 발열 Status 가 계속 4) clear 가 아예 없어
    /// 하루종일 enter 가 쌓인다 — 실측에서 하루 31건이 이 한 기기에서 나왔다.
    /// → 사용자에게는 "미해소 알림 N건" 이 **74**(실측 76) 로 보이는데
    ///    실제로는 **미해소 지문이 8개**였다. **수가 거짓말을 했다.**
    ///
    /// ## 규칙
    /// - **지문당 1개.** 반복 enter 는 스택이 아니라 **한 건**이다
    /// - **최신 clear 가 위에 있으면** 해소
    /// - 어떤 지문도 위에서 볼 수 없어도(저장 상한에 밀려나) enter 가 남았다면
    ///   **미해소로 본다** — 사라진 게 아니라 "해소된 기록이 없다" 이므로
    ///
    /// ## 구현: **시각순으로** 훑는다
    /// 입력이 최신 우선으로 저장되어 있고, 순서만 보고 판단하면
    /// `[최신 enter][clear][오래된 enter]` 에서 최신 enter 까지 지워버린다.
    /// 시각순(오래된 것 → 최근 것)으로 정렬한 뒤
    /// `clear` 가 지표를 지우고, `critical enter` 가 다시 켠다.
    /// → **입력 순서와 무관**하게 같은 답을 낸다.
    static func activeCriticalCount(_ events: [WatchEvent]) -> Int {
        var active = Set<String>()
        for e in events.sorted(by: { $0.at < $1.at }) {
            let fp = e.fingerprint
            if e.isClear {
                active.remove(fp)
            } else if e.severity == .critical {
                active.insert(fp)
            }
        }
        return active.count
    }
}
