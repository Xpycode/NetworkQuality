import Foundation
import SwiftUI

// MARK: - Ping Service

struct PingResult: Identifiable {
    let id = UUID()
    let host: String
    let success: Bool
    let time: Double?
    let error: String?
    let timestamp: Date
}

@MainActor
class PingService: ObservableObject {
    @Published var results: [PingResult] = []
    @Published var isRunning = false

    private var process: Process?
    private var shouldStop = false

    func ping(host: String, count: Int = 0) {
        stop()
        results.removeAll()
        isRunning = true
        shouldStop = false

        Task {
            await runPing(host: host, count: count)
        }
    }

    func stop() {
        shouldStop = true
        process?.terminate()
        process = nil
        isRunning = false
    }

    private func runPing(host: String, count: Int) async {
        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -c 0 means infinite, but we'll use a reasonable default for continuous ping
        var args = ["-i", "1", "-W", "2000"] // 1 second interval, 2 second timeout
        if count > 0 {
            args += ["-c", "\(count)"]
        } else {
            args += ["-c", "20"] // Default to 20 pings
        }
        args.append(host)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            let handle = pipe.fileHandleForReading

            // Read output line by line
            for try await line in handle.bytes.lines {
                if shouldStop { break }

                if let result = parsePingLine(line, host: host) {
                    await MainActor.run {
                        self.results.append(result)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.results.append(PingResult(
                    host: host,
                    success: false,
                    time: nil,
                    error: error.localizedDescription,
                    timestamp: Date()
                ))
            }
        }

        await MainActor.run {
            self.isRunning = false
        }
    }

    private func parsePingLine(_ line: String, host: String) -> PingResult? {
        // Parse: "64 bytes from 17.253.144.10: icmp_seq=0 ttl=59 time=12.345 ms"
        if line.contains("bytes from") && line.contains("time=") {
            if let timeRange = line.range(of: "time="),
               let msRange = line.range(of: " ms", range: timeRange.upperBound..<line.endIndex) {
                let timeStr = String(line[timeRange.upperBound..<msRange.lowerBound])
                if let time = Double(timeStr) {
                    return PingResult(host: host, success: true, time: time, error: nil, timestamp: Date())
                }
            }
        }

        // Parse timeout: "Request timeout for icmp_seq 0"
        if line.contains("Request timeout") || line.contains("Host is down") {
            return PingResult(host: host, success: false, time: nil, error: "Timeout", timestamp: Date())
        }

        // Parse error: "ping: cannot resolve..."
        if line.hasPrefix("ping:") {
            let error = line.replacingOccurrences(of: "ping: ", with: "")
            return PingResult(host: host, success: false, time: nil, error: error, timestamp: Date())
        }

        return nil
    }
}

// MARK: - Traceroute Service

struct TracerouteHop: Identifiable {
    let id = UUID()
    let hopNumber: Int
    let hostname: String?
    let ip: String?
    let rtts: [Double]
    let timedOut: Bool
    var isLast: Bool = false
}

@MainActor
class TracerouteService: ObservableObject {
    @Published var hops: [TracerouteHop] = []
    @Published var isRunning = false

    private var process: Process?

