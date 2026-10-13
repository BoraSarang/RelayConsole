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

    /// 지문당 미해소 **최대** 심각도 — clear가 지표를 지우고, enter가 켠다 (위와 동일 규칙).
    /// 메뉴바 ambient 신호용: critical > warning > info. nil = 미해소 없음.
    /// serial 지정 시 그 기기만 (열별 판정), nil이면 전 기기 (점 색 판정).
    static func maxUnresolvedSeverity(
        _ events: [WatchEvent],
        serial: String? = nil
    ) -> WatchSeverity? {
        var active: [String: WatchSeverity] = [:]
        for e in events.sorted(by: { $0.at < $1.at }) {
            guard serial == nil || e.serial == serial else { continue }
            if e.isClear {
                active.removeValue(forKey: e.fingerprint)
            } else if let prev = active[e.fingerprint] {
                active[e.fingerprint] = max(prev, e.severity)
            } else {
                active[e.fingerprint] = e.severity
            }
        }
        return active.values.max()
    }

    /// 메뉴바 표시 열 — 온라인만, serial 정렬, 최대 2열. 설정 off면 선택 기기만.
    static func menuPickedColumns(
        devices: [DeviceSnapshot],
        selectedSerial: String?,
        showAll: Bool
    ) -> [DeviceSnapshot] {
        let online = devices.filter(\.isOnline).sorted { $0.serial < $1.serial }
        guard !online.isEmpty else { return [] }
        if showAll { return Array(online.prefix(2)) }
        if let sel = selectedSerial, let d = online.first(where: { $0.serial == sel }) {
            return [d]
        }
        return Array(online.prefix(1))
    }

    /// 메뉴바 열별 셀 값 — `menuPickedColumns` 순서 그대로의 배열 (필드 단위 렌더용).
    /// nil = 그릴 것 없음 (아이콘만).
    ///
    /// ## 왜 문자열을 합치지 않는가 (B안, 2026-10-13)
    /// 구 `menuSpeedLines` 는 한 줄 문자열로 합쳐 공백으로 열을 흉내 냈으나,
    /// SF 폰트에서 공백·단위 글리프 pt 폭이 달라 열이 어긋났다 (A안 실측 폐기).
    /// `RelayMenuBarView` 의 고정폭 `NSTextField` + 우측 정렬이 열을 못박으므로
    /// 여기서 패딩·구분자를 넣지 않는다. 미측정은 "—" (0과 구분 [표시②]).
    static func menuSpeedCells(
        devices: [DeviceSnapshot],
        selectedSerial: String?,
        showAll: Bool
    ) -> (up: [String], down: [String])? {
        let picked = menuPickedColumns(
            devices: devices, selectedSerial: selectedSerial, showAll: showAll
        )
        guard !picked.isEmpty else { return nil }
        func cell(_ mbps: Double?) -> String {
            mbps.map(AdbClient.menuRateAlways) ?? "—"
        }
        return (
            up: picked.map { cell($0.netUpMBps) },
            down: picked.map { cell($0.netDownMBps) }
        )
    }

    /// 팝오버 범례용 열 번호 (1-based) — 메뉴바 열과 동일 순서. 표시 안 되면 nil.
    static func menuColumnIndex(
        devices: [DeviceSnapshot],
        selectedSerial: String?,
        showAll: Bool,
        serial: String
    ) -> Int? {
        let picked = menuPickedColumns(
            devices: devices, selectedSerial: selectedSerial, showAll: showAll
        )
        guard let i = picked.firstIndex(where: { $0.serial == serial }) else { return nil }
        return i + 1
    }
}
