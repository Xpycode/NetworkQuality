import SwiftUI
import Combine

// Shared state for all network tools to persist across tab switches
@MainActor
class NetworkToolsState: ObservableObject {
    let pingService = PingService()
    let tracerouteService = TracerouteService()
    let dnsService = DNSLookupService()

    @Published var pingHost = ""
    @Published var tracerouteHost = ""
    @Published var dnsHost = ""
    @Published var selectedRecordType = DNSRecordType.a

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward service changes to trigger UI updates
        pingService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        tracerouteService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        dnsService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

struct NetworkToolsView: View {
    @State private var selectedTool = 0
    @StateObject private var state = NetworkToolsState()

    var body: some View {
        VStack(spacing: 0) {
            // Tool picker
            Picker("Tool", selection: $selectedTool) {
                Text("Ping").tag(0)
                Text("Traceroute").tag(1)
                Text("DNS Lookup").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
            .padding()

            Divider()

            // Tool content
            switch selectedTool {
            case 0:
                PingToolView(state: state)
            case 1:
                TracerouteToolView(state: state)
            case 2:
                DNSLookupToolView(state: state)
            default:
                Text("Select a tool")
            }
        }
    }
}

// MARK: - Popular Hosts

struct PopularHostsView: View {
    let onSelect: (String) -> Void