    func trace(host: String) {
        stop()
        hops.removeAll()
        isRunning = true

        Task {
            await runTraceroute(host: host)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }

    private func runTraceroute(host: String) async {
        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")
        // -I: use ICMP (works better through firewalls), -m 30: max 30 hops, -q 1: 1 query per hop, -w 3: 3 second timeout
        process.arguments = ["-I", "-m", "30", "-q", "1", "-w", "3", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            let handle = pipe.fileHandleForReading

            for try await line in handle.bytes.lines {
                if let hop = parseTracerouteLine(line) {
                    await MainActor.run {
                        self.hops.append(hop)
                    }
                }
            }

            // Mark last hop
            await MainActor.run {
                if !self.hops.isEmpty {
                    self.hops[self.hops.count - 1].isLast = true
                }
            }
        } catch {
            // Traceroute failed
        }

        await MainActor.run {
            self.isRunning = false
        }
    }

    private func parseTracerouteLine(_ line: String) -> TracerouteHop? {
        // Skip header line
        if line.hasPrefix("traceroute to") { return nil }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Parse: " 1  router.local (192.168.1.1)  1.234 ms  1.456 ms  1.789 ms"
        // Or:    " 2  * * *"

        let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard let hopNum = Int(components.first ?? "") else { return nil }

        // Check for timeout (any asterisk means timeout for that probe)
        let asteriskCount = components.filter({ $0 == "*" }).count
        if asteriskCount > 0 && asteriskCount == components.count - 1 {
            // All probes timed out (only hop number + asterisks)
            return TracerouteHop(hopNumber: hopNum, hostname: nil, ip: nil, rtts: [], timedOut: true)
        }

        // Parse hostname and IP
        var hostname: String?
        var ip: String?
        var rtts: [Double] = []

        for (index, comp) in components.enumerated() {
            if index == 0 { continue } // Skip hop number

            let str = String(comp)

            // IP in parentheses
            if str.hasPrefix("(") && str.hasSuffix(")") {
                ip = String(str.dropFirst().dropLast())
            }
            // RTT value
            else if let rtt = Double(str) {
                rtts.append(rtt)
            }
            // Skip "ms"
            else if str == "ms" {
                continue
            }
            // Hostname
            else if hostname == nil && !str.hasPrefix("(") {
                hostname = str
            }
        }

        // If no hostname but have IP, the IP might be shown without parentheses
        if hostname == nil && ip == nil && components.count > 1 {
            let potentialIP = String(components[1])
            if potentialIP.contains(".") || potentialIP.contains(":") {
                ip = potentialIP
            }
        }

        return TracerouteHop(hopNumber: hopNum, hostname: hostname, ip: ip, rtts: rtts, timedOut: false)
    }
}

// MARK: - DNS Lookup Service

enum DNSRecordType: String, CaseIterable {
    case a = "A"
    case aaaa = "AAAA"
    case cname = "CNAME"
    case mx = "MX"
    case txt = "TXT"
    case ns = "NS"

    var description: String {
        switch self {
        case .a: return "IPv4 address"
        case .aaaa: return "IPv6 address"
        case .cname: return "Alias to another domain"
        case .mx: return "Mail servers"
        case .txt: return "Text records (SPF, DKIM, verification)"
        case .ns: return "Name servers"
        }
    }
}

struct DNSRecord: Identifiable {
    let id = UUID()
    let type: DNSRecordType
    let value: String
    let ttl: Int?
}

@MainActor
class DNSLookupService: ObservableObject {
    @Published var records: [DNSRecord] = []
    @Published var isRunning = false
    @Published var error: String?

    func lookup(host: String, recordType: DNSRecordType) {
        records.removeAll()
        error = nil
        isRunning = true

        Task {
            await runLookup(host: host, recordType: recordType)
        }
    }

    private func runLookup(host: String, recordType: DNSRecordType) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        process.arguments = ["+noall", "+answer", "+ttlid", host, recordType.rawValue]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let parsedRecords = parseDigOutput(output, requestedType: recordType)

                await MainActor.run {
                    if parsedRecords.isEmpty {
                        self.error = "No \(recordType.rawValue) records found"
                    } else {
                        self.records = parsedRecords
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }

        await MainActor.run {
            self.isRunning = false
        }
    }

    private func parseDigOutput(_ output: String, requestedType: DNSRecordType) -> [DNSRecord] {
        var records: [DNSRecord] = []

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse: "apple.com.		3600	IN	A	17.253.144.10"
            let components = trimmed.split(separator: "\t", omittingEmptySubsequences: true)
            guard components.count >= 5 else { continue }

            let ttl = Int(components[1])
            let typeStr = String(components[3])
            let value = components[4...].joined(separator: " ")

            // Match the record type
            if let type = DNSRecordType(rawValue: typeStr) {
                records.append(DNSRecord(type: type, value: value, ttl: ttl))
            } else if typeStr == requestedType.rawValue {
                records.append(DNSRecord(type: requestedType, value: value, ttl: ttl))
            }
        }

        return records
    }
}
