import Foundation
import CoreWLAN
import SystemConfiguration
import Network
import CoreLocation

/// Metadata about the network connection at the time of a test
struct NetworkMetadata: Codable, Equatable {
    let connectionType: ConnectionType
    let interfaceName: String
    let localIPAddress: String?      // IPv4 address of the active interface
    let localIPv6Address: String?    // Global/ULA IPv6 address (link-local excluded)
    let subnetMask: String?          // IPv4 subnet mask of the active interface
    let gatewayIPAddress: String?    // Default route (router) IP
    let mtu: Int?                    // Link MTU in bytes
    let dnsServers: [String]?        // Configured DNS resolver addresses
    let vpnActive: Bool?             // A VPN interface is active
    let vpnName: String?             // Best-guess VPN name (Tailscale, WireGuard, system service…)
    let proxyActive: Bool?           // A system proxy is configured
    let proxyDescription: String?    // Short summary of the active proxy

    // WiFi-specific
    let wifiSSID: String?
    let wifiBSSID: String?
    let wifiRSSI: Int?         // Signal strength in dBm
    let wifiNoise: Int?        // Noise in dBm
    let wifiChannel: Int?
    let wifiBand: WiFiBand?
    let wifiTxRate: Double?    // Link speed in Mbps
    let wifiSecurity: WiFiSecurity?

    /// Keys that are encoded/decoded. Identifying network fields are deliberately
    /// omitted so they are never written to disk (history) or to exports (JSON).
    /// They remain available in-memory for live/current-session display only.
    /// Omitted for privacy: localIPAddress, localIPv6Address, gatewayIPAddress,
    /// dnsServers, wifiSSID, wifiBSSID, proxyDescription.
    enum CodingKeys: String, CodingKey {
        case connectionType
        case interfaceName
        case subnetMask
        case mtu
        case vpnActive
        case vpnName
        case proxyActive
        case wifiRSSI
        case wifiNoise
        case wifiChannel
        case wifiBand
        case wifiTxRate
        case wifiSecurity
    }

    enum ConnectionType: String, Codable {
        case wifi = "WiFi"
        case ethernet = "Ethernet"
        case cellular = "Cellular"
        case other = "Other"

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .ethernet: return "cable.connector"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .other: return "network"
            }
        }
    }

    enum WiFiBand: String, Codable {
        case band2_4GHz = "2.4 GHz"
        case band5GHz = "5 GHz"
        case band6GHz = "6 GHz"
        case unknown = "Unknown"
    }

    enum WiFiSecurity: String, Codable {
        case none = "None"
        case wep = "WEP"
        case wpaPersonal = "WPA Personal"
        case wpaEnterprise = "WPA Enterprise"
        case wpa2Personal = "WPA2 Personal"
        case wpa2Enterprise = "WPA2 Enterprise"
        case wpa3Personal = "WPA3 Personal"
        case wpa3Enterprise = "WPA3 Enterprise"
        case unknown = "Unknown"
    }

    /// Signal quality description based on RSSI
    var signalQuality: String? {
        guard let rssi = wifiRSSI else { return nil }
        switch rssi {
        case -50...0: return "Excellent"
        case -60..<(-50): return "Good"
        case -70..<(-60): return "Fair"
        case -80..<(-70): return "Weak"
        default: return "Poor"
        }
    }

    /// Signal quality color
    var signalColor: String {
        guard let rssi = wifiRSSI else { return "secondary" }
        switch rssi {
        case -50...0: return "green"
        case -60..<(-50): return "blue"
        case -70..<(-60): return "orange"
        default: return "red"
        }
    }
}

// MARK: - Codable (privacy-aware)

extension NetworkMetadata {
    /// Decodes the persisted/exported keys and forces the omitted identifying
    /// fields to nil. Defined in an extension so the synthesized memberwise
    /// initializer (used by live capture) is preserved. `encode(to:)` is
    /// synthesized from `CodingKeys`, so the omitted fields are never written.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connectionType = try c.decode(ConnectionType.self, forKey: .connectionType)
        interfaceName = try c.decode(String.self, forKey: .interfaceName)
        subnetMask = try c.decodeIfPresent(String.self, forKey: .subnetMask)
        mtu = try c.decodeIfPresent(Int.self, forKey: .mtu)
        vpnActive = try c.decodeIfPresent(Bool.self, forKey: .vpnActive)
        vpnName = try c.decodeIfPresent(String.self, forKey: .vpnName)
        proxyActive = try c.decodeIfPresent(Bool.self, forKey: .proxyActive)
        wifiRSSI = try c.decodeIfPresent(Int.self, forKey: .wifiRSSI)
        wifiNoise = try c.decodeIfPresent(Int.self, forKey: .wifiNoise)
        wifiChannel = try c.decodeIfPresent(Int.self, forKey: .wifiChannel)
        wifiBand = try c.decodeIfPresent(WiFiBand.self, forKey: .wifiBand)
        wifiTxRate = try c.decodeIfPresent(Double.self, forKey: .wifiTxRate)
        wifiSecurity = try c.decodeIfPresent(WiFiSecurity.self, forKey: .wifiSecurity)

