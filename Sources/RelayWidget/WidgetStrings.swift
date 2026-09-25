import Foundation

/// 위젯 문자열 — 앱과 동일 Localizable.strings 테이블 공유 (xcodegen이 앱 lproj를 리소스로 포함)
/// 런타임 lookup은 appex 번들 기준 — SwiftPM `Bundle.module` 아님
enum WidgetStrings {
    static let bundle = Bundle(for: WidgetBundleAnchor.self)
    private final class WidgetBundleAnchor {}

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }

    /// "3분 전" / "3 min ago" — 마지막 업데이트 신선도 표시 ([표시②])
    static func relative(_ date: Date, reference: Date = .now) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: reference)
    }

    /// 이벤트 시각 "HH:mm"
    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
