import Testing
@testable import RelayConsole

struct WifiAdbTests {
    // MARK: - parseWlanIp

    @Test func parseWlanIpFromIpRouteGet() {
        let sample = """
        1.1.1.1 via 192.168.0.1 dev wlan0 src 192.168.0.5 uid 1000
            cache
        """
        #expect(WifiAdbLogic.parseWlanIp(from: sample) == "192.168.0.5")
    }

    @Test func parseWlanIpFromIfconfig() {
        let sample = """
        wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 10.0.0.42  netmask 255.255.255.0  broadcast 10.0.0.255
            ether 02:00:00:00:00:01  (Ethernet)
        """
        #expect(WifiAdbLogic.parseWlanIp(from: sample) == "10.0.0.42")
    }

    @Test func parseWlanIpSkipsLoopback() {
        let sample = """
        lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
            inet 127.0.0.1  netmask 255.0.0.0
        wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 192.168.1.7  netmask 255.255.255.0
        """
        #expect(WifiAdbLogic.parseWlanIp(from: sample) == "192.168.1.7")
    }

    @Test func parseWlanIpNilWhenEmpty() {
        #expect(WifiAdbLogic.parseWlanIp(from: "") == nil)
        #expect(WifiAdbLogic.parseWlanIp(from: "no addresses") == nil)
    }

    // MARK: - validateEndpoint

    @Test func validateEndpointAcceptsHostPort() {
        #expect(WifiAdbLogic.validateEndpoint("192.168.0.5:5555") == nil)
        #expect(WifiAdbLogic.validateEndpoint(" 10.0.0.1:5037 ") == nil)
    }

    @Test func validateEndpointRejectsBadInput() {
        #expect(WifiAdbLogic.validateEndpoint("") == "wifi.error.endpoint.empty")
        #expect(WifiAdbLogic.validateEndpoint("999.1.1.1:5555") == "wifi.error.endpoint.format")
        #expect(WifiAdbLogic.validateEndpoint("192.168.0.5") == "wifi.error.endpoint.format")
        #expect(WifiAdbLogic.validateEndpoint("192.168.0.5:0") == "wifi.error.endpoint.format")
        #expect(WifiAdbLogic.validateEndpoint("example.com:5555") == "wifi.error.endpoint.format")
        #expect(WifiAdbLogic.validateEndpoint("192.168.0.5:abc") == "wifi.error.endpoint.format")
    }

    // MARK: - args

    @Test func tcpipArgsShape() {
        let a = WifiAdbLogic.tcpipArgs(serial: "ABC123", port: 5555)
        #expect(a == ["-s", "ABC123", "tcpip", "5555"])
    }

    @Test func connectAndDisconnectArgs() {
        #expect(WifiAdbLogic.connectArgs(endpoint: " 10.0.0.2:5555 ") == ["connect", "10.0.0.2:5555"])
        #expect(WifiAdbLogic.disconnectArgs(endpoint: "10.0.0.2:5555") == ["disconnect", "10.0.0.2:5555"])
    }

    @Test func defaultEndpointJoinsIpPort() {
        #expect(WifiAdbLogic.defaultEndpoint(ip: "192.168.0.9") == "192.168.0.9:5555")
        #expect(WifiAdbLogic.defaultEndpoint(ip: "192.168.0.9", port: 5556) == "192.168.0.9:5556")
    }

    @Test func isIPv4ChecksOctets() {
        #expect(WifiAdbLogic.isIPv4("0.0.0.0"))
        #expect(WifiAdbLogic.isIPv4("255.255.255.255"))
        #expect(!WifiAdbLogic.isIPv4("256.0.0.1"))
        #expect(!WifiAdbLogic.isIPv4("1.2.3"))
        #expect(!WifiAdbLogic.isIPv4("1.2.3.4.5"))
        #expect(!WifiAdbLogic.isIPv4("a.b.c.d"))
    }
}
