import Foundation
import Network
import SystemConfiguration

// MARK: - VPN Status Detection

enum VPNStatus: Sendable {
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

struct VPNComparisonResult: Identifiable, Sendable {
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

struct SpeedTestSnapshot: Codable, Sendable {
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

enum ThrottlingAssessment: Sendable {
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

// MARK: - VPN Interface Detection

/// Detects VPN interfaces supporting both IPv4 and IPv6
struct VPNInterfaceDetector {
    /// Common VPN interface prefixes on macOS
    static let vpnInterfacePrefixes = ["utun", "ppp", "ipsec", "tun", "tap", "gif", "stf"]

    /// Tailscale CGNAT range: 100.64.0.0/10 (100.64.0.0 - 100.127.255.255)
    static func isTailscaleIPv4(_ ip: String) -> Bool {
        guard ip.hasPrefix("100.") else { return false }
        let parts = ip.split(separator: ".")
        guard parts.count >= 2, let second = Int(parts[1]) else { return false }
        return second >= 64 && second <= 127
    }

    /// Tailscale IPv6 range: fd7a:115c:a1e0::/48
    static func isTailscaleIPv6(_ ip: String) -> Bool {
        let ipLower = ip.lowercased()
        return ipLower.hasPrefix("fd7a:115c:a1e0:")
    }

    /// WireGuard typically uses these IPv6 prefixes (ULA range)
    static func isWireGuardIPv6(_ ip: String) -> Bool {
        let ipLower = ip.lowercased()
        // WireGuard often uses fd::/8 unique local addresses
        return ipLower.hasPrefix("fd") && !isTailscaleIPv6(ip)
    }

    /// Check if interface name is a VPN interface
    static func isVPNInterface(_ name: String) -> Bool {
        for prefix in vpnInterfacePrefixes {
            if name.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    /// Detect all active VPN interfaces with their IP addresses
    static func detectVPNInterfaces() -> [(interface: String, ipv4: String?, ipv6: String?, vpnType: VPNType?)] {
        var interfaces: [String: (ipv4: String?, ipv6: String?, vpnType: VPNType?)] = [:]

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var current = ifaddr
        while let addr = current {
            let name = String(cString: addr.pointee.ifa_name)
            let family = addr.pointee.ifa_addr?.pointee.sa_family

            if isVPNInterface(name) {
                // Initialize if not exists
                if interfaces[name] == nil {
                    interfaces[name] = (nil, nil, nil)
                }

                // Get IP address
                if let sockaddr = addr.pointee.ifa_addr {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                    if family == UInt8(AF_INET) {
                        // IPv4
                        if getnameinfo(sockaddr, socklen_t(MemoryLayout<sockaddr_in>.size),
                                       &hostname, socklen_t(hostname.count),
                                       nil, 0, NI_NUMERICHOST) == 0 {
                            let ipAddress = String(cString: hostname)
                            interfaces[name]?.ipv4 = ipAddress

                            // Detect VPN type from IPv4
                            if isTailscaleIPv4(ipAddress) {
                                interfaces[name]?.vpnType = .tailscale
                            }
                        }
                    } else if family == UInt8(AF_INET6) {
                        // IPv6
                        if getnameinfo(sockaddr, socklen_t(MemoryLayout<sockaddr_in6>.size),
                                       &hostname, socklen_t(hostname.count),
                                       nil, 0, NI_NUMERICHOST) == 0 {
                            var ipAddress = String(cString: hostname)

                            // Remove scope ID if present (e.g., "fe80::1%utun0")
                            if let percentIndex = ipAddress.firstIndex(of: "%") {
                                ipAddress = String(ipAddress[..<percentIndex])
                            }

                            // Skip link-local addresses for VPN detection
                            if !ipAddress.lowercased().hasPrefix("fe80:") {
                                interfaces[name]?.ipv6 = ipAddress

                                // Detect VPN type from IPv6
                                if isTailscaleIPv6(ipAddress) {
                                    interfaces[name]?.vpnType = .tailscale
                                } else if isWireGuardIPv6(ipAddress) {
                                    interfaces[name]?.vpnType = .wireGuard
                                }
                            }
                        }
                    }
                }
            }

            current = addr.pointee.ifa_next
        }

        // Filter to only interfaces with at least one IP address
        return interfaces.compactMap { name, info in
            guard info.ipv4 != nil || info.ipv6 != nil else { return nil }
            return (interface: name, ipv4: info.ipv4, ipv6: info.ipv6, vpnType: info.vpnType)
        }
    }

    enum VPNType: String {
        case tailscale = "Tailscale"
        case wireGuard = "WireGuard"
        case openVPN = "OpenVPN"
        case ipsec = "IPSec"
        case other = "VPN"
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

    // Live speed tracking during tests
    @Published var currentDownloadSpeed: Double = 0
    @Published var currentUploadSpeed: Double = 0

    // Detected VPN interfaces
    @Published var detectedInterfaces: [(interface: String, ipv4: String?, ipv6: String?, vpnType: VPNInterfaceDetector.VPNType?)] = []

    private let networkService = NetworkQualityService()
    private var speedObservationTask: Task<Void, Never>?
    private var runningTask: Task<Void, Never>?

    enum ComparisonPhase: String, Sendable {
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
        // Detect VPN interfaces (supports both IPv4 and IPv6)
        detectedInterfaces = VPNInterfaceDetector.detectVPNInterfaces()

        NetworkQualityLogger.vpn.debug("Detected \(self.detectedInterfaces.count) VPN interface(s)")

        for iface in detectedInterfaces {
            NetworkQualityLogger.vpn.debug("  \(iface.interface): IPv4=\(iface.ipv4 ?? "none"), IPv6=\(iface.ipv6 ?? "none"), Type=\(iface.vpnType?.rawValue ?? "unknown")")
        }

        if detectedInterfaces.isEmpty {
            return .disconnected
        }

        // Determine VPN name
        // Priority: Tailscale > WireGuard > System VPN name > Generic
        if let tailscale = detectedInterfaces.first(where: { $0.vpnType == .tailscale }) {
            NetworkQualityLogger.vpn.info("Tailscale VPN detected on \(tailscale.interface)")
            return .connected(name: "Tailscale")
        }

        if let wireGuard = detectedInterfaces.first(where: { $0.vpnType == .wireGuard }) {
            NetworkQualityLogger.vpn.info("WireGuard VPN detected on \(wireGuard.interface)")
            return .connected(name: "WireGuard")
        }

        // Try to get VPN name from System Preferences
        if let systemVPNName = getActiveVPNName() {
            NetworkQualityLogger.vpn.info("System VPN detected: \(systemVPNName)")
            return .connected(name: systemVPNName)
        }

        // Generic VPN detected
        let interfaceNames = detectedInterfaces.map { $0.interface }.joined(separator: ", ")
        NetworkQualityLogger.vpn.info("Generic VPN detected on interface(s): \(interfaceNames)")
        return .connected(name: nil)
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

            if Task.isCancelled {
                cleanup()
                return
            }

            await testWithoutVPN()
        } else {
            // VPN is off - test without VPN first, then ask user to connect
            await testWithoutVPN()

            if Task.isCancelled {
                cleanup()
                return
            }

            await testWithVPN()
        }

        if Task.isCancelled {
            cleanup()
            return
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
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: NetworkQualityConstants.secondInNanoseconds)
                updateVPNStatus()
                if !currentVPNStatus.isConnected {
                    break
                }
            }

            // Give network time to stabilize after VPN disconnect
            try? await Task.sleep(nanoseconds: 2 * NetworkQualityConstants.secondInNanoseconds)
        }

        if Task.isCancelled { return }

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
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: NetworkQualityConstants.secondInNanoseconds)
                updateVPNStatus()
                if currentVPNStatus.isConnected {
                    break
                }
            }

