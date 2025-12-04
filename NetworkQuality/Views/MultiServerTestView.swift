import SwiftUI
import Combine
import AppKit

// Shared state to persist across tab switches
@MainActor
class MultiServerTestState: ObservableObject {
    static let shared = MultiServerTestState()

    let coordinator = MultiServerTestCoordinator()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Forward coordinator changes to trigger UI updates
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

struct MultiServerTestView: View {
    @ObservedObject private var state = MultiServerTestState.shared
    @ObservedObject var historyManager: HistoryManager
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue
    @AppStorage("appleSequentialMode") private var appleSequentialMode = false
    @State private var lastSavedResultCount = 0

    private var coordinator: MultiServerTestCoordinator { state.coordinator }
    private var speedUnit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mbps }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with Run All button
                headerSection

                // Provider cards
                providerCardsSection

                // Comparison section (when results available)
                if !coordinator.results.isEmpty {
                    comparisonSection
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .onChange(of: coordinator.isRunning) { _, isRunning in
            // Save to history when all tests complete
            if !isRunning && coordinator.results.count >= 3 && coordinator.results.count != lastSavedResultCount {
                historyManager.saveMultiServerResult(coordinator.results)
                lastSavedResultCount = coordinator.results.count
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Multi-Server Testing")
                    .font(.title2.bold())
            }

            Text("Compare speeds across Apple, Cloudflare, and M-Lab servers to identify routing issues or throttling")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Run All Tests / Stop button
            Button {
                if coordinator.isRunning {
                    coordinator.stopAllTests()
                } else {
                    coordinator.runAllTests()
                }
            } label: {
                HStack {
                    Image(systemName: coordinator.isRunning ? "stop.fill" : "play.fill")
                    Text(coordinator.isRunning ? "Stop" : "Run All Tests")
                }
                .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .tint(coordinator.isRunning ? .red : .blue)
            .controlSize(.large)

        }
        .padding(.bottom, 10)
    }

    // MARK: - Provider Cards Section

    private var providerCardsSection: some View {
        HStack(spacing: 16) {
            ForEach(coordinator.availableProviders, id: \.name) { provider in
                ProviderCard(
                    name: provider.name,
                    icon: provider.icon,
                    progress: coordinator.progress[provider.name],
                    result: coordinator.results.first { $0.provider == provider.name },
                    isCurrentlyTesting: coordinator.currentProvider == provider.name,
                    speedUnit: speedUnit,
                    sequentialMode: provider.name == "Apple" ? $appleSequentialMode : nil,
                    isSequentialOnly: provider.name != "Apple",
                    onTest: {
                        coordinator.runSingleTest(providerName: provider.name)
                    }
                )
                .disabled(coordinator.isRunning)
            }
        }
    }

    // MARK: - Comparison Section

    private var comparisonSection: some View {
        VStack(spacing: 16) {
            Divider()

            HStack {
                Text("Results Comparison")
                    .font(.headline)

                Spacer()

                // Share menu
                Menu {
                    Button {
                        copyImageFeedback = MultiServerShareService.shared.copyToClipboard(results: coordinator.results)
                    } label: {
                        Label("Copy Image", systemImage: "doc.on.doc")
                    }

                    Button {
                        MultiServerShareService.shared.saveCard(results: coordinator.results)
                    } label: {
                        Label("Save Image", systemImage: "square.and.arrow.down")
                    }

                    Divider()

                    Button {
                        MultiServerShareService.shared.savePDFReport(results: coordinator.results)
                    } label: {
                        Label("Export PDF Report", systemImage: "doc.richtext")
                    }

                    Divider()

                    Button {
                        let text = MultiServerShareService.shared.textSummary(results: coordinator.results, speedUnit: speedUnit)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copyTextFeedback = true
                    } label: {
                        Label("Copy Text Summary", systemImage: "doc.plaintext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
                .overlay(alignment: .trailing) {
                    if copyImageFeedback {
                        Text("Copied!")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .offset(x: 50)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copyImageFeedback = false
                                }
                            }
                    }
                    if copyTextFeedback {
                        Text("Copied!")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .offset(x: 50)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copyTextFeedback = false
                                }
                            }
                    }
                }
            }

            // Speed comparison bars
            SpeedComparisonChart(results: coordinator.results, speedUnit: speedUnit)

            // Summary table
            ComparisonTable(results: coordinator.results, speedUnit: speedUnit)
        }
    }

