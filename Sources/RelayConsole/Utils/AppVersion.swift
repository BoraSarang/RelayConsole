import Foundation

/// 앱 버전 단일 진실원처 — `Info.plist`의 `CFBundleShortVersionString`에서만 읽는다.
///
/// ## 왜 필요한가
/// 버전이 화면·로그에 하드코딩되어 있으면 버전 상승을 여러 곳에 맞춰야 했고,
/// 실제로 `1.15.0`·`1.16.0` 상승 때 3곳이 이전 값(`1.14.0`·`1.15.0`)으로 남았다.
/// 표시와 로그는 반드시 이 값만 쓸 것.
enum AppVersion {

    /// 표시용 버전 (예: "1.16.0")
    static var display: String { value(from: .main) }

    /// 포맷팅용 (예: "v1.16.0")
    static var prefixed: String { "v\(display)" }

    /// 번들에서 버전을 읽는다 — 테스트는 다른 번들을 주입할 수 있다
    static func value(from bundle: Bundle) -> String {
        if let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.isEmpty {
            return v
        }
        if let v = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !v.isEmpty {
            return v
        }
        return "0"
    }

    /// plist 파일을 직접 읽는다 — `Bundle.main`이 앱 번들이 아닌 환경(예: 테스트)에서
    /// **출시 정본**을 검증할 때 쓴다.
    static func fromPlist(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any] else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }
}