        // Identifying network fields are never persisted or exported.
        localIPAddress = nil
        localIPv6Address = nil
        gatewayIPAddress = nil
        dnsServers = nil
        wifiSSID = nil
        wifiBSSID = nil
        proxyDescription = nil
    }
}

/// Service to fetch current network connection information
class NetworkInfoService {

    static let shared = NetworkInfoService()

    private init() {}

    /// Fetch current network metadata
    func getCurrentMetadata() -> NetworkMetadata {
        let wifiClient = CWWiFiClient.shared()
        let wifiInterface = wifiClient.interface()

        // Determine connection type and get WiFi details if applicable
        var connectionType: NetworkMetadata.ConnectionType = .other
        var wifiSSID: String?
        var wifiBSSID: String?
        var wifiRSSI: Int?
        var wifiNoise: Int?
        var wifiChannel: Int?
        var wifiBand: NetworkMetadata.WiFiBand?
        var wifiTxRate: Double?
        var wifiSecurity: NetworkMetadata.WiFiSecurity?
        var interfaceName = "unknown"

        if let wifi = wifiInterface {
            interfaceName = wifi.interfaceName ?? "en0"

            // Check if WiFi is active (has an IP or is powered on)
            if wifi.powerOn() {
                connectionType = .wifi

                // SSID requires Location Services permission on macOS 10.15+
                wifiSSID = wifi.ssid()
                wifiBSSID = wifi.bssid()
                wifiRSSI = wifi.rssiValue()
                wifiNoise = wifi.noiseMeasurement()
                wifiTxRate = wifi.transmitRate()

                if let channel = wifi.wlanChannel() {
                    wifiChannel = channel.channelNumber

                    switch channel.channelBand {
                    case .band2GHz:
                        wifiBand = .band2_4GHz
                    case .band5GHz:
                        wifiBand = .band5GHz
                    case .band6GHz:
                        wifiBand = .band6GHz
                    case .bandUnknown:
                        wifiBand = .unknown
                    @unknown default:
                        wifiBand = .unknown
                    }
                }

                wifiSecurity = mapSecurity(wifi.security())
            }
        }

        // Check for Ethernet by looking at interface names
        let ipAddresses = getIPAddresses()
        if connectionType == .other {
            // Check common Ethernet interface names
            for (iface, _) in ipAddresses {
                if iface.hasPrefix("en") && iface != "en0" {
                    // en1, en2, etc. are typically Ethernet on Macs with WiFi
                    connectionType = .ethernet
                    interfaceName = iface
                    break
                }
            }
        }

        // Get local IPs for the active interface, falling back to any interface
        let activeIPs = ipAddresses[interfaceName]
        let localIP = activeIPs?.ipv4 ?? ipAddresses.values.compactMap { $0.ipv4 }.first
        let localIPv6 = activeIPs?.ipv6 ?? ipAddresses.values.compactMap { $0.ipv6 }.first
        let subnetMask = activeIPs?.ipv4Netmask
        let mtu = activeIPs?.mtu ?? ipAddresses.values.compactMap { $0.mtu }.first

        let (gateway, dnsServers) = getGatewayAndDNS()

        let vpn = VPNInterfaceDetector.currentVPN()
        let proxy = SystemProxyDetector.currentProxy()

        return NetworkMetadata(
            connectionType: connectionType,
            interfaceName: interfaceName,
            localIPAddress: localIP,
            localIPv6Address: localIPv6,
            subnetMask: subnetMask,
            gatewayIPAddress: gateway,
            mtu: mtu,
            dnsServers: dnsServers,
            vpnActive: vpn.active,
            vpnName: vpn.name,
            proxyActive: proxy.active,
            proxyDescription: proxy.description,
            wifiSSID: wifiSSID,
            wifiBSSID: wifiBSSID,
            wifiRSSI: wifiRSSI,
            wifiNoise: wifiNoise,
            wifiChannel: wifiChannel,
            wifiBand: wifiBand,
            wifiTxRate: wifiTxRate,
            wifiSecurity: wifiSecurity
        )
    }

    /// IPv4 and IPv6 addresses for a single interface
    private struct InterfaceAddresses {
        var ipv4: String?
        var ipv6: String?
        var ipv4Netmask: String?
        var mtu: Int?
    }