    @State private var copyImageFeedback = false
    @State private var copyTextFeedback = false
}

// MARK: - Provider Card

struct ProviderCard: View {
    let name: String
    let icon: String
    let progress: SpeedTestProgress?
    let result: SpeedTestResult?
    let isCurrentlyTesting: Bool
    let speedUnit: SpeedUnit
    var sequentialMode: Binding<Bool>?
    var isSequentialOnly: Bool = false
    let onTest: () -> Void

    private var providerColor: Color {
        switch name {
        case "Apple": return .blue
        case "Cloudflare": return .orange
        case "M-Lab": return .green
        default: return .gray
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Provider header
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(providerColor)
                Text(name)
                    .font(.headline)
            }

            // Mode indicator
            if let binding = sequentialMode {
                Picker("", selection: binding) {
                    Text("Parallel").tag(false)
                    Text("Sequential").tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            } else if isSequentialOnly {
                Text("Sequential only")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // Content based on state
            if isCurrentlyTesting, let progress = progress {
                testingView(progress: progress)
            } else if let result = result {
                resultView(result: result)
            } else {
                idleView
            }

            // Test button
            Button(action: onTest) {
                Text(result != nil ? "Retest" : "Test")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(providerColor)
            .disabled(isCurrentlyTesting)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentlyTesting ? providerColor : Color.clear, lineWidth: 2)
        )
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Ready to test")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 100)
    }

    private func testingView(progress: SpeedTestProgress) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: progress.progress)
                .progressViewStyle(.linear)

            Text(progress.phase.rawValue)
                .font(.caption.bold())
                .foregroundStyle(providerColor)

            // Show both speeds for parallel testing (Apple)
            if progress.phase == .parallel,
               let download = progress.downloadSpeed, download > 0 {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(formatSpeed(download))
                                .font(.system(.body, design: .rounded, weight: .bold))
                        }
                    }

                    if let upload = progress.uploadSpeed, upload > 0 {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text(formatSpeed(upload))
                                    .font(.system(.body, design: .rounded, weight: .bold))
                            }
                        }
                    }
                }
                .foregroundStyle(providerColor)
            } else if let speed = progress.currentSpeed, speed > 0 {
                Text(formatSpeed(speed))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(providerColor)
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .frame(height: 100)
    }

    private func resultView(result: SpeedTestResult) -> some View {
        VStack(spacing: 8) {
            if result.isSuccess {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Text(formatSpeed(result.downloadSpeed))
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("Download")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                        Text(formatSpeed(result.uploadSpeed))
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("Upload")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let latency = result.latency {
                    Text(String(format: "%.0f ms latency", latency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let location = result.serverLocation {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                    Text(result.error ?? "Test failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(height: 100)
    }

    private func formatSpeed(_ mbps: Double) -> String {
        let formatted = speedUnit.format(mbps)
        return "\(formatted.value) \(formatted.unit)"
    }
}

// MARK: - Speed Comparison Chart

struct SpeedComparisonChart: View {
    let results: [SpeedTestResult]
    let speedUnit: SpeedUnit

    private var maxSpeed: Double {
        let allSpeeds = results.flatMap { [$0.downloadSpeed, $0.uploadSpeed] }
        return max(allSpeeds.max() ?? 100, 10)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Download comparison
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    Text("Download Speed")
                        .font(.subheadline.bold())
                }

                ForEach(results.sorted(by: { $0.downloadSpeed > $1.downloadSpeed })) { result in
                    SpeedBar(
                        label: result.provider,
                        speed: result.downloadSpeed,
                        maxSpeed: maxSpeed,
                        color: providerColor(result.provider),
                        speedUnit: speedUnit
                    )
                }
            }

            // Upload comparison
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Upload Speed")
                        .font(.subheadline.bold())
                }

                ForEach(results.sorted(by: { $0.uploadSpeed > $1.uploadSpeed })) { result in
                    SpeedBar(
                        label: result.provider,
                        speed: result.uploadSpeed,
                        maxSpeed: maxSpeed,
                        color: providerColor(result.provider),
                        speedUnit: speedUnit
                    )
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func providerColor(_ name: String) -> Color {
        switch name {
        case "Apple": return .blue
        case "Cloudflare": return .orange
        case "M-Lab": return .green
        default: return .gray
        }
    }
}

struct SpeedBar: View {
    let label: String
    let speed: Double
    let maxSpeed: Double
    let color: Color
    let speedUnit: SpeedUnit

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 70, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: max(0, geo.size.width * CGFloat(speed / maxSpeed)))
                }
            }
            .frame(height: 20)

            Text(formatSpeed(speed))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
        }
    }

    private func formatSpeed(_ mbps: Double) -> String {
        let formatted = speedUnit.format(mbps)
        return "\(formatted.value) \(formatted.unit)"
    }
}

