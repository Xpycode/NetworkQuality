import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = NetworkQualityViewModel()
    @State private var selectedTab = 0
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedTab) {
                Section("Test") {
                    Label("Speed Test", systemImage: "speedometer")
                        .tag(0)
                    Label("Results", systemImage: "list.bullet.clipboard")
                        .tag(1)
                }

                Section("Analytics") {
                    Label("Speed Graph", systemImage: "chart.xyaxis.line")
                        .tag(2)
                    Label("History", systemImage: "clock")
                        .tag(3)
                }

                Section("Options") {
                    Label("Settings", systemImage: "gear")
                        .tag(4)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            // Main content
            Group {
                switch selectedTab {
                case 0:
                    SpeedTestView(viewModel: viewModel)
                case 1:
                    ResultsView(
                        result: viewModel.currentResult,
                        verboseOutput: viewModel.verboseOutput
                    )
                case 2:
                    VStack(spacing: 20) {
                        SpeedGraphView(
                            speedHistory: viewModel.speedHistory,
                            averageDownload: viewModel.averageDownloadSpeed,
                            averageUpload: viewModel.averageUploadSpeed,
                            maxDownload: viewModel.maxDownloadSpeed,
                            maxUpload: viewModel.maxUploadSpeed
                        )

                        LatencyComparisonView(result: viewModel.currentResult)
                    }
                    .padding()
                case 3:
                    HistoryView(results: viewModel.results, viewModel: viewModel)
                case 4:
                    SettingsView(
                        config: $viewModel.testConfiguration,
                        availableInterfaces: viewModel.availableInterfaces
                    )
                default:
                    Text("Select an option")
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .navigationTitle("Network Quality")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isRunning {
                    Button(action: { viewModel.cancelTest() }) {
                        Label("Cancel", systemImage: "stop.circle.fill")
                    }
                    .tint(.red)
                } else {
                    Button(action: {
                        Task {
                            await viewModel.runTest()
                        }
                    }) {
                        Label("Run Test", systemImage: "play.circle.fill")
                    }
                    .tint(.green)
                }

                Button(action: { viewModel.clearHistory() }) {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(viewModel.results.isEmpty)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
}

struct SpeedTestView: View {
    @ObservedObject var viewModel: NetworkQualityViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Status indicator
                if viewModel.isRunning {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(viewModel.progress)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                }

                // Speed gauges
                HStack(spacing: 40) {
                    SpeedGaugeView(
                        title: "Download",
                        speed: viewModel.isRunning ?
                            viewModel.currentDownloadSpeed :
                            (viewModel.currentResult?.downloadSpeedMbps ?? 0),
                        maxSpeed: max(viewModel.maxDownloadSpeed, 1000),
                        color: .blue,
                        icon: "arrow.down.circle.fill"
                    )

                    SpeedGaugeView(
                        title: "Upload",
                        speed: viewModel.isRunning ?
                            viewModel.currentUploadSpeed :
                            (viewModel.currentResult?.uploadSpeedMbps ?? 0),
                        maxSpeed: max(viewModel.maxUploadSpeed, 1000),
                        color: .green,
                        icon: "arrow.up.circle.fill"
                    )
                }
                .padding()

                // Responsiveness and Latency
                HStack(spacing: 20) {
                    ResponsivenessGaugeView(
                        rpm: viewModel.currentResult?.responsivenessValue
                    )
                    .frame(maxWidth: .infinity)

                    LatencyGaugeView(latency: viewModel.currentResult?.baseRtt)
                        .frame(maxWidth: 200)
                }
                .padding(.horizontal)

                // Quick stats
                if let result = viewModel.currentResult {
                    QuickStatsView(result: result)
                }

                // Test info
                TestInfoView(config: viewModel.testConfiguration)

                Spacer()
            }
            .padding()
        }
    }
}

struct QuickStatsView: View {
    let result: NetworkQualityResult

    var body: some View {
        GroupBox("Test Results") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                QuickStatItem(
                    title: "Download",
                    value: result.formattedDownloadSpeed,
                    icon: "arrow.down",
                    color: .blue
                )
                QuickStatItem(
                    title: "Upload",
                    value: result.formattedUploadSpeed,
                    icon: "arrow.up",
                    color: .green
                )
                QuickStatItem(
                    title: "Latency",
                    value: result.baseRtt.map { String(format: "%.1f ms", $0) } ?? "N/A",
                    icon: "clock",
                    color: .orange
                )
                QuickStatItem(
                    title: "Interface",
                    value: result.interfaceName ?? "N/A",
                    icon: "network",
                    color: .purple
                )
            }
        }
    }
}

struct QuickStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .rounded, weight: .medium))
            }
        }
    }
}

struct TestInfoView: View {
    let config: TestConfiguration

    var body: some View {
        GroupBox("Test Configuration") {
            HStack(spacing: 20) {
                Label(config.mode.rawValue, systemImage: "arrow.left.arrow.right")
                Label(config.protocolSelection.rawValue, systemImage: "network")
                if !config.networkInterface.isEmpty {
                    Label(config.networkInterface, systemImage: "antenna.radiowaves.left.and.right")
                }
                if config.usePrivateRelay {
                    Label("Private Relay", systemImage: "lock.shield")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct HistoryView: View {
    let results: [NetworkQualityResult]
    @ObservedObject var viewModel: NetworkQualityViewModel
    @State private var exportPresented = false

    var body: some View {
        VStack {
            if results.isEmpty {
                ContentUnavailableView(
                    "No Test History",
                    systemImage: "clock",
                    description: Text("Run speed tests to build history")
                )
            } else {
                List {
                    ForEach(results.reversed()) { result in
                        HistoryRow(result: result)
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { exportPresented = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(results.isEmpty)
            }
        }
        .sheet(isPresented: $exportPresented) {
            ExportSheet(jsonContent: viewModel.exportResults())
        }
    }
}

struct HistoryRow: View {
    let result: NetworkQualityResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.timestamp, style: .date)
                    .font(.headline)
                Text(result.timestamp, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 20) {
                VStack(alignment: .trailing) {
                    Text("Download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.formattedDownloadSpeed)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .trailing) {
                    Text("Upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.formattedUploadSpeed)
                        .foregroundStyle(.green)
                }

                if let rpm = result.responsiveness {
                    VStack(alignment: .trailing) {
                        Text("RPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(rpm)")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.system(.body, design: .rounded))
        }
        .padding(.vertical, 4)
    }
}

struct ExportSheet: View {
    let jsonContent: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Results")
                .font(.headline)

            ScrollView {
                Text(jsonContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonContent, forType: .string)
                }

                Button("Save to File") {
                    saveToFile()
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "network-quality-results.json"

        if panel.runModal() == .OK, let url = panel.url {
            try? jsonContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
