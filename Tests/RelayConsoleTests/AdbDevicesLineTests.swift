import Testing
@testable import RelayConsole

/// `adb devices` 한 줄 파싱 — **serial 에 공백이 들어갈 수 있다** (2026-10-19 실측)
///
/// macOS mDNSResponder 가 중복 mDNS 등록을 `" (2)"` 로 개명하면 adb 는 그 이름을
/// 그대로 serial 로 쓴다. 첫 공백에서 자르면 상태가 `(2)...` 가 되어
/// **연결된 기기를 '연결 끊김'으로 오판**한다.
struct AdbDevicesLineTests {

    @Test func mdnsSerialWithSpaceKeepsWholeSerialAndState() {
        let line = "adb-R5CT215F4QK-iL8Q9e (2)._adb-tls-connect._tcp\tdevice"
        let parsed = DeviceMonitor.parseDeviceLine(line)
        #expect(parsed?.serial == "adb-R5CT215F4QK-iL8Q9e (2)._adb-tls-connect._tcp")
        #expect(parsed?.state == "device")
    }

    @Test func plainUsbAndTcpSerials() {
        #expect(DeviceMonitor.parseDeviceLine("R5CT215F4QK\tdevice")?.serial == "R5CT215F4QK")
        #expect(DeviceMonitor.parseDeviceLine("192.168.86.49:46249\tdevice")?.serial == "192.168.86.49:46249")
        #expect(DeviceMonitor.parseDeviceLine("172.30.102.182:5555\toffline")?.state == "offline")
    }

    @Test func legacySpaceSeparatedLineStillParses() {
        let parsed = DeviceMonitor.parseDeviceLine("R5CT215F4QK device")
        #expect(parsed?.serial == "R5CT215F4QK")
        #expect(parsed?.state == "device")
    }

    @Test func headerAndGarbageAreSkipped() {
        #expect(DeviceMonitor.parseDeviceLine("List of devices attached") == nil)
        #expect(DeviceMonitor.parseDeviceLine("* daemon not running; starting now") == nil)
        #expect(DeviceMonitor.parseDeviceLine("") == nil)
        #expect(DeviceMonitor.parseDeviceLine("adb server version (41) doesn't match") == nil)
    }
}