// MARK: - Comparison Table

struct ComparisonTable: View {
    let results: [SpeedTestResult]
    let speedUnit: SpeedUnit

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Provider")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Download")
                    .frame(width: 90, alignment: .trailing)
                Text("Upload")
                    .frame(width: 90, alignment: .trailing)
                Text("Latency")
                    .frame(width: 70, alignment: .trailing)
                Text("Server")
                    .frame(width: 120, alignment: .trailing)
            }
            .font(.caption.bold())
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.1))

            // Rows
            ForEach(results) { result in
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: providerIcon(result.provider))
                            .font(.system(size: 10))
                            .foregroundStyle(providerColor(result.provider))
                            .frame(width: 12)
                        Text(result.provider)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(result.isSuccess ? formatSpeed(result.downloadSpeed) : "-")
                        .frame(width: 90, alignment: .trailing)
                        .foregroundStyle(result.isSuccess ? .primary : .secondary)

                    Text(result.isSuccess ? formatSpeed(result.uploadSpeed) : "-")
                        .frame(width: 90, alignment: .trailing)
                        .foregroundStyle(result.isSuccess ? .primary : .secondary)

                    Text(result.latency.map { String(format: "%.0f ms", $0) } ?? "-")
                        .frame(width: 70, alignment: .trailing)
                        .foregroundStyle(.secondary)

                    Text(result.serverLocation ?? "-")
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

                if result.id != results.last?.id {
                    Divider()
                }
            }
        }
        .background(Color.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func providerIcon(_ name: String) -> String {
        switch name {
        case "Apple": return "apple.logo"
        case "Cloudflare": return "cloud.fill"
        case "M-Lab": return "globe.americas.fill"
        default: return "server.rack"
        }
    }

    private func providerColor(_ name: String) -> Color {
        switch name {
        case "Apple": return .blue
        case "Cloudflare": return .orange
        case "M-Lab": return .green
        default: return .gray
        }
    }

    private func formatSpeed(_ mbps: Double) -> String {
        let formatted = speedUnit.format(mbps)
        return "\(formatted.value) \(formatted.unit)"
    }
}

// MARK: - Analysis View

struct AnalysisView: View {
    let results: [SpeedTestResult]

    private var analysis: (verdict: String, details: String, color: Color) {
        let successfulResults = results.filter { $0.isSuccess }
        guard successfulResults.count >= 2 else {
            return ("Insufficient Data", "Run tests on at least 2 servers to compare results", .secondary)
        }

        let downloads = successfulResults.map { $0.downloadSpeed }
        let avgDownload = downloads.reduce(0, +) / Double(downloads.count)
        let maxDownload = downloads.max() ?? 0
        let minDownload = downloads.min() ?? 0

        let variance = (maxDownload - minDownload) / avgDownload * 100

        if variance < 15 {
            return ("Consistent Results", "Your connection performs similarly across all servers. No throttling detected.", .green)
        } else if variance < 30 {
            return ("Minor Variations", "Some speed differences between servers. This is normal due to routing and server load.", .blue)
        } else {
            let fastestProvider = successfulResults.max { $0.downloadSpeed < $1.downloadSpeed }?.provider ?? ""
            let slowestProvider = successfulResults.min { $0.downloadSpeed < $1.downloadSpeed }?.provider ?? ""
            return ("Significant Variation", "\(fastestProvider) is significantly faster than \(slowestProvider). This could indicate routing issues or ISP throttling.", .orange)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(analysis.color)
                Text(analysis.verdict)
                    .font(.subheadline.bold())
            }

            Text(analysis.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(analysis.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    MultiServerTestView(historyManager: HistoryManager())
        .frame(width: 800, height: 700)
}
