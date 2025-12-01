import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = NetworkQualityViewModel()
    @State private var selectedTab = 0
    @State private var showSettings = false
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedTab) {
                Section("Test") {
                    Label("Speed Test", systemImage: "speedometer")
                        .tag(0)
                    Label("Results", systemImage: "list.bullet.clipboard")
                        .tag(1)
                    Label("History", systemImage: "clock")
                        .tag(2)
                }

                Section("Options") {
                    Label("Settings", systemImage: "gear")
                        .tag(3)
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
                    HistoryView(results: viewModel.results, viewModel: viewModel)
                case 3:
                    SettingsView(
                        config: $viewModel.testConfiguration,
                        availableInterfaces: viewModel.availableInterfaces
                    )
                default:
                    Text("Select an option")
                }
            }
            .frame(minWidth: 500, minHeight: 300)
        }
        .navigationTitle("Network Quality")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Unit", selection: $speedUnitRaw) {
                    ForEach(SpeedUnit.allCases, id: \.rawValue) { unit in
                        Text(unit.label).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

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
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Speed gauges
            HStack(spacing: 30) {
                SpeedGaugeView(
                    title: "Download",
                    speed: viewModel.isRunning ?
                        viewModel.currentDownloadSpeed :
                        (viewModel.currentResult?.downloadSpeedMbps ?? 0),
                    maxSpeed: max(viewModel.maxDownloadSpeed, 1000),
                    color: .blue,
                    icon: "arrow.down.circle.fill",
                    speedUnit: speedUnit
                )

                SpeedGaugeView(
                    title: "Upload",
                    speed: viewModel.isRunning ?
                        viewModel.currentUploadSpeed :
                        (viewModel.currentResult?.uploadSpeedMbps ?? 0),
                    maxSpeed: max(viewModel.maxUploadSpeed, 1000),
                    color: .green,
                    icon: "arrow.up.circle.fill",
                    speedUnit: speedUnit
                )
            }
            .padding(.horizontal)

            // Start/Stop button with progress
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
                    // Background circle
                    Circle()
                        .fill(viewModel.isRunning ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)

                    if viewModel.isRunning {
                        // Indeterminate progress ring (continuous rotation)
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 74, height: 74)

                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 74, height: 74)
                            .rotationEffect(.degrees(viewModel.service.elapsedTime * 90))
                            .animation(.linear(duration: 0.1), value: viewModel.service.elapsedTime)

                        // Elapsed time
                        Text(String(format: "%.0fs", viewModel.service.elapsedTime))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            // Test mode picker
            Picker("", selection: $viewModel.testConfiguration.mode) {
                Text("Parallel").tag(TestMode.parallel)
                Text("Sequential").tag(TestMode.sequential)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(viewModel.isRunning)

            Spacer()

            // Stats row (always reserve space, show when test completes)
            HStack(spacing: 24) {
                if let result = viewModel.currentResult, !viewModel.isRunning {
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
                }
            }
            .frame(height: 36)
            .padding(.bottom, 12)
        }
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
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
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
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

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

            HStack(spacing: 16) {
                VStack(alignment: .trailing) {
                    Text("Download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(speedUnit.formatBps(result.dlThroughput))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .trailing) {
                    Text("Upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(speedUnit.formatBps(result.ulThroughput))
                        .foregroundStyle(.green)
                }

                if let latency = result.baseRtt {
                    VStack(alignment: .trailing) {
                        Text("Latency")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f ms", latency))
                            .foregroundStyle(.orange)
                    }
                }

                if let rpm = result.responsivenessValue {
                    VStack(alignment: .trailing) {
                        Text("RPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(rpm)")
                            .foregroundStyle(.purple)
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
