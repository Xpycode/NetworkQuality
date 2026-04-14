import SwiftUI
import AppKit

// MARK: - Ping Share Card

struct PingShareCardView: View {
    let host: String
    let results: [PingResult]
    let timestamp: Date

    private let cardWidth: CGFloat = 400
    private let cardHeight: CGFloat = 380

    private var stats: PingStats {
        let times = results.compactMap { $0.time }
        let received = results.filter { $0.success }.count
        let transmitted = results.count

        return PingStats(
            transmitted: transmitted,
            received: received,
            minTime: times.min(),
            avgTime: times.isEmpty ? nil : times.reduce(0, +) / Double(times.count),
            maxTime: times.max()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Content
            VStack(spacing: 16) {
                // Host info
                hostSection

                Divider()
                    .padding(.horizontal)

                // Stats grid
                statsSection

                // Latency visualization
                if let avg = stats.avgTime {
                    latencyBarSection(avg)
                }

                Spacer(minLength: 0)

                // Footer
                footerSection
            }
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    private var headerSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.cyan, Color.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Ping Results")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Text(qualityLabel)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.9)
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
        }
        .frame(height: 80)
    }

    private var qualityLabel: String {
        guard let avg = stats.avgTime else { return "No response" }
        switch avg {
        case 0..<20: return "Excellent Response Time"
        case 20..<50: return "Good Response Time"
        case 50..<100: return "Fair Response Time"
        default: return "High Latency"
        }
    }

