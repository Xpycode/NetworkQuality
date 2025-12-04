import SwiftUI

struct ResultsView: View {
    let result: NetworkQualityResult?
    let verboseOutput: [String]
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue
    @State private var selectedTab = 0

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let result = result {
                    // Tab picker for Insights vs Raw Data
                    Picker("View", selection: $selectedTab) {
                        Text("Insights").tag(0)
                        Text("Raw Data").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    if selectedTab == 0 {
                        // Insights Tab - Plain language explanations

                        // Network metadata section (if available)
                        if let metadata = result.networkMetadata {
                            NetworkMetadataSection(metadata: metadata)
                        }

                        InsightsView(result: result)
                    } else {
                        // Raw Data Tab - Technical metrics
                        RawMetricsView(result: result, speedUnit: speedUnit)

                        // Detailed metrics
                        if hasDetailedMetrics(result) {
                            DetailedMetricsSection(result: result)
                        }

                        // Connection info
                        ConnectionInfoSection(result: result)
                    }

                    // Verbose output (only show with results)
                    if !verboseOutput.isEmpty {
                        VerboseOutputSection(output: verboseOutput)
                    }
                } else {
                    // No results - centered empty state
                    VStack {
                        Spacer()
                        ContentUnavailableView(
                            "No Results Yet",
                            systemImage: "network",
                            description: Text("Run a test to see results")
                        )

                        // Verbose output below empty state
                        if !verboseOutput.isEmpty {
                            VerboseOutputSection(output: verboseOutput)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    private func hasDetailedMetrics(_ result: NetworkQualityResult) -> Bool {
        result.avgIdleH2ReqResp != nil ||
        result.avgIdleTcpHandshake != nil ||
        result.avgIdleTlsHandshake != nil ||
        result.avgLoadedH2ReqResp != nil
    }

    private func responsivenessColor(_ rpm: Int) -> Color {
        switch rpm {
        case 0..<200: return .red
        case 200..<800: return .orange
        case 800..<1500: return .yellow
        default: return .green
        }
    }
}

// MARK: - Raw Metrics View (Technical Data)

struct RawMetricsView: View {
    let result: NetworkQualityResult
    let speedUnit: SpeedUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Main metrics
            HStack(spacing: 30) {
                MetricCard(
                    title: "Download",
                    value: speedUnit.formatBps(result.dlThroughput),
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )

                MetricCard(
                    title: "Upload",
                    value: speedUnit.formatBps(result.ulThroughput),
                    icon: "arrow.up.circle.fill",
                    color: .green
                )
            }

            HStack(spacing: 30) {
                if let rpm = result.responsivenessValue {
                    MetricCard(
                        title: "Responsiveness",
                        value: "\(rpm) RPM",
                        subtitle: result.responsivenessRating,
                        icon: "speedometer",
                        color: responsivenessColor(rpm)
                    )
                }

                if let rtt = result.baseRtt {
                    MetricCard(
                        title: "Base Latency",
                        value: String(format: "%.1f ms", rtt),
                        icon: "clock.fill",
                        color: .orange
                    )
                }
            }
        }
    }

    private func responsivenessColor(_ rpm: Int) -> Color {
        switch rpm {
        case 0..<200: return .red
        case 200..<800: return .orange
        case 800..<1500: return .yellow
        default: return .green
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title2)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DetailedMetricsSection: View {
    let result: NetworkQualityResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latency Details (Averages)")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                if let h2 = result.avgIdleH2ReqResp {
                    LatencyItem(title: "HTTP/2 Req/Resp", value: h2)
                }
                if let tcp = result.avgIdleTcpHandshake {
                    LatencyItem(title: "TCP Handshake", value: tcp)
                }
                if let tls = result.avgIdleTlsHandshake {
                    LatencyItem(title: "TLS Handshake", value: tls)
                }
            }

            if hasLoadedLatency {
                Text("Latency Under Load (Averages)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    if let foreign = result.avgLoadedH2ReqResp {
                        LatencyItem(title: "Foreign H2", value: foreign)
                    }
                    if let selfH2 = result.avgLoadedSelfH2ReqResp {
                        LatencyItem(title: "Self H2", value: selfH2)
                    }
                    if let tcp = result.avgLoadedTcpHandshake {
                        LatencyItem(title: "Foreign TCP", value: tcp)
                    }
                    if let tls = result.avgLoadedTlsHandshake {
                        LatencyItem(title: "Foreign TLS", value: tls)
                    }
                }
            }
        }
    }

    private var hasLoadedLatency: Bool {
        result.avgLoadedH2ReqResp != nil ||
        result.avgLoadedSelfH2ReqResp != nil ||
        result.avgLoadedTcpHandshake != nil ||
        result.avgLoadedTlsHandshake != nil
    }
}

struct LatencyItem: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f ms", value))
                .font(.system(.body, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ConnectionInfoSection: View {
    let result: NetworkQualityResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Rich network metadata (if available)
            if let metadata = result.networkMetadata {
                NetworkMetadataSection(metadata: metadata)
            }

            // Additional test info from JSON
            VStack(alignment: .leading, spacing: 12) {
                Text("Test Details")
                    .font(.headline)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    if let interface = result.interfaceName {
                        InfoItem(title: "Interface", value: interface)
                    }
                    if let dlFlows = result.dlFlows {
                        InfoItem(title: "Download Flows", value: "\(dlFlows)")
                    }
                    if let ulFlows = result.ulFlows {
                        InfoItem(title: "Upload Flows", value: "\(ulFlows)")
                    }
                    if let os = result.osVersion {
                        InfoItem(title: "OS Version", value: os)
                    }
                }

                if let startDate = result.startDate, let endDate = result.endDate {
                    HStack {
                        InfoItem(title: "Start", value: startDate)
                        InfoItem(title: "End", value: endDate)
                    }
                }

                if let errorCode = result.errorCode, let errorDomain = result.errorDomain {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Error: \(errorDomain) (\(errorCode))")
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct InfoItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct VerboseOutputSection: View {
    let output: [String]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Verbose Output (\(output.count) lines)")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(output.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    ResultsView(result: nil, verboseOutput: [])
        .frame(width: 600, height: 500)
}
