import Foundation
import CoreWLAN
import SystemConfiguration
import Network
import CoreLocation

/// Metadata about the network connection at the time of a test
struct NetworkMetadata: Codable, Equatable {
    let connectionType: ConnectionType
    let interfaceName: String
    let localIPAddress: String?

    // WiFi-specific
    let wifiSSID: String?
    let wifiBSSID: String?
    let wifiRSSI: Int?         // Signal strength in dBm
    let wifiNoise: Int?        // Noise in dBm
    let wifiChannel: Int?
    let wifiBand: WiFiBand?
    let wifiTxRate: Double?    // Link speed in Mbps
    let wifiSecurity: WiFiSecurity?

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

        // Get local IP for the active interface
        let localIP = ipAddresses[interfaceName] ?? ipAddresses.values.first

        return NetworkMetadata(
            connectionType: connectionType,
            interfaceName: interfaceName,
            localIPAddress: localIP,
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

    /// Get IP addresses for all interfaces
    private func getIPAddresses() -> [String: String] {
        var addresses: [String: String] = [:]

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

            // Only IPv4 for simplicity
            if family == UInt8(AF_INET) {
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

                let ip = String(cString: hostname)
                // Skip loopback
                if !ip.hasPrefix("127.") {
                    addresses[name] = ip
                }
            }
        }

        return addresses
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