    private let hosts = [
        ("apple.com", "apple.logo"),
        ("google.com", "g.circle.fill"),
        ("github.com", "chevron.left.forwardslash.chevron.right"),
        ("youtube.com", "play.rectangle.fill"),
        ("reddit.com", "bubble.left.and.bubble.right.fill"),
        ("cloudflare.com", "cloud.fill"),
        ("amazon.com", "cart.fill"),
        ("netflix.com", "play.tv.fill"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(hosts, id: \.0) { host, icon in
                    Button {
                        onSelect(host)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.caption)
                            Text(host.replacingOccurrences(of: ".com", with: ""))
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Ping Tool

struct PingToolView: View {
    @ObservedObject var state: NetworkToolsState

    private var pingService: PingService { state.pingService }

    var body: some View {
        VStack(spacing: 12) {
            // Quick access hosts
            PopularHostsView { selectedHost in
                state.pingHost = selectedHost
                if !pingService.isRunning {
                    startPing()
                }
            }

            // Input
            HStack {
                TextField("example.com or IP address", text: $state.pingHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { startPing() }

                Button(pingService.isRunning ? "Stop" : "Ping") {
                    if pingService.isRunning {
                        pingService.stop()
                    } else {
                        startPing()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(pingService.isRunning ? .red : .accentColor)
            }
            .padding(.horizontal)

            if !pingService.results.isEmpty {
                // Stats summary
                PingStatsView(results: pingService.results)
                    .padding(.horizontal)

                Divider()

                // Results list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(pingService.results) { result in
                                PingResultRow(result: result)
                                    .id(result.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: pingService.results.count) { _, _ in
                        if let last = pingService.results.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Ready to Ping",
                    systemImage: "network",
                    description: Text("Enter a host and tap Ping to start")
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.top)
    }

    private func startPing() {
        let trimmed = state.pingHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pingService.ping(host: trimmed)
    }
}

struct PingStatsView: View {
    let results: [PingResult]

    private var successfulPings: [PingResult] {
        results.filter { $0.success }
    }

    private var stats: (min: Double, max: Double, avg: Double, loss: Double)? {
        guard !results.isEmpty else { return nil }
        let times = successfulPings.compactMap { $0.time }
        guard !times.isEmpty else { return nil }

        let min = times.min() ?? 0
        let max = times.max() ?? 0
        let avg = times.reduce(0, +) / Double(times.count)
        let loss = Double(results.count - successfulPings.count) / Double(results.count) * 100

        return (min, max, avg, loss)
    }

    var body: some View {
        if let stats = stats {
            HStack(spacing: 20) {
                StatBox(label: "Min", value: String(format: "%.1f ms", stats.min), color: .green)
                StatBox(label: "Avg", value: String(format: "%.1f ms", stats.avg), color: .blue)
                StatBox(label: "Max", value: String(format: "%.1f ms", stats.max), color: .orange)
                StatBox(label: "Loss", value: String(format: "%.0f%%", stats.loss), color: stats.loss > 0 ? .red : .green)
            }
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PingResultRow: View {
    let result: PingResult

    var body: some View {
        HStack {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? .green : .red)

            Text(result.host)
                .font(.system(.body, design: .monospaced))

            Spacer()

            if let time = result.time {
                Text(String(format: "%.1f ms", time))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(timeColor(time))
            } else if let error = result.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(result.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func timeColor(_ ms: Double) -> Color {
        switch ms {
        case 0..<50: return .green
        case 50..<100: return .blue
        case 100..<200: return .orange
        default: return .red
        }
    }
}

// MARK: - Traceroute Tool

struct TracerouteToolView: View {
    @ObservedObject var state: NetworkToolsState

    private var tracerouteService: TracerouteService { state.tracerouteService }

    var body: some View {
        VStack(spacing: 12) {
            // Quick access hosts
            PopularHostsView { selectedHost in
                state.tracerouteHost = selectedHost
                if !tracerouteService.isRunning {
                    startTraceroute()
                }
            }

            // Input
            HStack {
                TextField("example.com or IP address", text: $state.tracerouteHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { startTraceroute() }

                Button(tracerouteService.isRunning ? "Stop" : "Trace") {
                    if tracerouteService.isRunning {
                        tracerouteService.stop()
                    } else {
                        startTraceroute()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(tracerouteService.isRunning ? .red : .accentColor)
            }
            .padding(.horizontal)

            if !tracerouteService.hops.isEmpty || tracerouteService.isRunning {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(tracerouteService.hops) { hop in
                            TracerouteHopRow(hop: hop)
                        }

                        if tracerouteService.isRunning {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Tracing...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Ready to Trace",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Enter a host to trace the network path")
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.top)
    }

    private func startTraceroute() {
        let trimmed = state.tracerouteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tracerouteService.trace(host: trimmed)
    }
}

struct TracerouteHopRow: View {
    let hop: TracerouteHop

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Hop number
            Text("\(hop.hopNumber)")
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Visual indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(hop.timedOut ? .orange : .green)
                    .frame(width: 10, height: 10)
                if !hop.isLast {
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 2, height: 20)
                }
            }

            // Hop details
            VStack(alignment: .leading, spacing: 4) {
                if hop.timedOut {
                    Text("* * *")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.orange)
                } else {
                    Text(hop.hostname ?? hop.ip ?? "Unknown")
                        .font(.system(.body, design: .monospaced))

                    if hop.hostname != nil, let ip = hop.ip {
                        Text(ip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // RTT times
            if !hop.timedOut {
                HStack(spacing: 8) {
                    ForEach(hop.rtts.indices, id: \.self) { index in
                        Text(String(format: "%.1f", hop.rtts[index]))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(rttColor(hop.rtts[index]))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func rttColor(_ ms: Double) -> Color {
        switch ms {
        case 0..<50: return .green
        case 50..<100: return .blue
        case 100..<200: return .orange
        default: return .red
        }
    }
}

// MARK: - DNS Lookup Tool

struct DNSLookupToolView: View {
    @ObservedObject var state: NetworkToolsState

    private var dnsService: DNSLookupService { state.dnsService }

    var body: some View {
        VStack(spacing: 12) {
            // Quick access hosts
            PopularHostsView { selectedHost in
                state.dnsHost = selectedHost
                performLookup()
            }

            // Input
            HStack {
                TextField("example.com", text: $state.dnsHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performLookup() }

                Picker("Type", selection: $state.selectedRecordType) {
                    ForEach(DNSRecordType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                .help(state.selectedRecordType.description)

                Button(dnsService.isRunning ? "..." : "Lookup") {
                    performLookup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(dnsService.isRunning)
            }
            .padding(.horizontal)

            // Record type description
            Text(state.selectedRecordType.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if !dnsService.records.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(dnsService.records) { record in
                            DNSRecordRow(record: record)
                        }
                    }
                    .padding()
                }
            } else if let error = dnsService.error {
                ContentUnavailableView(
                    "Lookup Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ContentUnavailableView(
                    "Ready to Lookup",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a domain to query DNS records")
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.top)
    }

    private func performLookup() {
        let trimmed = state.dnsHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dnsService.lookup(host: trimmed, recordType: state.selectedRecordType)
    }
}

struct DNSRecordRow: View {
    let record: DNSRecord

    var body: some View {
        HStack(alignment: .top) {
            Text(record.type.rawValue)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(typeColor(record.type))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                if let ttl = record.ttl {
                    Text("TTL: \(ttl)s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func typeColor(_ type: DNSRecordType) -> Color {
        switch type {
        case .a: return .blue
        case .aaaa: return .purple
        case .cname: return .orange
        case .mx: return .green
        case .txt: return .pink
        case .ns: return .teal
        }
    }
}

#Preview {
    NetworkToolsView()
        .frame(width: 600, height: 500)
}
