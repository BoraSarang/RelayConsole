import Foundation
import EventKit

/// 알림 1건을 캘린더 일정에 넣는다 — **쓰기 전용**
///
/// ## 권한을 최소화한 이유 (2026-09-28)
/// 일정을 **넣기만** 하면 되는데 읽기 권한까지 요구하면 과한 요구다.
/// `requestWriteOnlyAccessToEvents` (macOS 14+) 로 **쓰기만** 요청한다.
/// → 캘린더 내용을 앱이 뒤지지 않는다
///
/// ## 실패를 구분한다 ([표시②])
/// "안 됐어요" 하나로 뭉치지 않는다. 권한이 없으면 권한을, 캘린더가 없으면
/// 캘린더를, 그 외면 원문을 — **사용자가 뭘 해야 하는지** 알 수 있게 한다.
enum CalendarBridge {

    /// 캘린더 접근 권한 요청 — **권한만** 확인한다 (일정은 넣지 않는다)
    ///
    /// 이미 허용된 앱이면 **프롬프트 없이** 끝난다 (앱 재실행 시 사용자를 붙잡지 않는다).
    /// 반환은 `.ready` / `.permissionDenied` / `.noCalendar` / `.failed`
    static func requestWriteAccess() async -> CalendarBridgeState {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)
        let granted = status == .fullAccess || status == .writeOnly
        if !granted {
            do {
                if try await store.requestWriteOnlyAccessToEvents() == false {
                    return .permissionDenied
                }
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        // 권한은 있어도 **넣을 캘린더가 없으면** 넣을 수 없다 — 구분해서 말한다
        return store.defaultCalendarForNewEvents == nil ? .noCalendar : .ready
    }

    /// 초안을 캘린더에 넣는다 — 호출 전에 권한이 있어야 한다
    static func insert(_ draft: CalendarDraft.Draft) async -> CalendarBridgeState {
        let store = EKEventStore()
        guard let calendar = store.defaultCalendarForNewEvents else { return .noCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        // ★ 알람을 **붙이지 않는다** — 캘린더가 이미 알린다. 이중 알림이 된다
        do {
            try store.save(event, span: .thisEvent)
            return .added(draft.title)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 권한 요청 → 삽입까지 한 번에 — UI 는 이 하나만 부른다
    static func addToCalendar(detail: String, serialLabel: String?, now: Date = .now) async -> CalendarBridgeState {
        await DebugLogger.shared.info("Calendar", "[INFO] 캘린더 버튼 클릭 — 권한 확인 시작")
        // 권한 확인과 삽입 사이에 상태가 바뀌지 않으므로 **한 번만** 확인한다
        let access = await requestWriteAccess()
        await DebugLogger.shared.info("Calendar", "[INFO] 권한 확인 결과: \(access)")
        switch access {
        case .ready:
            return await insert(CalendarDraft.make(detail: detail, serialLabel: serialLabel, now: now))
        case .permissionDenied, .noCalendar, .failed:
            return access   // 사유를 **그대로** — 사용자가 뭘 해야 하는지 봐야 한다
        case .added:
            return .failed("예상치 못한 상태")   // 권한 확인 단계에서는 나올 수 없다
        }
    }
}
