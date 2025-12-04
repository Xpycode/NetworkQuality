import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = NetworkQualityViewModel()
    @StateObject private var historyManager = HistoryManager()
    @State private var selectedTab = 0
    @State private var showSettings = false
    @State private var showExportSheet = false
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    var body: some View {
        HStack(spacing: 0) {
            // Static sidebar
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
                    Label("Diagnostics", systemImage: "network")
                        .tag(4)
                    Label("Multi-Server", systemImage: "server.rack")
                        .tag(5)
                    Label("Route Map", systemImage: "map")
                        .tag(6)
                    Label("LAN Speed", systemImage: "wifi")
                        .tag(9)
                    Label("VPN Compare", systemImage: "network.badge.shield.half.filled")
                        .tag(11)
                }

                Section("History") {
                    Label("Multi-Server", systemImage: "clock.arrow.2.circlepath")
                        .tag(7)
                    Label("Diagnostics", systemImage: "doc.text.magnifyingglass")
                        .tag(8)
                    Label("LAN Speed", systemImage: "clock.badge.checkmark")
                        .tag(10)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

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
                case 11:
                    VPNComparisonView()
                default:
                    Text("Select an option")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                // Show clear button for history tab
                if selectedTab == 2 {
                    Button(action: { viewModel.clearHistory() }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(viewModel.results.isEmpty)
                }

                // Show Share button for Results tab
                if selectedTab == 1 {
                    Button(action: { showExportSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.currentResult == nil)
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(viewModel: viewModel)
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
            HistoryDetailSheet(result: result, allResults: results, viewModel: viewModel)
        }
    }
}

struct HistoryDetailSheet: View {
    let result: NetworkQualityResult
    var allResults: [NetworkQualityResult] = []
    @ObservedObject var viewModel: NetworkQualityViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue
    @State private var showShareSheet = false

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
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ExportSheet(viewModel: viewModel, specificResult: result)
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

enum ShareOption: String, CaseIterable, Identifiable {
    case image = "Share Card"
    case pdf = "PDF Report"
    case csv = "CSV Data"
    case json = "JSON Data"
    case text = "Text Summary"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .text: return "text.alignleft"
        }
    }

    var description: String {
        switch self {
        case .image: return "Visual card for social sharing"
        case .pdf: return "Branded report with insights"
        case .csv: return "Spreadsheet-compatible format"
        case .json: return "Developer-friendly format"
        case .text: return "Plain text summary"
        }
    }

    var canCopy: Bool {
        switch self {
        case .image, .csv, .json, .text: return true
        case .pdf: return false
        }
    }

    var fileExtension: String {
        switch self {
        case .image: return "png"
        case .pdf: return "pdf"
        case .csv: return "csv"
        case .json: return "json"
        case .text: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .image: return .png
        case .pdf: return .pdf
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .text: return .plainText
        }
    }
}

struct ExportSheet: View {
    @ObservedObject var viewModel: NetworkQualityViewModel
    var specificResult: NetworkQualityResult? = nil  // If set, share this specific result
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: ShareOption = .image
    @State private var copiedFeedback = false
    @State private var cardImage: NSImage?

    private var currentResult: NetworkQualityResult? {
        specificResult ?? viewModel.results.last
    }

    private var resultsForExport: [NetworkQualityResult] {
        if specificResult != nil {
            return [specificResult!]
        }
        return viewModel.results
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 4) {
                Text("Share & Export")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                ForEach(ShareOption.allCases) { option in
                    sidebarButton(option)
                }

                Spacer()

                if specificResult != nil {
                    Text("1 test selected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                } else {
                    Text("\(viewModel.results.count) results")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 16)
            .frame(width: 160)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content area
            VStack(spacing: 16) {
                // Preview
                previewArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Action buttons
                HStack {
                    if selectedOption.canCopy {
                        Button {
                            copyToClipboard()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                                Text(copiedFeedback ? "Copied!" : "Copy")
                            }
                        }
                    }

                    Button("Save...") {
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
        }
        .frame(width: 700, height: 500)
        .onAppear {
            generateCardImage()
        }
        .onChange(of: selectedOption) { _, _ in
            if selectedOption == .image {
                generateCardImage()
            }
        }
    }

    private func sidebarButton(_ option: ShareOption) -> some View {
        Button {
            selectedOption = option
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    Text(option.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedOption == option ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var previewArea: some View {
        switch selectedOption {
        case .image:
            imagePreview
        case .pdf:
            pdfPreview
        case .csv:
            textPreview(content: exportCSV())
        case .json:
            textPreview(content: exportJSON())
        case .text:
            textPreview(content: textSummary)
        }
    }

    private var imagePreview: some View {
        VStack(spacing: 16) {
            if let image = cardImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else if let result = currentResult {
                ShareableResultCardView(result: result)
                    .scaleEffect(0.6)
            } else {
                noResultsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var pdfPreview: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("PDF Report")
                .font(.title2.weight(.semibold))

            Text("Generate a branded PDF report with:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label("Speed test results", systemImage: "gauge.with.dots.needle.bottom.50percent")
                Label("Quality metrics and ratings", systemImage: "star")
                Label("Network connection details", systemImage: "wifi")
                Label("Recommendations and insights", systemImage: "lightbulb")
                if resultsForExport.count > 1 {
                    Label("Historical trends (\(resultsForExport.count) tests)", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func textPreview(content: String) -> some View {
        ScrollView {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Results")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Run a test first")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private var textSummary: String {
        guard let result = currentResult else { return "No results available" }

        var text = "Network Quality Test Results\n"
        text += "============================\n\n"
        text += "Download: \(SpeedUnit.mbps.formatBps(result.dlThroughput))\n"
        text += "Upload: \(SpeedUnit.mbps.formatBps(result.ulThroughput))\n"

        if let rpm = result.responsivenessValue {
            text += "Responsiveness: \(rpm) RPM (\(result.responsivenessRating))\n"
        }

        if let rtt = result.baseRtt {
            text += "Latency: \(String(format: "%.1f", rtt)) ms\n"
        }

        text += "\nTested: \(result.timestamp.formatted())\n"
        text += "Tested with NetworkQuality app"

        return text
    }

    private func generateCardImage() {
        guard let result = currentResult else { return }
        Task { @MainActor in
            let cardView = ShareableResultCardView(result: result)
            let renderer = ImageRenderer(content: cardView)
            renderer.scale = 2.0
            if let cgImage = renderer.cgImage {
                cardImage = NSImage(cgImage: cgImage, size: NSSize(width: 440, height: 520))
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch selectedOption {
        case .image:
            if let image = cardImage {
                pasteboard.writeObjects([image])
            }
        case .csv:
            pasteboard.setString(exportCSV(), forType: .string)
        case .json:
            pasteboard.setString(exportJSON(), forType: .string)
        case .text:
            pasteboard.setString(textSummary, forType: .string)
        case .pdf:
            return
        }

        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedFeedback = false
        }
    }

    private func exportCSV() -> String {
        if specificResult != nil, let result = currentResult {
            // Export single result
            return viewModel.exportSingleResultCSV(result)
        }
        return viewModel.exportResultsCSV()
    }

    private func exportJSON() -> String {
        if specificResult != nil, let result = currentResult {
            // Export single result
            return viewModel.exportSingleResultJSON(result)
        }
        return viewModel.exportResultsJSON()
    }

    private func saveToFile() {
        switch selectedOption {
        case .image:
            if let result = currentResult {
                Task { @MainActor in
                    ShareService.shared.saveResultCard(result: result)
                }
            }
        case .pdf:
            if let result = currentResult {
                Task { @MainActor in
                    PDFReportService.shared.saveReport(for: result, history: resultsForExport)
                }
            }
        case .csv, .json, .text:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [selectedOption.contentType]
            panel.nameFieldStringValue = "network-quality.\(selectedOption.fileExtension)"

            if panel.runModal() == .OK, let url = panel.url {
                let content: String
                switch selectedOption {
                case .csv: content = exportCSV()
                case .json: content = exportJSON()
                case .text: content = textSummary
                default: return
                }
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
