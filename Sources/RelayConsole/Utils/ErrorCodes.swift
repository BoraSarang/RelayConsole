import Foundation

enum ErrorCode: String, Error {
    case adbBinaryMissing = "E-MAC-ADB-0001"
    case adbConnectFailed = "E-MAC-ADB-0002"
    case adbParseFailed = "E-MAC-ADB-0003"
    case storeInitFailed = "E-MAC-STORE-0001"
    case storeWriteFailed = "E-MAC-STORE-0002"
    case storeReadFailed = "E-MAC-STORE-0003"
    case watchStartFailed = "E-MAC-WATCH-0001"

    var koMessage: String {
        switch self {
        case .adbBinaryMissing: return "ADB 바이너리를 찾을 수 없습니다. Android Platform-Tools를 설치해 주세요."
        case .adbConnectFailed: return "기기에 연결할 수 없습니다. 무선 디버깅과 허용 여부를 확인해 주세요."
        case .adbParseFailed: return "기기 응답 파싱에 실패했습니다."
        case .storeInitFailed: return "이벤트 저장소 초기화에 실패했습니다."
        case .storeWriteFailed: return "이벤트 저장에 실패했습니다. 디스크 여유 공간을 확인해 주세요."
        case .storeReadFailed: return "이벤트 조회에 실패했습니다."
        case .watchStartFailed: return "설정 감시 시작에 실패했습니다."
        }
    }
}
