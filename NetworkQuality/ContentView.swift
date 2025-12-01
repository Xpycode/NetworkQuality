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
                    SpeedGraphView(
                        speedHistory: viewModel.speedHistory,
                        averageDownload: viewModel.averageDownloadSpeed,
                        averageUpload: viewModel.averageUploadSpeed,
                        maxDownload: viewModel.maxDownloadSpeed,
                        maxUpload: viewModel.maxUploadSpeed
                    )
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
                Button(action: { viewModel.clearHistory() }) {
                    Label("Clear", systemImage: "trash")
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
        VStack(spacing: 20) {
            // Speed gauges
            HStack(spacing: 30) {
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
            .padding(.horizontal)

            // Compact stats row (only show after test completes)
            if let result = viewModel.currentResult, !viewModel.isRunning {
                HStack(spacing: 24) {
                    StatPill(
                        icon: "clock",
                        label: "Latency",
                        value: result.baseRtt.map { String(format: "%.0f ms", $0) } ?? "N/A",
                        color: .orange
                    )
                    StatPill(
                        icon: "gauge.with.dots.needle.67percent",
                        label: "RPM",
                        value: result.responsivenessValue.map { "\($0)" } ?? "N/A",
                        color: .purple
                    )
                    if let iface = result.interfaceName {
                        StatPill(icon: "network", label: "Interface", value: iface, color: .gray)
                    }
                }
                .padding(.horizontal)
            }

            // Start/Stop button
            Button(action: {
                if viewModel.isRunning {
                    viewModel.cancelTest()
                } else {
                    Task {
                        await viewModel.runTest()
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRunning ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)

                    if viewModel.isRunning {
                        ProgressView()
                            .scaleEffect(1.5)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.top)
    }
}

struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
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
