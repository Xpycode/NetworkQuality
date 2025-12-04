import Foundation

// MARK: - Multi-Server History

struct MultiServerHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let results: [StoredSpeedTestResult]

    init(id: UUID = UUID(), timestamp: Date = Date(), results: [SpeedTestResult]) {
        self.id = id
        self.timestamp = timestamp
        self.results = results.map { StoredSpeedTestResult(from: $0) }
    }

    var fastestDownload: StoredSpeedTestResult? {
        results.filter { $0.isSuccess }.max(by: { $0.downloadSpeed < $1.downloadSpeed })
    }

    var fastestUpload: StoredSpeedTestResult? {
        results.filter { $0.isSuccess }.max(by: { $0.uploadSpeed < $1.uploadSpeed })
    }

    var lowestLatency: StoredSpeedTestResult? {
        results.filter { $0.isSuccess && $0.latency != nil }.min(by: { ($0.latency ?? .infinity) < ($1.latency ?? .infinity) })
    }

    var successfulResults: [StoredSpeedTestResult] {
        results.filter { $0.isSuccess }
    }
}

// Codable version of SpeedTestResult for persistence
struct StoredSpeedTestResult: Identifiable, Codable {
    let id: UUID
    let provider: String
    let downloadSpeed: Double
    let uploadSpeed: Double
    let latency: Double?
    let serverLocation: String?
    let timestamp: Date
    let error: String?

    var isSuccess: Bool { error == nil }

    init(from result: SpeedTestResult) {
        self.id = result.id
        self.provider = result.provider
        self.downloadSpeed = result.downloadSpeed
        self.uploadSpeed = result.uploadSpeed
        self.latency = result.latency
        self.serverLocation = result.serverLocation
        self.timestamp = result.timestamp
        self.error = result.error
    }
}

// MARK: - Network Tools History

struct NetworkToolsHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let toolType: ToolType
    let host: String
    let summary: String
    let details: ToolDetails

    enum ToolType: String, Codable {
        case ping
        case traceroute
        case dns

        var icon: String {
            switch self {
            case .ping: return "antenna.radiowaves.left.and.right"
            case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
            case .dns: return "server.rack"
            }
        }

        var displayName: String {
            switch self {
            case .ping: return "Ping"
            case .traceroute: return "Traceroute"
            case .dns: return "DNS Lookup"
            }
        }
    }

    enum ToolDetails: Codable {
        case ping(PingDetails)
        case traceroute(TracerouteDetails)
        case dns(DNSDetails)
    }
}

struct PingDetails: Codable {
    let packetsTransmitted: Int
    let packetsReceived: Int
    let minTime: Double?
    let avgTime: Double?
    let maxTime: Double?

    var packetLoss: Double {
        guard packetsTransmitted > 0 else { return 0 }
        return Double(packetsTransmitted - packetsReceived) / Double(packetsTransmitted) * 100
    }
}

struct TracerouteDetails: Codable {
    let hops: [TracerouteHopDetail]
    let reachedDestination: Bool
}

struct TracerouteHopDetail: Codable, Identifiable {
    var id: Int { hopNumber }
    let hopNumber: Int
    let hostname: String?
    let ip: String?
    let avgRtt: Double?
    let timedOut: Bool
}

struct DNSDetails: Codable {
    let recordType: String
    let records: [DNSRecordDetail]
}

struct DNSRecordDetail: Codable, Identifiable {
    let id: UUID
    let type: String
    let value: String
    let ttl: Int?

    init(id: UUID = UUID(), type: String, value: String, ttl: Int?) {
        self.id = id
        self.type = type
        self.value = value
        self.ttl = ttl
    }
}

// MARK: - LAN Speed History

struct LANSpeedHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let peerName: String
    let downloadSpeed: Double // Mbps
    let uploadSpeed: Double // Mbps
    let latency: Double // ms
    let bytesTransferred: Int64
    let duration: TimeInterval

    init(id: UUID = UUID(), timestamp: Date = Date(), peerName: String, downloadSpeed: Double, uploadSpeed: Double, latency: Double, bytesTransferred: Int64, duration: TimeInterval) {
        self.id = id
        self.timestamp = timestamp
        self.peerName = peerName
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.latency = latency
        self.bytesTransferred = bytesTransferred
        self.duration = duration
    }
}

// MARK: - History Manager

@MainActor
class HistoryManager: ObservableObject {
    @Published var multiServerHistory: [MultiServerHistoryEntry] = []
    @Published var networkToolsHistory: [NetworkToolsHistoryEntry] = []
    @Published var lanSpeedHistory: [LANSpeedHistoryEntry] = []

    private let multiServerKey = "multiServerHistory"
    private let networkToolsKey = "networkToolsHistory"
    private let lanSpeedKey = "lanSpeedHistory"
    private let maxEntries = 100

    init() {
        loadHistory()
    }

    // MARK: - Multi-Server History

    func saveMultiServerResult(_ results: [SpeedTestResult]) {
        let entry = MultiServerHistoryEntry(results: results)
        multiServerHistory.insert(entry, at: 0)

        // Trim to max entries
        if multiServerHistory.count > maxEntries {
            multiServerHistory = Array(multiServerHistory.prefix(maxEntries))
        }

        persistMultiServerHistory()
    }

    func deleteMultiServerEntry(_ entry: MultiServerHistoryEntry) {
        multiServerHistory.removeAll { $0.id == entry.id }
        persistMultiServerHistory()
    }