    /// Get IPv4 and IPv6 addresses for all interfaces
    private func getIPAddresses() -> [String: InterfaceAddresses] {
        var addresses: [String: InterfaceAddresses] = [:]

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return addresses
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr!.pointee
            let family = interface.ifa_addr.pointee.sa_family

            // AF_LINK entries carry per-interface link data including the MTU.
            if family == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)
                if let data = interface.ifa_data {
                    let linkData = data.assumingMemoryBound(to: if_data.self).pointee
                    addresses[name, default: InterfaceAddresses()].mtu = Int(linkData.ifi_mtu)
                }
                continue
            }

            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var addr = interface.ifa_addr.pointee

            getnameinfo(
                &addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            var ip = String(cString: hostname)

            if family == UInt8(AF_INET) {
                // Skip IPv4 loopback
                guard !ip.hasPrefix("127.") else { continue }
                addresses[name, default: InterfaceAddresses()].ipv4 = ip

                // Subnet mask comes from the matching ifa_netmask sockaddr
                if let netmaskPtr = interface.ifa_netmask {
                    var nmHost = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    var nmAddr = netmaskPtr.pointee
                    getnameinfo(
                        &nmAddr,
                        socklen_t(netmaskPtr.pointee.sa_len),
                        &nmHost,
                        socklen_t(nmHost.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    addresses[name, default: InterfaceAddresses()].ipv4Netmask = String(cString: nmHost)
                }
            } else {
                // IPv6: getnameinfo appends a "%en0" scope id for link-local; strip it
                if let percent = ip.firstIndex(of: "%") {
                    ip = String(ip[..<percent])
                }
                // Skip special-use addresses that begin with "::" (unspecified "::",
                // loopback "::1", IPv4-mapped "::ffff:") and link-local (fe80::/10);
                // keep only real global/ULA addresses.
                let lower = ip.lowercased()
                guard !lower.hasPrefix("::"),
                      !lower.hasPrefix("fe8"), !lower.hasPrefix("fe9"),
                      !lower.hasPrefix("fea"), !lower.hasPrefix("feb") else { continue }
                // Prefer the first non-temporary-looking address we see for the interface
                if addresses[name, default: InterfaceAddresses()].ipv6 == nil {
                    addresses[name, default: InterfaceAddresses()].ipv6 = ip
                }
            }
        }

        return addresses
    }

    /// Read the default gateway and configured DNS resolvers from the system
    /// configuration dynamic store (no subprocess required).
    private func getGatewayAndDNS() -> (gateway: String?, dns: [String]?) {
        guard let store = SCDynamicStoreCreate(nil, "NetworkQuality" as CFString, nil, nil) else {
            return (nil, nil)
        }

        var gateway: String?
        if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            gateway = ipv4["Router"] as? String
        }
        // Fall back to the IPv6 default route if there's no IPv4 router
        if gateway == nil,
           let ipv6 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any] {
            gateway = ipv6["Router"] as? String
        }

        var dns: [String]?
        if let dnsDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = dnsDict["ServerAddresses"] as? [String], !servers.isEmpty {
            dns = servers
        }

        return (gateway, dns)
    }

    private func mapSecurity(_ security: CWSecurity) -> NetworkMetadata.WiFiSecurity {
        switch security {
        case .none:
            return .none
        case .WEP:
            return .wep
        case .wpaPersonal:
            return .wpaPersonal
        case .wpaEnterprise:
            return .wpaEnterprise
        case .wpa2Personal:
            return .wpa2Personal
        case .wpa2Enterprise:
            return .wpa2Enterprise
        case .wpa3Personal:
            return .wpa3Personal
        case .wpa3Enterprise:
            return .wpa3Enterprise
        case .wpaPersonalMixed:
            return .wpaPersonal
        case .wpaEnterpriseMixed:
            return .wpaEnterprise
        case .wpa3Transition:
            return .wpa3Personal
        case .personal:
            return .wpa2Personal
        case .enterprise:
            return .wpa2Enterprise
        case .dynamicWEP:
            return .wep
        case .OWE:
            return .unknown
        case .oweTransition:
            return .unknown
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

/// Manages location permission for SSID access
class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionManager()

    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        updateAuthorizationStatus()
    }

    private func updateAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
        isAuthorized = authorizationStatus == .authorizedAlways || authorizationStatus == .authorized
    }

    /// Request location permission (shows system dialog with custom message from Info.plist)
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.updateAuthorizationStatus()
        }
    }

    /// Check if SSID access is available (permission granted)
    var canAccessSSID: Bool {
        return isAuthorized
    }

    /// Status message for UI
    var statusMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Location permission not requested"
        case .restricted:
            return "Location access restricted"
        case .denied:
            return "Location access denied - enable in System Settings"
        case .authorizedAlways, .authorized:
            return "Location access granted"
        @unknown default:
            return "Unknown status"
        }
    }
}
