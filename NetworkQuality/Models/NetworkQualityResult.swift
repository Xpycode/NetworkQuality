import Foundation

struct NetworkQualityResult: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date

    // Basic metrics
    let dlThroughput: Int64?
    let ulThroughput: Int64?
    let responsiveness: Double?
    let dlResponsiveness: Double?
    let ulResponsiveness: Double?
    let baseRtt: Double?

    // Flow counts
    let dlFlows: Int?
    let ulFlows: Int?

    // Interface info
    let interfaceName: String?
    let osVersion: String?

    // Timestamps
    let startDate: String?
    let endDate: String?

    // Idle latency measurements (arrays - we'll compute averages)
    let ilH2ReqResp: [Double]?
    let ilTcpHandshake443: [Double]?
    let ilTlsHandshake: [Double]?

    // Latency under load - download (sequential mode)
    let ludForeignDlH2ReqResp: [Double]?
    let ludForeignDlTcpHandshake443: [Double]?
    let ludForeignDlTlsHandshake: [Double]?
    let ludSelfDlH2ReqResp: [Double]?

    // Latency under load - upload (sequential mode)
    let ludForeignUlH2ReqResp: [Double]?
    let ludForeignUlTcpHandshake443: [Double]?
    let ludForeignUlTlsHandshake: [Double]?
    let ludSelfUlH2ReqResp: [Double]?

    // Latency under load - combined (parallel mode)
    let ludForeignH2ReqResp: [Double]?
    let ludForeignTcpHandshake443: [Double]?
    let ludForeignTlsHandshake: [Double]?
    let ludSelfH2ReqResp: [Double]?

    // Error info
    let errorCode: Int?
    let errorDomain: String?

    enum CodingKeys: String, CodingKey {
        case dlThroughput = "dl_throughput"
        case ulThroughput = "ul_throughput"
        case responsiveness
        case dlResponsiveness = "dl_responsiveness"
        case ulResponsiveness = "ul_responsiveness"
        case baseRtt = "base_rtt"
        case dlFlows = "dl_flows"
        case ulFlows = "ul_flows"
        case interfaceName = "interface_name"
        case osVersion = "os_version"
        case startDate = "start_date"
        case endDate = "end_date"
        case ilH2ReqResp = "il_h2_req_resp"
        case ilTcpHandshake443 = "il_tcp_handshake_443"
        case ilTlsHandshake = "il_tls_handshake"
        case ludForeignH2ReqResp = "lud_foreign_h2_req_resp"
        case ludForeignTcpHandshake443 = "lud_foreign_tcp_handshake_443"
        case ludForeignTlsHandshake = "lud_foreign_tls_handshake"
        case ludSelfH2ReqResp = "lud_self_h2_req_resp"
        case ludForeignDlH2ReqResp = "lud_foreign_dl_h2_req_resp"
        case ludForeignDlTcpHandshake443 = "lud_foreign_dl_tcp_handshake_443"
        case ludForeignDlTlsHandshake = "lud_foreign_dl_tls_handshake"
        case ludSelfDlH2ReqResp = "lud_self_dl_h2_req_resp"
        case ludForeignUlH2ReqResp = "lud_foreign_ul_h2_req_resp"
        case ludForeignUlTcpHandshake443 = "lud_foreign_ul_tcp_handshake_443"
        case ludForeignUlTlsHandshake = "lud_foreign_ul_tls_handshake"
        case ludSelfUlH2ReqResp = "lud_self_ul_h2_req_resp"
        case errorCode = "error_code"
        case errorDomain = "error_domain"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        timestamp = Date()
        dlThroughput = try container.decodeIfPresent(Int64.self, forKey: .dlThroughput)
        ulThroughput = try container.decodeIfPresent(Int64.self, forKey: .ulThroughput)
        responsiveness = try container.decodeIfPresent(Double.self, forKey: .responsiveness)
        dlResponsiveness = try container.decodeIfPresent(Double.self, forKey: .dlResponsiveness)
        ulResponsiveness = try container.decodeIfPresent(Double.self, forKey: .ulResponsiveness)
        baseRtt = try container.decodeIfPresent(Double.self, forKey: .baseRtt)
        dlFlows = try container.decodeIfPresent(Int.self, forKey: .dlFlows)
        ulFlows = try container.decodeIfPresent(Int.self, forKey: .ulFlows)
        interfaceName = try container.decodeIfPresent(String.self, forKey: .interfaceName)
        osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)

        // Decode arrays for latency data
        ilH2ReqResp = try container.decodeIfPresent([Double].self, forKey: .ilH2ReqResp)
        ilTcpHandshake443 = try container.decodeIfPresent([Double].self, forKey: .ilTcpHandshake443)
        ilTlsHandshake = try container.decodeIfPresent([Double].self, forKey: .ilTlsHandshake)

        ludForeignDlH2ReqResp = try container.decodeIfPresent([Double].self, forKey: .ludForeignDlH2ReqResp)
        ludForeignDlTcpHandshake443 = try container.decodeIfPresent([Double].self, forKey: .ludForeignDlTcpHandshake443)
        ludForeignDlTlsHandshake = try container.decodeIfPresent([Double].self, forKey: .ludForeignDlTlsHandshake)
        ludSelfDlH2ReqResp = try container.decodeIfPresent([Double].self, forKey: .ludSelfDlH2ReqResp)

        ludForeignUlH2ReqResp = try container.decodeIfPresent([Double].self, forKey: .ludForeignUlH2ReqResp)
        ludForeignUlTcpHandshake443 = try container.decodeIfPresent([Double].self, forKey: .ludForeignUlTcpHandshake443)
        ludForeignUlTlsHandshake = try container.decodeIfPresent([Double].self, forKey: .ludForeignUlTlsHandshake)
        ludSelfUlH2ReqResp = try container.decodeIfPresent([Double].self, forKey: .ludSelfUlH2ReqResp)

        ludForeignH2ReqResp = try container.decodeIfPresent([Double].self, forKey: .ludForeignH2ReqResp)
        ludForeignTcpHandshake443 = try container.decodeIfPresent([Double].self, forKey: .ludForeignTcpHandshake443)
        ludForeignTlsHandshake = try container.decodeIfPresent([Double].self, forKey: .ludForeignTlsHandshake)
        ludSelfH2ReqResp = try container.decodeIfPresent([Double].self, forKey: .ludSelfH2ReqResp)

        errorCode = try container.decodeIfPresent(Int.self, forKey: .errorCode)
        errorDomain = try container.decodeIfPresent(String.self, forKey: .errorDomain)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(dlThroughput, forKey: .dlThroughput)
        try container.encodeIfPresent(ulThroughput, forKey: .ulThroughput)
        try container.encodeIfPresent(responsiveness, forKey: .responsiveness)
        try container.encodeIfPresent(dlResponsiveness, forKey: .dlResponsiveness)
        try container.encodeIfPresent(ulResponsiveness, forKey: .ulResponsiveness)
        try container.encodeIfPresent(baseRtt, forKey: .baseRtt)
    }

    // Computed properties for display
    var downloadSpeedMbps: Double {
        guard let throughput = dlThroughput else { return 0 }
        return Double(throughput) / 1_000_000.0
    }

    var uploadSpeedMbps: Double {
        guard let throughput = ulThroughput else { return 0 }
        return Double(throughput) / 1_000_000.0
    }

    var formattedDownloadSpeed: String {
        formatSpeed(dlThroughput)
    }

    var formattedUploadSpeed: String {
        formatSpeed(ulThroughput)
    }

    var responsivenessValue: Int? {
        if let r = responsiveness { return Int(r) }
        if let r = dlResponsiveness { return Int(r) }
        if let r = ulResponsiveness { return Int(r) }
        return nil
    }

    var responsivenessRating: String {
        guard let rpm = responsivenessValue else {
            return "Unknown"
        }
        switch rpm {
        case 0..<200: return "Low"
        case 200..<800: return "Medium"
        case 800..<1500: return "High"
        default: return "Excellent"
        }
    }

    // Average latency computed properties
    var avgIdleH2ReqResp: Double? {
        ilH2ReqResp?.average
    }

    var avgIdleTcpHandshake: Double? {
        ilTcpHandshake443?.average
    }

    var avgIdleTlsHandshake: Double? {
        ilTlsHandshake?.average
    }

    var avgLoadedH2ReqResp: Double? {
        (ludForeignH2ReqResp ?? ludForeignDlH2ReqResp ?? ludForeignUlH2ReqResp)?.average
    }

    var avgLoadedSelfH2ReqResp: Double? {
        (ludSelfH2ReqResp ?? ludSelfDlH2ReqResp ?? ludSelfUlH2ReqResp)?.average
    }

    var avgLoadedTcpHandshake: Double? {
        (ludForeignTcpHandshake443 ?? ludForeignDlTcpHandshake443 ?? ludForeignUlTcpHandshake443)?.average
    }

    var avgLoadedTlsHandshake: Double? {
        (ludForeignTlsHandshake ?? ludForeignDlTlsHandshake ?? ludForeignUlTlsHandshake)?.average
    }

    // Initializer for creating result from text summary output
    init(downloadMbps: Double, uploadMbps: Double, responsivenessRPM: Double?, idleLatencyMs: Double?, interfaceName: String?) {
        self.timestamp = Date()
        self.dlThroughput = Int64(downloadMbps * 1_000_000)
        self.ulThroughput = Int64(uploadMbps * 1_000_000)
        self.responsiveness = responsivenessRPM
        self.dlResponsiveness = nil
        self.ulResponsiveness = nil
        self.baseRtt = idleLatencyMs
        self.dlFlows = nil
        self.ulFlows = nil
        self.interfaceName = interfaceName
        self.osVersion = nil
        self.startDate = nil
        self.endDate = nil
        self.ilH2ReqResp = nil
        self.ilTcpHandshake443 = nil
        self.ilTlsHandshake = nil
        self.ludForeignDlH2ReqResp = nil
        self.ludForeignDlTcpHandshake443 = nil
        self.ludForeignDlTlsHandshake = nil
        self.ludSelfDlH2ReqResp = nil
        self.ludForeignUlH2ReqResp = nil
        self.ludForeignUlTcpHandshake443 = nil
        self.ludForeignUlTlsHandshake = nil
        self.ludSelfUlH2ReqResp = nil
        self.ludForeignH2ReqResp = nil
        self.ludForeignTcpHandshake443 = nil
        self.ludForeignTlsHandshake = nil
        self.ludSelfH2ReqResp = nil
        self.errorCode = nil
        self.errorDomain = nil
    }

    private func formatSpeed(_ bps: Int64?) -> String {
        guard let bps = bps else { return "N/A" }
        let mbps = Double(bps) / 1_000_000.0
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000)
        } else if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        } else {
            return String(format: "%.0f Kbps", mbps * 1000)
        }
    }
}

extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

struct SpeedDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let downloadMbps: Double
    let uploadMbps: Double
}

enum TestMode: String, CaseIterable {
    case parallel = "Parallel"
    case sequential = "Sequential"
    case downloadOnly = "Download Only"
    case uploadOnly = "Upload Only"
}

enum ProtocolSelection: String, CaseIterable {
    case auto = "Auto"
    case h1 = "HTTP/1.1"
    case h2 = "HTTP/2"
    case h3 = "HTTP/3 (QUIC)"
}

enum SpeedUnit: String, CaseIterable {
    case mbps = "Mbit/s"
    case mbytes = "MB/s"

    var label: String {
        rawValue
    }

    /// Format speed from Mbps (megabits per second) to the selected unit
    func format(_ mbps: Double) -> (value: String, unit: String) {
        switch self {
        case .mbps:
            if mbps >= 1000 {
                return (String(format: "%.2f", mbps / 1000), "Gbit/s")
            } else if mbps >= 1 {
                return (String(format: "%.1f", mbps), "Mbit/s")
            } else {
                return (String(format: "%.0f", mbps * 1000), "Kbit/s")
            }
        case .mbytes:
            let mbytes = mbps / 8.0  // 8 bits = 1 byte
            if mbytes >= 1000 {
                return (String(format: "%.2f", mbytes / 1000), "GB/s")
            } else if mbytes >= 1 {
                return (String(format: "%.1f", mbytes), "MB/s")
            } else {
                return (String(format: "%.0f", mbytes * 1000), "KB/s")
            }
        }
    }

    /// Format speed from bps (bits per second) to a display string
    func formatBps(_ bps: Int64?) -> String {
        guard let bps = bps else { return "N/A" }
        let mbps = Double(bps) / 1_000_000.0
        let formatted = format(mbps)
        return "\(formatted.value) \(formatted.unit)"
    }
}

struct TestConfiguration {
    var mode: TestMode = .parallel
    var protocolSelection: ProtocolSelection = .auto
    var networkInterface: String = ""
    var customConfigURL: String = ""
    var maxRunTime: Int = 0
    var disableTLSVerification: Bool = false
    var usePrivateRelay: Bool = false
    var verbose: Bool = false
    var enableL4S: Bool? = nil
}
