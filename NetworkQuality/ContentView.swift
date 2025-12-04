import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = NetworkQualityViewModel()
    @StateObject private var historyManager = HistoryManager()
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

                Section("Tools") {
                    Label("Network Tools", systemImage: "network")
                        .tag(4)
                    Label("Multi-Server", systemImage: "server.rack")
                        .tag(5)
                    Label("Route Map", systemImage: "map")
                        .tag(6)
                    Label("LAN Speed", systemImage: "wifi")
                        .tag(9)
                }

                Section("History") {
                    Label("Multi-Server History", systemImage: "clock.arrow.2.circlepath")
                        .tag(7)
                    Label("Tools History", systemImage: "doc.text.magnifyingglass")
                        .tag(8)
                    Label("LAN Speed History", systemImage: "clock.badge.checkmark")
                        .tag(10)
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
                    SpeedTestView(viewModel: viewModel, selectedTab: $selectedTab)
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
                case 4:
                    NetworkToolsView(historyManager: historyManager)
                case 5:
                    MultiServerTestView(historyManager: historyManager)
                case 6:
                    GeoTracerouteView()
                case 7:
                    MultiServerHistoryView(historyManager: historyManager)
                case 8:
                    NetworkToolsHistoryView(historyManager: historyManager)
                case 9:
                    LANSpeedTestView(historyManager: historyManager)
                case 10:
                    LANSpeedHistoryView(historyManager: historyManager)
                default:
                    Text("Select an option")
                }
            }
            .frame(minWidth: 680, minHeight: 300)
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
                // Only show main clear button for speed test history (tab 2)
                if selectedTab == 2 {
                    Button(action: { viewModel.clearHistory() }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(viewModel.results.isEmpty)
                }
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
    @Binding var selectedTab: Int
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        VStack(spacing: 16) {
            // Test mode picker at top
            Picker("", selection: $viewModel.testConfiguration.mode) {
                Text("Parallel").tag(TestMode.parallel)
                Text("Sequential").tag(TestMode.sequential)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(viewModel.isRunning)
            .padding(.top, 12)

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
                        .frame(width: 50, height: 50)

                    if viewModel.isRunning {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                            .frame(width: 44, height: 44)

                        // Use TimelineView for smooth continuous animation
                        TimelineView(.animation) { timeline in
                            let seconds = timeline.date.timeIntervalSinceReferenceDate
                            Circle()
                                .trim(from: 0, to: 0.3)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 44, height: 44)
                                .rotationEffect(.degrees(seconds * 90))
                        }

                        Text(String(format: "%.0fs", viewModel.service.elapsedTime))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            // Speed gauges
            HStack(spacing: 50) {
                SpeedGaugeView(
                    title: "Download",
                    speed: viewModel.isRunning ?
                        viewModel.currentDownloadSpeed :
                        (viewModel.currentResult?.downloadSpeedMbps ?? 0),
                    maxSpeed: max(viewModel.maxDownloadSpeed, 1000),
                    color: .blue,
                    icon: "arrow.down.circle.fill",
                    speedUnit: speedUnit,
                    showTitle: false,
                    size: 130
                )

                SpeedGaugeView(
                    title: "Upload",
                    speed: viewModel.isRunning ?
                        viewModel.currentUploadSpeed :
                        (viewModel.currentResult?.uploadSpeedMbps ?? 0),
                    maxSpeed: max(viewModel.maxUploadSpeed, 1000),
                    color: .green,
                    icon: "arrow.up.circle.fill",
                    speedUnit: speedUnit,
                    showTitle: false,
                    size: 130
                )
            }

            Spacer()

            // Stats row
            if let result = viewModel.currentResult, !viewModel.isRunning {
                HStack(spacing: 20) {
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

                // Insight summary with link to details
                Button {
                    selectedTab = 1
                } label: {
                    HStack {
                        CompactInsightSummary(result: result)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .help("View detailed insights and bufferbloat analysis")
            }

            Spacer()
                .frame(height: 8)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentResult?.id)
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
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct HistoryView: View {
    let results: [NetworkQualityResult]
    @ObservedObject var viewModel: NetworkQualityViewModel
    @State private var exportPresented = false
    @State private var selectedResult: NetworkQualityResult?

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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedResult = result
                            }
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
            ExportSheet(viewModel: viewModel)
        }
        .sheet(item: $selectedResult) { result in
            HistoryDetailSheet(result: result, allResults: results)
        }
    }
}

struct HistoryDetailSheet: View {
    let result: NetworkQualityResult
    var allResults: [NetworkQualityResult] = []
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with date/time and speeds
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.timestamp, style: .date)
                                .font(.title2.weight(.semibold))
                            Text(result.timestamp, style: .time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 20) {
                            VStack(alignment: .trailing) {
                                Text(speedUnit.formatBps(result.dlThroughput))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.blue)
                                Text("Download")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .trailing) {
                                Text(speedUnit.formatBps(result.ulThroughput))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.green)
                                Text("Upload")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Network metadata section
                    if let metadata = result.networkMetadata {
                        NetworkMetadataSection(metadata: metadata)
                    }

                    // Full insights view
                    InsightsView(result: result)
                }
                .padding()
            }
            .navigationTitle("Test Details")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { @MainActor in
                            PDFReportService.shared.saveReport(for: result, history: allResults)
                        }
                    } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

