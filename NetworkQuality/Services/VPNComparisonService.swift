import Foundation
import Network
import SystemConfiguration

// MARK: - VPN Status Detection

enum VPNStatus {
    case connected(name: String?)
    case disconnected
    case unknown

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .connected(let name):
            return name ?? "VPN Connected"
        case .disconnected:
            return "No VPN"
        case .unknown:
            return "Unknown"
        }
    }
}

struct VPNComparisonResult: Identifiable {
    let id = UUID()
    let timestamp: Date

    // VPN Off results
    let withoutVPN: SpeedTestSnapshot?

    // VPN On results
    let withVPN: SpeedTestSnapshot?

    // Analysis
    var downloadDifferencePercent: Double? {
        guard let off = withoutVPN?.downloadMbps, let on = withVPN?.downloadMbps, off > 0 else {
            return nil
        }
        return ((on - off) / off) * 100
    }

    var uploadDifferencePercent: Double? {
        guard let off = withoutVPN?.uploadMbps, let on = withVPN?.uploadMbps, off > 0 else {
            return nil
        }
        return ((on - off) / off) * 100
    }

    var latencyDifference: Double? {
        guard let off = withoutVPN?.latencyMs, let on = withVPN?.latencyMs else {
            return nil
        }
        return on - off
    }

    var assessment: ThrottlingAssessment {
        guard let dlDiff = downloadDifferencePercent else {
            return .inconclusive
        }

        // If VPN is faster by more than 10%, possible ISP throttling
        if dlDiff > 10 {
            return .likelyThrottling(improvement: dlDiff)
        }
        // If VPN is slower by less than 20%, normal VPN overhead
        else if dlDiff > -20 {
            return .normalOverhead
        }
        // If VPN is much slower, VPN itself may be slow
        else {
            return .vpnBottleneck
        }
    }
}

struct SpeedTestSnapshot: Codable {
    let downloadMbps: Double
    let uploadMbps: Double
    let latencyMs: Double?
    let responsiveness: Int?
    let vpnStatus: String
    let timestamp: Date

    init(from result: NetworkQualityResult, vpnStatus: VPNStatus) {
        self.downloadMbps = result.downloadSpeedMbps
        self.uploadMbps = result.uploadSpeedMbps
        self.latencyMs = result.baseRtt
        self.responsiveness = result.responsivenessValue
        self.vpnStatus = vpnStatus.displayName
        self.timestamp = Date()
    }
}

enum ThrottlingAssessment {
    case likelyThrottling(improvement: Double)
    case normalOverhead
    case vpnBottleneck
    case inconclusive

    var title: String {
        switch self {
        case .likelyThrottling(let improvement):
            return String(format: "Possible ISP Throttling Detected (+%.0f%% with VPN)", improvement)
        case .normalOverhead:
            return "No Throttling Detected"
        case .vpnBottleneck:
            return "VPN is Limiting Speed"
        case .inconclusive:
            return "Results Inconclusive"
        }
    }

    var description: String {
        switch self {
        case .likelyThrottling:
            return "Your ISP may be throttling your connection. Speeds improved significantly when using a VPN, which masks your traffic from your ISP."
        case .normalOverhead:
            return "Your ISP does not appear to be throttling your connection. The slight speed reduction with VPN is normal overhead."
        case .vpnBottleneck:
            return "Your VPN connection is significantly slower than your direct connection. Consider trying a different VPN server or provider."
        case .inconclusive:
            return "Unable to determine throttling status. Try running the comparison again."
        }
    }

    var icon: String {
        switch self {
        case .likelyThrottling:
            return "exclamationmark.triangle.fill"
        case .normalOverhead:
            return "checkmark.circle.fill"
        case .vpnBottleneck:
            return "tortoise.fill"
        case .inconclusive:
            return "questionmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .likelyThrottling:
            return "orange"
        case .normalOverhead:
            return "green"
        case .vpnBottleneck:
            return "red"
        case .inconclusive:
            return "gray"
        }
    }
}

// MARK: - VPN Comparison Service

@MainActor
class VPNComparisonService: ObservableObject {
    @Published var currentVPNStatus: VPNStatus = .unknown
    @Published var isRunning = false
    @Published var progress: String = ""
    @Published var currentPhase: ComparisonPhase = .idle
    @Published var lastResult: VPNComparisonResult?

    @Published var withoutVPNResult: SpeedTestSnapshot?
    @Published var withVPNResult: SpeedTestSnapshot?

    private let networkService = NetworkQualityService()

    enum ComparisonPhase: String {
        case idle = "Ready"
        case detectingVPN = "Detecting VPN status..."
        case testingWithoutVPN = "Testing without VPN..."
        case waitingForVPN = "Waiting for VPN connection..."
        case testingWithVPN = "Testing with VPN..."
        case analyzing = "Analyzing results..."
        case complete = "Complete"
        case error = "Error"
    }

    init() {
        updateVPNStatus()
    }

    // MARK: - VPN Detection

    func updateVPNStatus() {
        currentVPNStatus = detectVPNConnection()
    }

