import Foundation

/// **충전 방치** — "위험" 이 아니라 "아무도 충전하지 않았다" 를 시간으로 잰다
///
/// ## 왜 존재하는가
/// `WatchEngine` 의 배터리 규칙은 **순간 임계**(20/10/5%)다. 20% 를 한 번 가로지르면
/// 울리고, 충전 재상승 시 재무장된다. 그래서 **"이 기기는 6시간째 15% 에 머물러 있다"** 를
/// 말하지 못한다. 기기가 위험한 게 아니라 **아무도 챙기지 않았다**는 사실이 사라진다.
///
/// ## 왜 순수 상태 기계인가
/// 시간원을 **주입**한다(`now` 가 매 호출에 온다). 안 그러면 테스트가 시계에 기대고,
/// "6시간째" 를 재현할 수 없다. 저장도 없다 — 상태는 호출자가 들고 있다.
///
/// ## 정직성 규칙
/// - **배터리 미확인(`nil`)** → 방치 아님으로 **단정하지 않는다.** `since` 를 **유지**한다.
///   모르는 구간이 방치를 끊는다고 볼 근거가 없다
/// - **충전 중** → `since` 를 **초기화**한다. 충전이 방치를 끊는다는 뜻이다
/// - **임계 초과 → 충전 → 다시 하강** → **새로 시작.** 중간에 충전이 있었냐로 갈린다
final class BatteryNeglectTracker: @unchecked Sendable {
    /// 앱 전역 단일 — 폴링(DeviceMonitor)이 먹고, `/metrics` 가 읽는다
    static let shared = BatteryNeglectTracker()

    /// 기기별 방치 시작 시각 — 조건이 처음 성립한 `now`
    private var since: [String: Date] = [:]
    private let lock = NSLock()

    /// 현재 기준값 — `rules.yaml` 의 `battery.neglectPercent` 가 이걸 바꾼다
    private var percentThreshold: Int

    init(percentThreshold: Int = RulesConfig.Battery.builtIn.neglectPercent) {
        self.percentThreshold = percentThreshold
    }

    /// 한 기기의 관측을 반영한다 — **매 폴링마다** 호출한다. 방치 지속 초를 돌려준다
    @discardableResult
    func observe(serial: String, level: Int?, isCharging: Bool?, now: Date) -> Int {
        lock.lock()
        defer { lock.unlock() }

        // ① 충전 중 — 방치는 **끝난다**. 충전이 방치를 끊는다는 뜻이다
        if isCharging == true {
            since.removeValue(forKey: serial)
            return 0
        }

        // ② 배터리 미확인 — **끊지 않는다.** 모르는 구간이 방치를 끊는다는 근거가 없다
        guard let level else {
            return since[serial].map { Int(now.timeIntervalSince($0)) } ?? 0
        }

        // ③ 기준을 넘으면 방치가 아니다 — 여기서 **새로 시작**할 수 있게 끊는다
        if level > percentThreshold {
            since.removeValue(forKey: serial)
            return 0
        }

        // ④ 방치 중 — 시작 시각은 **처음 성립할 때 고정**한다
        let start = since[serial] ?? now
        since[serial] = start
        return Int(now.timeIntervalSince(start))
    }

    /// 방치 중인 기기와 그 지속 초 — **지표가 읽는다**
    func snapshot(now: Date) -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return since.mapValues { Int(now.timeIntervalSince($0)) }
    }

    /// 관측이 끊긴 기기 정리 — 폴링이 사라진 기기가 영원히 방치로 남지 않게
    func forget(serials: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        for s in serials where since[s] != nil {
            since.removeValue(forKey: s)
        }
    }

    /// 상태 초기화 — 설정 변경으로 임계가 바뀌면 방치 구간도 다시 잰다
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        since.removeAll()
    }

    /// 임계값을 바꾼다 — **의미가 달라지므로 누적도 비운다**
    ///
    /// 임계 20% 에서 3시간을 잰 뒤 임계가 90% 로 바뀌면, 그 3시간은 "90% 아래 3시간" 이
    /// 아니라 "20% 아래 3시간" 이다. 그대로 두면 엉뚱한 시간이 방치로 보고된다.
    func setThreshold(_ percent: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard percent != percentThreshold else { return }
        percentThreshold = percent
        since.removeAll()
    }
}