            // Give network time to stabilize after VPN connect
            try? await Task.sleep(nanoseconds: 2 * NetworkQualityConstants.secondInNanoseconds)
        }

        if Task.isCancelled { return }

        currentPhase = .testingWithVPN
        progress = "Running speed test with VPN..."

        // Run the test
        updateVPNStatus()
        if let result = await runSpeedTest() {
            withVPNResult = SpeedTestSnapshot(from: result, vpnStatus: currentVPNStatus)
        }
    }

    private func runSpeedTest() async -> NetworkQualityResult? {
        // Reset speeds
        currentDownloadSpeed = 0
        currentUploadSpeed = 0

        // Start observing speed updates from the network service
        speedObservationTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await MainActor.run {
                    self.currentDownloadSpeed = self.networkService.currentDownloadSpeed
                    self.currentUploadSpeed = self.networkService.currentUploadSpeed
                }
                try? await Task.sleep(nanoseconds: NetworkQualityConstants.progressPollInterval)
            }
        }

        // Run networkQuality test
        var config = TestConfiguration()
        config.mode = .parallel

        defer {
            speedObservationTask?.cancel()
            speedObservationTask = nil
            currentDownloadSpeed = 0
            currentUploadSpeed = 0
        }

        do {
            let result = try await networkService.runTest(config: config)
            return result
        } catch {
            NetworkQualityLogger.vpn.error("Speed test failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanup() {
        speedObservationTask?.cancel()
        speedObservationTask = nil
        runningTask?.cancel()
        runningTask = nil
        currentDownloadSpeed = 0
        currentUploadSpeed = 0
        isRunning = false
        currentPhase = .idle
        progress = ""
    }

    func cancel() {
        networkService.cancelTest()
        cleanup()
    }
}
