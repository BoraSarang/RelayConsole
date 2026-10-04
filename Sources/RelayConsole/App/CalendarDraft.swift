import Foundation

/// 알림 → 캘린더 일정 — **무엇을 넣을지** 를 정하는 순수 로직
///
/// ## 왜 EventKit 밖으로 뺐나 (2026-09-28)
/// `EKEventStore` 는 테스트에서 만들 수 없다. 그래야 "제목이 뭔가" 를
/// **눈으로만** 확인할 수 있었다. 순수 함수로 떼어 내면 **값이 틀리면 테스트가 죽는다.**
///
/// ## 왜 앱이 대신 넣지 않는가
/// 캘린더는 **사용자 데이터**다. 앱이 "이건 중요하니 넣어뒀어요" 라고 하면
/// 캘린더가 신뢰를 잃고, 알림마다 일정이 쌓여 사용자가 권한을 끈다.
/// → **누르면 1건만 넣는다.** 판단은 전부 사용자.
enum CalendarDraft {
    /// 넣을 일정의 내용 — EventKit 없이 검증할 수 있다
    struct Draft: Equatable, Sendable {
        var title: String
        var start: Date
        var end: Date
    }

    /// 기본 시작 — **지금 + 15분**. 캘린더는 "언제 볼지" 를 물으면 그것이 답이다
    static let leadMinutes: Double = 15
    /// 기본 길이 — 알림 하나를 확인하는 데 걸리는 시간
    static let durationMinutes: Double = 15

    /// 제목 — **알림의 문구를 그대로** 옮긴다. 맥락을 바꾸지 않는다
    ///
    /// 두 줄로 나누는 이유: 캘린더는 제목을 1줄로 자른다. 앞쪽에 **무엇이** 있고
    /// 뒤에 **어디서** 일어났는지 두면, 잘려도 의미가 남는다.
    static func title(detail: String, serialLabel: String?) -> String {
        let who = serialLabel?.trimmingCharacters(in: .whitespaces) ?? ""
        let d = detail.trimmingCharacters(in: .whitespaces)
        if who.isEmpty { return d }
        // 이미 들어 있으면 덧붙이지 않는다 — 실측 "크래시 감지 · IP · … · IP" 중복
        if d.contains(who) { return d }
        return "\(d) · \(who)"
    }

    /// 일정 초안 — 순수 계산 (시각은 주입)
    static func make(detail: String, serialLabel: String?, now: Date) -> Draft {
        let start = now.addingTimeInterval(leadMinutes * 60)
        return Draft(
            title: title(detail: detail, serialLabel: serialLabel),
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60)
        )
    }
}

/// 캘린더 연동의 **결과 상태** — 실패를 숨기지 않는다 ([표시②])
///
/// "실패" 를 하나로 뭉치지 않는다. **무엇이 다른지** 를 구분해야 사용자가
/// 뭘 해야 하는지 안다.
enum CalendarBridgeState: Equatable, Sendable {
    /// 권한 있음 + 넣을 캘린더 있음 — **진행 가능**
    case ready
    /// 권한이 없어 요청 자체가 안 됐거나 거부됨
    case permissionDenied
    /// 권한은 있지만 **기본 캘린더가 없음** — 일정을 넣을 곳이 없다
    case noCalendar
    /// 성공 — 넣은 일정의 제목
    case added(String)
    /// 그 외 오류 (원문 유지)
    case failed(String)

    /// 사람이 읽을 **제목** — 상태마다 다르다. 합쳐지지 않는다 ([표시②])
    var titleKey: String {
        switch self {
        case .ready: return "calendar.add"
        case .permissionDenied: return "calendar.denied.title"
        case .noCalendar: return "calendar.noCalendar.title"
        case .added: return "calendar.added.title"
        case .failed: return "calendar.failed.title"
        }
    }

    /// 사람이 읽을 **본문** — 실패는 원문을 그대로 보여준다
    var messageArgs: (key: String, args: [CVarArg]) {
        switch self {
        case .ready: return ("calendar.add", [])
        case .permissionDenied: return ("calendar.denied", [])
        case .noCalendar: return ("calendar.noCalendar", [])
        case .added(let title): return ("calendar.added", [title])
        case .failed(let why): return ("calendar.failed", [why])
        }
    }

    /// 성공했을 때 넣은 제목 — 뭐가 들어갔는지 알 수 있어야 한다
    var addedTitle: String? {
        if case .added(let t) = self { return t }
        return nil
    }

    /// 실패 원문 — 앱이 요약하면 **진짜 원인을 잃는다**
    var errorText: String? {
        if case .failed(let e) = self { return e }
        return nil
    }
}