    private func detectVPNConnection() -> VPNStatus {
        // Check for VPN interfaces with active IP addresses
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return .unknown }
        defer { freeifaddrs(ifaddr) }

        var vpnInterfacesWithIP: Set<String> = []
        var isTailscale = false
        var current = ifaddr

        while let addr = current {
            let name = String(cString: addr.pointee.ifa_name)
            let family = addr.pointee.ifa_addr?.pointee.sa_family

            // Common VPN interface prefixes
            let isVPNInterface = name.hasPrefix("utun") || name.hasPrefix("ppp") ||
                                 name.hasPrefix("ipsec") || name.hasPrefix("tun") ||
                                 name.hasPrefix("tap")

            // Only count VPN interfaces that have an actual IP address (IPv4)
            // This ensures we don't detect disconnected VPN interfaces
            if isVPNInterface && family == UInt8(AF_INET) {
                // Get the IP address to check for Tailscale's CGNAT range (100.x.x.x)
                if let sockaddr = addr.pointee.ifa_addr {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(sockaddr, socklen_t(sockaddr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ipAddress = String(cString: hostname)

                        // Tailscale uses 100.x.x.x (CGNAT range)
                        if ipAddress.hasPrefix("100.") {
                            isTailscale = true
                        }

                        vpnInterfacesWithIP.insert(name)
                    }
                }
            }

            current = addr.pointee.ifa_next
        }

        if vpnInterfacesWithIP.isEmpty {
            return .disconnected
        }

        // Determine VPN name
        if isTailscale {
            return .connected(name: "Tailscale")
        }

        // Try to get VPN name from System Preferences for traditional VPNs
        let vpnName = getActiveVPNName()
        return .connected(name: vpnName)
    }

    private func getActiveVPNName() -> String? {
        // Check network preferences for VPN configuration name
        guard let prefs = SCPreferencesCreate(nil, "NetworkQuality" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
            return nil
        }

        for service in services {
            if let name = SCNetworkServiceGetName(service),
               let interface = SCNetworkServiceGetInterface(service),
               let type = SCNetworkInterfaceGetInterfaceType(interface) {

                let typeStr = type as String
                if typeStr == "PPP" || typeStr == "VPN" || typeStr == "IPSec" {
                    return name as String
                }
            }
        }

        return nil
    }

    // MARK: - Run Comparison

    func runComparison() async {
        guard !isRunning else { return }

        isRunning = true
        withoutVPNResult = nil
        withVPNResult = nil
        lastResult = nil

        // Phase 1: Detect current VPN status
        currentPhase = .detectingVPN
        progress = "Checking VPN status..."
        updateVPNStatus()

        let initialVPNStatus = currentVPNStatus

        // Determine test order based on current VPN state
        if initialVPNStatus.isConnected {
            // VPN is on - test with VPN first, then ask user to disconnect
            await testWithVPN()
            await testWithoutVPN()
        } else {
            // VPN is off - test without VPN first, then ask user to connect
            await testWithoutVPN()
            await testWithVPN()
        }

        // Analyze results
        currentPhase = .analyzing
        progress = "Analyzing comparison..."

        lastResult = VPNComparisonResult(
            timestamp: Date(),
            withoutVPN: withoutVPNResult,
            withVPN: withVPNResult
        )

        currentPhase = .complete
        progress = "Comparison complete"
        isRunning = false
    }

    private func testWithoutVPN() async {
        // Check if VPN is connected
        updateVPNStatus()

        if currentVPNStatus.isConnected {
            currentPhase = .waitingForVPN
            progress = "Please disconnect your VPN to continue..."

            // Wait for VPN to disconnect (up to 60 seconds)
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                updateVPNStatus()
                if !currentVPNStatus.isConnected {
                    break
                }
            }

            // Give network time to stabilize after VPN disconnect
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        currentPhase = .testingWithoutVPN
        progress = "Running speed test without VPN..."

        // Run the test
        if let result = await runSpeedTest() {
            withoutVPNResult = SpeedTestSnapshot(from: result, vpnStatus: .disconnected)
        }
    }

    private func testWithVPN() async {
        // Check if VPN is disconnected
        updateVPNStatus()

        if !currentVPNStatus.isConnected {
            currentPhase = .waitingForVPN
            progress = "Please connect your VPN to continue..."

            // Wait for VPN to connect (up to 60 seconds)
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                updateVPNStatus()
                if currentVPNStatus.isConnected {
                    break
                }
            }

            // Give network time to stabilize after VPN connect
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        currentPhase = .testingWithVPN
        progress = "Running speed test with VPN..."

        // Run the test
        updateVPNStatus()
        if let result = await runSpeedTest() {
            withVPNResult = SpeedTestSnapshot(from: result, vpnStatus: currentVPNStatus)
        }
    }

    private func runSpeedTest() async -> NetworkQualityResult? {
        // Run networkQuality test
        var config = TestConfiguration()
        config.mode = .parallel

        do {
            let result = try await networkService.runTest(config: config)
            return result
        } catch {
            return nil
        }
    }

    func cancel() {
        networkService.cancelTest()
        isRunning = false
        currentPhase = .idle
        progress = ""
    }
}