    private var hostSection: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(.secondary)
            Text(host)
                .font(.system(size: 16, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            // Packets
            VStack(spacing: 4) {
                Text("\(stats.received)/\(stats.transmitted)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Packets")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f%% loss", stats.packetLoss))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(stats.packetLoss > 0 ? .red : .green)
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 50)

            // Min/Avg/Max
            VStack(spacing: 4) {
                if let avg = stats.avgTime {
                    Text(String(format: "%.1f ms", avg))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Avg Latency")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let min = stats.minTime, let max = stats.maxTime {
                        Text(String(format: "%.1f - %.1f ms", min, max))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("No Response")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }

    private func latencyBarSection(_ avg: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Response Time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(latencyRating(avg))
                    .font(.caption.weight(.medium))
                    .foregroundColor(latencyColor(avg))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(latencyColor(avg))
                        .frame(width: min(geo.size.width * CGFloat(min(avg, 200) / 200), geo.size.width))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 20)
    }

    private var footerSection: some View {
        HStack {
            Text(timestamp, style: .date)
            Text("at")
            Text(timestamp, style: .time)
            Spacer()
            Text("NetworkQuality")
                .foregroundColor(.secondary.opacity(0.7))
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func latencyRating(_ ms: Double) -> String {
        switch ms {
        case 0..<20: return "Excellent"
        case 20..<50: return "Good"
        case 50..<100: return "Fair"
        default: return "High"
        }
    }

    private func latencyColor(_ ms: Double) -> Color {
        switch ms {
        case 0..<20: return .green
        case 20..<50: return .blue
        case 50..<100: return .orange
        default: return .red
        }
    }
}

private struct PingStats {
    let transmitted: Int
    let received: Int
    let minTime: Double?
    let avgTime: Double?
    let maxTime: Double?

    var packetLoss: Double {
        guard transmitted > 0 else { return 0 }
        return Double(transmitted - received) / Double(transmitted) * 100
    }
}

// MARK: - Traceroute Share Card

struct TracerouteShareCardView: View {
    let host: String
    let hops: [TracerouteHop]
    let timestamp: Date

    private let cardWidth: CGFloat = 420
    private var cardHeight: CGFloat {
        CGFloat(min(max(hops.count, 5), 12) * 32 + 220)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Content
            VStack(spacing: 12) {
                // Destination info
                destinationSection

                Divider()
                    .padding(.horizontal)

                // Hop list
                hopListSection

                Spacer(minLength: 0)

                // Footer
                footerSection
            }
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    private var headerSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Traceroute")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Text("\(hops.count) hops" + (reachedDestination ? " - reached" : " - incomplete"))
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.9)
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
        }
        .frame(height: 80)
    }

    private var reachedDestination: Bool {
        hops.last?.isLast ?? false
    }

    private var destinationSection: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(.secondary)
            Text(host)
                .font(.system(size: 15, weight: .medium))
            Spacer()

            if reachedDestination {
                Label("Reached", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Label("Incomplete", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
    }

    private var hopListSection: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("#")
                    .frame(width: 25, alignment: .center)
                Text("Host")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("RTT")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            // Hop rows (limit to first 12)
            ForEach(hops.prefix(12)) { hop in
                hopRow(hop)
            }

            if hops.count > 12 {
                Text("... and \(hops.count - 12) more hops")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func hopRow(_ hop: TracerouteHop) -> some View {
        HStack {
            Text("\(hop.hopNumber)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 25, alignment: .center)
                .foregroundColor(.secondary)

            if hop.timedOut {
                Text("* * *")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text(hop.hostname ?? hop.ip ?? "Unknown")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }

            Spacer()

            if !hop.timedOut, let rtt = hop.rtts.first {
                Text(String(format: "%.1f ms", rtt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(rttColor(rtt))
                    .frame(width: 70, alignment: .trailing)
            } else {
                Text("-")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(hop.hopNumber % 2 == 0 ? Color.secondary.opacity(0.05) : Color.clear)
    }

    private func rttColor(_ rtt: Double) -> Color {
        switch rtt {
        case 0..<30: return .green
        case 30..<100: return .orange
        default: return .red
        }
    }

    private var footerSection: some View {
        HStack {
            Text(timestamp, style: .date)
            Text("at")
            Text(timestamp, style: .time)
            Spacer()
            Text("NetworkQuality")
                .foregroundColor(.secondary.opacity(0.7))
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - DNS Share Card

struct DNSShareCardView: View {
    let host: String
    let recordType: DNSRecordType
    let records: [DNSRecord]
    let timestamp: Date

    private let cardWidth: CGFloat = 400
    private var cardHeight: CGFloat {
        CGFloat(min(max(records.count, 3), 8) * 36 + 220)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Content
            VStack(spacing: 12) {
                // Query info
                querySection

                Divider()
                    .padding(.horizontal)

                // Records list
                recordsSection

                Spacer(minLength: 0)

                // Footer
                footerSection
            }
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    private var headerSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.teal, Color.mint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 20, weight: .semibold))
                    Text("DNS Lookup")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Text("\(records.count) \(recordType.rawValue) record\(records.count == 1 ? "" : "s") found")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.9)
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
        }
        .frame(height: 80)
    }

    private var querySection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Query")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(host)
                    .font(.system(size: 15, weight: .medium))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(recordType.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.teal)
            }
        }
        .padding(.horizontal, 20)
    }

    private var recordsSection: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("Type")
                    .frame(width: 50, alignment: .leading)
                Text("Value")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("TTL")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            // Record rows (limit to first 8)
            ForEach(records.prefix(8)) { record in
                recordRow(record)
            }

            if records.count > 8 {
                Text("... and \(records.count - 8) more records")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func recordRow(_ record: DNSRecord) -> some View {
        HStack {
            Text(record.type.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.teal)
                .frame(width: 50, alignment: .leading)

            Text(record.value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let ttl = record.ttl {
                Text(formatTTL(ttl))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("-")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(records.firstIndex(where: { $0.id == record.id })! % 2 == 0 ? Color.secondary.opacity(0.05) : Color.clear)
    }

    private func formatTTL(_ seconds: Int) -> String {
        if seconds >= 86400 {
            return "\(seconds / 86400)d"
        } else if seconds >= 3600 {
            return "\(seconds / 3600)h"
        } else if seconds >= 60 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds)s"
        }
    }

    private var footerSection: some View {
        HStack {
            Text(timestamp, style: .date)
            Text("at")
            Text(timestamp, style: .time)
            Spacer()
            Text("NetworkQuality")
                .foregroundColor(.secondary.opacity(0.7))
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Image Rendering Extensions

extension PingShareCardView {
    @MainActor
    func renderAsImage() -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cardWidth, height: cardHeight))
    }
}

extension TracerouteShareCardView {
    @MainActor
    func renderAsImage() -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cardWidth, height: cardHeight))
    }
}

extension DNSShareCardView {
    @MainActor
    func renderAsImage() -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0
        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cardWidth, height: cardHeight))
    }
}

// MARK: - Share Service for Network Tools

@MainActor
class NetworkToolsShareService {
    static let shared = NetworkToolsShareService()
    private init() {}

    func savePingCard(host: String, results: [PingResult]) {
        let card = PingShareCardView(host: host, results: results, timestamp: Date())
        guard let image = card.renderAsImage() else { return }
        saveImage(image, filename: "Ping-\(host)")
    }

    func saveTracerouteCard(host: String, hops: [TracerouteHop]) {
        let card = TracerouteShareCardView(host: host, hops: hops, timestamp: Date())
        guard let image = card.renderAsImage() else { return }
        saveImage(image, filename: "Traceroute-\(host)")
    }

    func saveDNSCard(host: String, recordType: DNSRecordType, records: [DNSRecord]) {
        let card = DNSShareCardView(host: host, recordType: recordType, records: records, timestamp: Date())
        guard let image = card.renderAsImage() else { return }
        saveImage(image, filename: "DNS-\(host)")
    }

    func copyPingCardToClipboard(host: String, results: [PingResult]) -> Bool {
        let card = PingShareCardView(host: host, results: results, timestamp: Date())
        guard let image = card.renderAsImage() else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        return true
    }

    func copyTracerouteCardToClipboard(host: String, hops: [TracerouteHop]) -> Bool {
        let card = TracerouteShareCardView(host: host, hops: hops, timestamp: Date())
        guard let image = card.renderAsImage() else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        return true
    }

    func copyDNSCardToClipboard(host: String, recordType: DNSRecordType, records: [DNSRecord]) -> Bool {
        let card = DNSShareCardView(host: host, recordType: recordType, records: records, timestamp: Date())
        guard let image = card.renderAsImage() else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        return true
    }

    private func saveImage(_ image: NSImage, filename: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "\(filename)-\(formattedDate()).png"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                guard let tiffData = image.tiffRepresentation,
                      let bitmapRep = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                    return
                }
                try? pngData.write(to: url)
            }
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}

// MARK: - Previews

#Preview("Ping Card") {
    PingShareCardView(
        host: "google.com",
        results: [
            PingResult(host: "google.com", success: true, time: 12.5, error: nil, timestamp: Date()),
            PingResult(host: "google.com", success: true, time: 14.2, error: nil, timestamp: Date()),
            PingResult(host: "google.com", success: true, time: 11.8, error: nil, timestamp: Date()),
            PingResult(host: "google.com", success: true, time: 13.1, error: nil, timestamp: Date()),
            PingResult(host: "google.com", success: false, time: nil, error: "timeout", timestamp: Date())
        ],
        timestamp: Date()
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}

#Preview("Traceroute Card") {
    TracerouteShareCardView(
        host: "8.8.8.8",
        hops: [
            TracerouteHop(hopNumber: 1, hostname: "router.local", ip: "192.168.1.1", rtts: [1.2, 1.5, 1.3], timedOut: false, isLast: false),
            TracerouteHop(hopNumber: 2, hostname: nil, ip: "10.0.0.1", rtts: [5.6], timedOut: false, isLast: false),
            TracerouteHop(hopNumber: 3, hostname: "isp-gateway.net", ip: "72.14.215.85", rtts: [12.4, 11.8], timedOut: false, isLast: false),
            TracerouteHop(hopNumber: 4, hostname: nil, ip: nil, rtts: [], timedOut: true, isLast: false),
            TracerouteHop(hopNumber: 5, hostname: "dns.google", ip: "8.8.8.8", rtts: [18.5, 17.9], timedOut: false, isLast: true)
        ],
        timestamp: Date()
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}

#Preview("DNS Card") {
    DNSShareCardView(
        host: "google.com",
        recordType: .a,
        records: [
            DNSRecord(type: .a, value: "142.250.189.206", ttl: 300),
            DNSRecord(type: .a, value: "142.250.189.238", ttl: 300),
            DNSRecord(type: .aaaa, value: "2607:f8b0:4004:800::200e", ttl: 300)
        ],
        timestamp: Date()
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
