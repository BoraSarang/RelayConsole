import Foundation

enum ErrorCode: String, Error {
    case adbBinaryMissing = "E-MAC-ADB-0001"
    case adbConnectFailed = "E-MAC-ADB-0002"
    case adbParseFailed = "E-MAC-ADB-0003"
    case storeInitFailed = "E-MAC-STORE-0001"
    case storeWriteFailed = "E-MAC-STORE-0002"
    case storeReadFailed = "E-MAC-STORE-0003"
    case watchStartFailed = "E-MAC-WATCH-0001"
    case scrcpyBinaryMissing = "E-MAC-SCRCPY-0001"
    case scrcpyBrewMissing = "E-MAC-SCRCPY-0002"
    case scrcpyInstallFailed = "E-MAC-SCRCPY-0003"
    case scrcpyLaunchFailed = "E-MAC-SCRCPY-0004"
    case appleBinaryMissing = "E-MAC-APL-0001"
    case appleConnectFailed = "E-MAC-APL-0002"
    case appleParseFailed = "E-MAC-APL-0003"
    case appleInstallFailed = "E-MAC-APL-0004"

    var koMessage: String {
        switch self {
        case .adbBinaryMissing: return "ADB 바이너리를 찾을 수 없습니다. Android Platform-Tools를 설치해 주세요."
        case .adbConnectFailed: return "기기에 연결할 수 없습니다. 무선 디버깅과 허용 여부를 확인해 주세요."
        case .adbParseFailed: return "기기 응답 파싱에 실패했습니다."
        case .storeInitFailed: return "이벤트 저장소 초기화에 실패했습니다."
        case .storeWriteFailed: return "이벤트 저장에 실패했습니다. 디스크 여유 공간을 확인해 주세요."
        case .storeReadFailed: return "이벤트 조회에 실패했습니다."
        case .watchStartFailed: return "설정 감시 시작에 실패했습니다."
        case .scrcpyBinaryMissing: return "scrcpy를 찾을 수 없습니다. 설치가 필요합니다."
        case .scrcpyBrewMissing: return "Homebrew를 찾을 수 없습니다. brew로 scrcpy를 설치해 주세요."
        case .scrcpyInstallFailed: return "scrcpy 설치에 실패했습니다. 터미널에서 brew install scrcpy 를 실행해 보세요."
        case .scrcpyLaunchFailed: return "미러링을 시작할 수 없습니다. 기기 연결과 scrcpy 버전을 확인해 주세요."
        case .appleBinaryMissing: return "libimobiledevice(idevice_id/ideviceinfo)를 찾을 수 없습니다."
        case .appleConnectFailed: return "Apple 기기에 연결할 수 없습니다. 신뢰 여부를 확인해 주세요."
        case .appleParseFailed: return "Apple 기기 응답 파싱에 실패했습니다."
        case .appleInstallFailed: return "libimobiledevice 설치에 실패했습니다. brew install libimobiledevice 를 실행해 보세요."
        }
    }
}