struct NetworkMetadataSection: View {
    let metadata: NetworkMetadata
    @ObservedObject private var locationManager = LocationPermissionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: metadata.connectionType.icon)
                    .foregroundStyle(.blue)
                Text("Connection Info")
                    .font(.headline)
                Spacer()
                Text(metadata.connectionType.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Connection details grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                // Interface
                MetadataItem(label: "Interface", value: metadata.interfaceName)

                // IP Address
                if let ip = metadata.localIPAddress {
                    MetadataItem(label: "IP Address", value: ip)
                }

                // WiFi-specific info
                if metadata.connectionType == .wifi {
                    if let ssid = metadata.wifiSSID {
                        MetadataItem(label: "Network", value: ssid)
                    } else {
                        // No SSID - show button to request permission
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Network")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                locationManager.requestPermission()
                            } label: {
                                Label("Enable WiFi Name", systemImage: "location")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let rssi = metadata.wifiRSSI, let quality = metadata.signalQuality {
                        MetadataItem(
                            label: "Signal",
                            value: "\(quality) (\(rssi) dBm)",
                            valueColor: signalColor(rssi)
                        )
                    }

                    if let channel = metadata.wifiChannel, let band = metadata.wifiBand {
                        MetadataItem(label: "Channel", value: "\(channel) (\(band.rawValue))")
                    }

                    if let txRate = metadata.wifiTxRate {
                        MetadataItem(label: "Link Speed", value: String(format: "%.0f Mbps", txRate))
                    }

                    if let security = metadata.wifiSecurity, security != .unknown {
                        MetadataItem(label: "Security", value: security.rawValue)
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func signalColor(_ rssi: Int) -> Color {
        switch rssi {
        case -50...0: return .green
        case -60..<(-50): return .blue
        case -70..<(-60): return .orange
        default: return .red
        }
    }
}

struct MetadataItem: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(.body, design: .rounded))
        }
        .padding(.vertical, 4)
    }
}

enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case json = "JSON"
    case pdf = "PDF"

    var fileExtension: String {
        rawValue.lowercased()
    }

    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .pdf: return .pdf
        }
    }
}

struct ExportSheet: View {
    @ObservedObject var viewModel: NetworkQualityViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .csv
    @State private var copiedFeedback = false

    private var exportContent: String {
        switch selectedFormat {
        case .csv: return viewModel.exportResultsCSV()
        case .json: return viewModel.exportResultsJSON()
        case .pdf: return "PDF report includes speed results, insights, and historical trends.\n\nClick 'Save to File...' to generate the PDF."
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Export Results")
                    .font(.headline)

                Spacer()

                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            if selectedFormat == .pdf {
                // PDF preview
                VStack(spacing: 16) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("PDF Report")
                        .font(.title2.weight(.semibold))

                    Text("Generate a branded PDF report with:\n- Speed test results\n- Quality metrics and ratings\n- Network connection details\n- Recommendations and insights\n- Historical trends (\(viewModel.results.count) tests)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    Text(exportContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                if selectedFormat != .pdf {
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            Text(copiedFeedback ? "Copied!" : "Copy to Clipboard")
                        }
                    }
                }

                Button("Save to File...") {
                    saveToFile()
                }

                Spacer()

                Text("\(viewModel.results.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 450)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportContent, forType: .string)
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedFeedback = false
        }
    }

    private func saveToFile() {
        if selectedFormat == .pdf {
            savePDF()
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [selectedFormat.contentType]
            panel.nameFieldStringValue = "network-quality-results.\(selectedFormat.fileExtension)"

            if panel.runModal() == .OK, let url = panel.url {
                try? exportContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func savePDF() {
        guard let latestResult = viewModel.results.last else { return }
        Task { @MainActor in
            PDFReportService.shared.saveReport(for: latestResult, history: viewModel.results)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
