import Testing
@testable import RelayConsole

struct IdeviceParsingTests {
    // MARK: - idevice_id -l

    @Test func parseDeviceIdsList() {
        let sample = """
        00008101-001A2B3C4D5E6F70
        00008110-0011223344556677
        """
        let ids = IdeviceClient.parseDeviceIds(sample)
        #expect(ids.count == 2)
        #expect(ids[0] == "00008101-001A2B3C4D5E6F70")
    }

    @Test func parseDeviceIdsSkipsErrorAndShort() {
        let sample = """
        ERROR: No device found

        abc
        """
        #expect(IdeviceClient.parseDeviceIds(sample).isEmpty)
    }

    // MARK: - ideviceinfo

    @Test func parseInfoCoreFields() {
        let sample = """
        DeviceName: iPhone 15
        ProductType: iPhone15,2
        ProductVersion: 18.1
        BatteryCurrentCapacity: 84
        BatteryIsCharging: false
        """
        let info = IdeviceClient.parseInfo(sample)
        #expect(info["DeviceName"] == "iPhone 15")
        #expect(info["ProductType"] == "iPhone15,2")
        #expect(info["ProductVersion"] == "18.1")
        #expect(info["BatteryCurrentCapacity"] == "84")
        #expect(IdeviceClient.parseBool(info["BatteryIsCharging"]) == false)
    }

    @Test func parseInfoIgnoresMissingColon() {
        let sample = """
        no colon line
        Key: value
        """
        let info = IdeviceClient.parseInfo(sample)
        #expect(info.count == 1)
        #expect(info["Key"] == "value")
    }

    @Test func parseBoolVariants() {
        #expect(IdeviceClient.parseBool("true") == true)
        #expect(IdeviceClient.parseBool("YES") == true)
        #expect(IdeviceClient.parseBool("1") == true)
        #expect(IdeviceClient.parseBool("false") == false)
        #expect(IdeviceClient.parseBool("NO") == false)
        #expect(IdeviceClient.parseBool("0") == false)
        #expect(IdeviceClient.parseBool(nil) == nil)
        #expect(IdeviceClient.parseBool("maybe") == nil)
    }

    // MARK: - snapshot

    @Test func snapshotBatteryAndIdentity() {
        let info = [
            "DeviceName": "iPad",
            "ProductType": "iPad14,1",
            "ProductVersion": "17.4",
            "BatteryCurrentCapacity": "62",
            "BatteryIsCharging": "true"
        ]
        let snap = IdeviceClient.snapshot(udid: "00008101-001A2B3C4D5E6F70", info: info)
        #expect(snap.isOnline)
        #expect(snap.displayName == "iPad")
        #expect(snap.batteryLevel == 62)
        #expect(snap.isCharging == true)
        #expect(snap.productType == "iPad14,1")
        #expect(snap.storageTotalGB == nil)
    }

    @Test func snapshotClampsBatteryLevel() {
        let snap = IdeviceClient.snapshot(udid: "x", info: ["BatteryCurrentCapacity": "150"])
        #expect(snap.batteryLevel == 100)
        let snap2 = IdeviceClient.snapshot(udid: "x", info: ["BatteryCurrentCapacity": "-5"])
        #expect(snap2.batteryLevel == 0)
    }

    @Test func snapshotStorageFromDiskDomain() {
        let info = ["DeviceName": "iPhone"]
        let disk = [
            "TotalDataCapacity": "256000000000",
            "TotalDataAvailable": "106000000000"
        ]
        let snap = IdeviceClient.snapshot(udid: "u", info: info, disk: disk)
        #expect(snap.storageTotalGB != nil)
        #expect(snap.storageUsedGB != nil)
        if let total = snap.storageTotalGB, let used = snap.storageUsedGB {
            #expect(abs(total - 256.0) < 0.01)
            // used = 256 - 106 = 150.0
            #expect(abs(used - 150.0) < 0.01)
        }
    }

    @Test func snapshotThermalAndHealth() {
        let info = [
            "ThermalState": "Fair",
            "BatteryHealthPercent": "91",
            "BatteryCycleCount": "312"
        ]
        let snap = IdeviceClient.snapshot(udid: "u", info: info)
        #expect(snap.thermalState == "fair")
        #expect(snap.batteryHealthPct == 91)
        #expect(snap.cycleCount == 312)
    }

    @Test func snapshotDisplayNameFallback() {
        let bare = IdeviceClient.snapshot(udid: "00008101-001A2B3C4D5E6F70", info: [:])
        #expect(bare.displayName.hasSuffix("6F70"))
        #expect(bare.displayName.hasPrefix("…"))
    }

    @Test func shortUdidMasksMiddle() {
        #expect(IdeviceClient.shortUdid("00008101-001A2B3C4D5E6F70") == "…6F70")
        #expect(IdeviceClient.shortUdid("ab") == "ab")
    }

    @Test func bytesToGBCalculates() {
        #expect(abs(IdeviceClient.bytesToGB(1_000_000_000) - 1.0) < 0.001)
        #expect(IdeviceClient.bytesToGB(0) == 0)
    }
}
