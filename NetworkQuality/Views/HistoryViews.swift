import SwiftUI

// MARK: - Multi-Server History View

struct MultiServerHistoryView: View {
    @ObservedObject var historyManager: HistoryManager
    @State private var selectedEntry: MultiServerHistoryEntry?
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        VStack {
            if historyManager.multiServerHistory.isEmpty {
                ContentUnavailableView(
                    "No Multi-Server History",
                    systemImage: "server.rack",
                    description: Text("Run multi-server tests to build history")
                )
            } else {
                List {
                    ForEach(historyManager.multiServerHistory) { entry in
                        MultiServerHistoryRow(entry: entry, speedUnit: speedUnit)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEntry = entry
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    historyManager.deleteMultiServerEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive, action: {
                    historyManager.clearMultiServerHistory()
                }) {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(historyManager.multiServerHistory.isEmpty)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            MultiServerHistoryDetailSheet(entry: entry)
        }
    }
}

struct MultiServerHistoryRow: View {
    let entry: MultiServerHistoryEntry
    let speedUnit: SpeedUnit

    var body: some View {
        HStack(spacing: 12) {
            // Timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.timestamp, style: .date)
                    .font(.subheadline.weight(.medium))
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100, alignment: .leading)

            Divider()

            // Provider results with download/latency/upload
            HStack(spacing: 16) {
                ForEach(entry.results) { result in
                    providerColumn(result: result, isFastest: entry.fastestDownload?.id == result.id)
                }
            }

            Spacer()

            // Winner badge
            if let fastest = entry.fastestDownload {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "trophy")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(fastest.provider)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func providerColumn(result: StoredSpeedTestResult, isFastest: Bool) -> some View {
        VStack(spacing: 2) {
            // Provider icon
            Image(systemName: iconForProvider(result.provider))
                .font(.system(size: 10))
                .foregroundStyle(result.isSuccess ? .primary : .secondary)

            if result.isSuccess {
                // Download
                let dl = speedUnit.format(result.downloadSpeed)
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                    Text(dl.value)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.blue)
                }

                // Latency
                if let latency = result.latency {
                    Text(String(format: "%.0fms", latency))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Upload
                let ul = speedUnit.format(result.uploadSpeed)
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                    Text(ul.value)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                }
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 55)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isFastest ? Color.orange.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func iconForProvider(_ provider: String) -> String {
        switch provider {
        case "Apple": return "apple.logo"
        case "Cloudflare": return "cloud.fill"
        case "M-Lab": return "globe.americas.fill"
        default: return "server.rack"
        }
    }
}

struct MultiServerHistoryDetailSheet: View {
    let entry: MultiServerHistoryEntry
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.timestamp, style: .date)
                                .font(.title2.weight(.semibold))
                            Text(entry.timestamp, style: .time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let fastest = entry.fastestDownload {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trophy")
                                        .foregroundStyle(.secondary)
                                    Text("Fastest")
                                        .font(.caption)
                                }
                                Text(fastest.provider)
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Results grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Results")
                            .font(.headline)

                        ForEach(entry.results) { result in
                            ProviderResultRow(result: result, isFastest: entry.fastestDownload?.id == result.id, speedUnit: speedUnit)
                        }
                    }

                    // Comparison stats
                    if entry.successfulResults.count > 1 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Analysis")
                                .font(.headline)

                            let downloads = entry.successfulResults.map { $0.downloadSpeed }
                            let variance = (downloads.max() ?? 0) - (downloads.min() ?? 0)
                            let variancePercent = downloads.max().map { variance / $0 * 100 } ?? 0

                            HStack {
                                Label("Download Variance", systemImage: "chart.bar")
                                Spacer()
                                Text(String(format: "%.1f Mbps (%.0f%%)", variance, variancePercent))
                                    .foregroundStyle(variancePercent > 20 ? .orange : .green)
                            }
                            .font(.subheadline)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Comparison Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct ProviderResultRow: View {
    let result: StoredSpeedTestResult
    let isFastest: Bool
    let speedUnit: SpeedUnit

    var body: some View {
        HStack(spacing: 16) {
            // Provider icon and name
            HStack(spacing: 8) {
                Image(systemName: iconForProvider(result.provider))
                    .frame(width: 20)
                Text(result.provider)
                    .font(.subheadline.weight(.medium))

                if isFastest {
                    Image(systemName: "trophy")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 120, alignment: .leading)

            if result.isSuccess {
                // Download
                VStack(alignment: .trailing, spacing: 2) {
                    let dl = speedUnit.format(result.downloadSpeed)
                    Text(dl.value)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text(dl.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 70)

                // Upload
                VStack(alignment: .trailing, spacing: 2) {
                    let ul = speedUnit.format(result.uploadSpeed)
                    Text(ul.value)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(ul.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 70)

                // Latency
                VStack(alignment: .trailing, spacing: 2) {
                    if let latency = result.latency {
                        Text(String(format: "%.0f", latency))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 50)
            } else {
                Text(result.error ?? "Failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isFastest ? Color.orange.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func iconForProvider(_ provider: String) -> String {
        switch provider {
        case "Apple": return "apple.logo"
        case "Cloudflare": return "cloud.fill"
        case "M-Lab": return "globe.americas.fill"
        default: return "server.rack"
        }
    }
}

// MARK: - Network Tools History View

struct NetworkToolsHistoryView: View {
    @ObservedObject var historyManager: HistoryManager
    @State private var selectedEntry: NetworkToolsHistoryEntry?
    @State private var filterType: NetworkToolsHistoryEntry.ToolType?

    var filteredHistory: [NetworkToolsHistoryEntry] {
        if let filter = filterType {
            return historyManager.networkToolsHistory.filter { $0.toolType == filter }
        }
        return historyManager.networkToolsHistory
    }

    var body: some View {
        VStack {
            if historyManager.networkToolsHistory.isEmpty {
                ContentUnavailableView(
                    "No Tools History",
                    systemImage: "network",
                    description: Text("Use network tools to build history")
                )
            } else {
                VStack(spacing: 0) {
                    // Filter bar
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: filterType == nil) {
                            filterType = nil
                        }
                        FilterChip(title: "Ping", icon: "antenna.radiowaves.left.and.right", isSelected: filterType == .ping) {
                            filterType = .ping
                        }
                        FilterChip(title: "Traceroute", icon: "point.topleft.down.to.point.bottomright.curvepath", isSelected: filterType == .traceroute) {
                            filterType = .traceroute
                        }
                        FilterChip(title: "DNS", icon: "server.rack", isSelected: filterType == .dns) {
                            filterType = .dns
                        }
                        Spacer()
                    }
                    .padding()

                    Divider()

                    List {
                        ForEach(filteredHistory) { entry in
                            NetworkToolsHistoryRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedEntry = entry
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        historyManager.deleteToolsEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive, action: {
                    historyManager.clearToolsHistory()
                }) {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(historyManager.networkToolsHistory.isEmpty)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            NetworkToolsHistoryDetailSheet(entry: entry)
        }
    }
}

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct NetworkToolsHistoryRow: View {
    let entry: NetworkToolsHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Tool icon
            Image(systemName: entry.toolType.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.toolType.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(entry.host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Timestamp
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct NetworkToolsHistoryDetailSheet: View {
    let entry: NetworkToolsHistoryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: entry.toolType.icon)
                            .font(.title)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.toolType.displayName)
                                .font(.title2.weight(.semibold))
                            Text(entry.host)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.timestamp, style: .date)
                                .font(.subheadline)
                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Details based on tool type
                    switch entry.details {
                    case .ping(let details):
                        PingDetailsView(details: details)
                    case .traceroute(let details):
                        TracerouteDetailsView(details: details)
                    case .dns(let details):
                        DNSDetailsView(details: details)
                    }
                }
                .padding()
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 450, minHeight: 350)
    }
}

struct PingDetailsView: View {
    let details: PingDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "Packets Sent", value: "\(details.packetsTransmitted)", icon: "arrow.up.circle")
                StatCard(title: "Packets Received", value: "\(details.packetsReceived)", icon: "arrow.down.circle")
                StatCard(title: "Packet Loss", value: String(format: "%.1f%%", details.packetLoss),
                         icon: "exclamationmark.triangle", color: details.packetLoss > 0 ? .red : .green)
                StatCard(title: "Avg Time", value: details.avgTime.map { String(format: "%.1f ms", $0) } ?? "-",
                         icon: "clock")
            }

            if let min = details.minTime, let max = details.maxTime {
                HStack {
                    Text("Range: \(String(format: "%.1f", min)) - \(String(format: "%.1f", max)) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TracerouteDetailsView: View {
    let details: TracerouteDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hops")
                    .font(.headline)
                Spacer()
                Text(details.reachedDestination ? "Reached destination" : "Incomplete")
                    .font(.caption)
                    .foregroundStyle(details.reachedDestination ? .green : .orange)
            }

            ForEach(details.hops) { hop in
                HStack(spacing: 12) {
                    Text("\(hop.hopNumber)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 24)
                        .foregroundStyle(.secondary)

                    if hop.timedOut {
                        Text("* * *")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hop.hostname ?? hop.ip ?? "Unknown")
                                .font(.system(size: 13, weight: .medium))
                            if let ip = hop.ip, hop.hostname != nil {
                                Text(ip)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if let rtt = hop.avgRtt {
                        Text(String(format: "%.1f ms", rtt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct DNSDetailsView: View {
    let details: DNSDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(details.recordType) Records")
                .font(.headline)

            ForEach(details.records) { record in
                HStack {
                    Text(record.value)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()

                    if let ttl = record.ttl {
                        Text("TTL: \(ttl)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .blue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - LAN Speed History View

struct LANSpeedHistoryView: View {
    @ObservedObject var historyManager: HistoryManager
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        VStack {
            if historyManager.lanSpeedHistory.isEmpty {
                ContentUnavailableView(
                    "No LAN Speed History",
                    systemImage: "wifi",
                    description: Text("Run LAN speed tests to build history")
                )
            } else {
                List {
                    ForEach(historyManager.lanSpeedHistory) { entry in
                        LANSpeedHistoryRow(entry: entry, speedUnit: speedUnit)
                            .contextMenu {
                                Button(role: .destructive) {
                                    historyManager.deleteLANSpeedEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive, action: {
                    historyManager.clearLANSpeedHistory()
                }) {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(historyManager.lanSpeedHistory.isEmpty)
            }
        }
    }
}

struct LANSpeedHistoryRow: View {
    let entry: LANSpeedHistoryEntry
    let speedUnit: SpeedUnit

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)

            // Peer and time
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.peerName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(entry.timestamp, style: .date)
                    Text("at")
                    Text(entry.timestamp, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Speeds
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 2) {
                    let dl = speedUnit.format(entry.downloadSpeed)
                    Text(dl.value)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text(dl.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    let ul = speedUnit.format(entry.uploadSpeed)
                    Text(ul.value)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(ul.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", entry.latency))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