    func clearMultiServerHistory() {
        multiServerHistory.removeAll()
        persistMultiServerHistory()
    }

    // MARK: - Network Tools History

    func savePingResult(host: String, results: [PingResult]) {
        let transmitted = results.count
        let received = results.filter { $0.success }.count
        let times = results.compactMap { $0.time }

        let details = PingDetails(
            packetsTransmitted: transmitted,
            packetsReceived: received,
            minTime: times.min(),
            avgTime: times.isEmpty ? nil : times.reduce(0, +) / Double(times.count),
            maxTime: times.max()
        )

        let summary: String
        if let avg = details.avgTime {
            summary = String(format: "%.1f ms avg, %.0f%% loss", avg, details.packetLoss)
        } else {
            summary = "100% packet loss"
        }

        let entry = NetworkToolsHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            toolType: .ping,
            host: host,
            summary: summary,
            details: .ping(details)
        )

        networkToolsHistory.insert(entry, at: 0)
        trimAndPersistToolsHistory()
    }

    func saveTracerouteResult(host: String, hops: [TracerouteHop]) {
        let hopDetails = hops.map { hop in
            TracerouteHopDetail(
                hopNumber: hop.hopNumber,
                hostname: hop.hostname,
                ip: hop.ip,
                avgRtt: hop.rtts.isEmpty ? nil : hop.rtts.reduce(0, +) / Double(hop.rtts.count),
                timedOut: hop.timedOut
            )
        }

        let details = TracerouteDetails(
            hops: hopDetails,
            reachedDestination: hops.last?.isLast ?? false
        )

        let summary = "\(hops.count) hops" + (details.reachedDestination ? " - reached" : " - incomplete")

        let entry = NetworkToolsHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            toolType: .traceroute,
            host: host,
            summary: summary,
            details: .traceroute(details)
        )

        networkToolsHistory.insert(entry, at: 0)
        trimAndPersistToolsHistory()
    }

    func saveDNSResult(host: String, recordType: DNSRecordType, records: [DNSRecord]) {
        let recordDetails = records.map { record in
            DNSRecordDetail(type: record.type.rawValue, value: record.value, ttl: record.ttl)
        }

        let details = DNSDetails(recordType: recordType.rawValue, records: recordDetails)
        let summary = "\(records.count) \(recordType.rawValue) record\(records.count == 1 ? "" : "s")"

        let entry = NetworkToolsHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            toolType: .dns,
            host: host,
            summary: summary,
            details: .dns(details)
        )

        networkToolsHistory.insert(entry, at: 0)
        trimAndPersistToolsHistory()
    }

    func deleteToolsEntry(_ entry: NetworkToolsHistoryEntry) {
        networkToolsHistory.removeAll { $0.id == entry.id }
        persistToolsHistory()
    }

    func clearToolsHistory() {
        networkToolsHistory.removeAll()
        persistToolsHistory()
    }

    // MARK: - LAN Speed History

    func saveLANSpeedResult(peerName: String, downloadSpeed: Double, uploadSpeed: Double, latency: Double, bytesTransferred: Int64, duration: TimeInterval) {
        let entry = LANSpeedHistoryEntry(
            peerName: peerName,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            latency: latency,
            bytesTransferred: bytesTransferred,
            duration: duration
        )
        lanSpeedHistory.insert(entry, at: 0)

        if lanSpeedHistory.count > maxEntries {
            lanSpeedHistory = Array(lanSpeedHistory.prefix(maxEntries))
        }
        persistLanSpeedHistory()
    }

    func deleteLANSpeedEntry(_ entry: LANSpeedHistoryEntry) {
        lanSpeedHistory.removeAll { $0.id == entry.id }
        persistLanSpeedHistory()
    }

    func clearLANSpeedHistory() {
        lanSpeedHistory.removeAll()
        persistLanSpeedHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        // Load multi-server history
        if let data = UserDefaults.standard.data(forKey: multiServerKey),
           let decoded = try? JSONDecoder().decode([MultiServerHistoryEntry].self, from: data) {
            multiServerHistory = decoded
        }

        // Load network tools history
        if let data = UserDefaults.standard.data(forKey: networkToolsKey),
           let decoded = try? JSONDecoder().decode([NetworkToolsHistoryEntry].self, from: data) {
            networkToolsHistory = decoded
        }

        // Load LAN speed history
        if let data = UserDefaults.standard.data(forKey: lanSpeedKey),
           let decoded = try? JSONDecoder().decode([LANSpeedHistoryEntry].self, from: data) {
            lanSpeedHistory = decoded
        }
    }

    private func persistMultiServerHistory() {
        if let encoded = try? JSONEncoder().encode(multiServerHistory) {
            UserDefaults.standard.set(encoded, forKey: multiServerKey)
        }
    }

    private func persistToolsHistory() {
        if let encoded = try? JSONEncoder().encode(networkToolsHistory) {
            UserDefaults.standard.set(encoded, forKey: networkToolsKey)
        }
    }

    private func trimAndPersistToolsHistory() {
        if networkToolsHistory.count > maxEntries {
            networkToolsHistory = Array(networkToolsHistory.prefix(maxEntries))
        }
        persistToolsHistory()
    }

    private func persistLanSpeedHistory() {
        if let encoded = try? JSONEncoder().encode(lanSpeedHistory) {
            UserDefaults.standard.set(encoded, forKey: lanSpeedKey)
        }
    }
}
