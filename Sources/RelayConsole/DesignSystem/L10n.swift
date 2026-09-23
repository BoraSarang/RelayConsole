import Foundation

/// Localized string lookup for SwiftPM bundle (ko source, en secondary).
/// Keys match Resources/Localizable.xcstrings and *.lproj/Localizable.strings.
enum L10n {
    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }

    static var na: String { string("common.na") }
}
