import SwiftUI
import AppKit
import os.log

private let multiServerShareLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NetworkQuality", category: "MultiServerShare")

/// A shareable card showing multi-server speed test comparison
struct MultiServerShareCardView: View {
    let results: [SpeedTestResult]
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    private let cardWidth: CGFloat = 440
    private let cardHeight: CGFloat = 480

    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient
            headerSection

            // Main content
            VStack(spacing: 16) {
                // Provider results
                resultsSection

                Divider()
                    .padding(.horizontal)

                // Summary/Winner
                summarySection

                Spacer(minLength: 0)

                // Footer with timestamp
                footerSection
            }
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            // Gradient background - Orange/Amber for speed/energy feel
            LinearGradient(
                colors: [Color.orange, Color(red: 0.9, green: 0.4, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Multi-Server Comparison")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Text("\(successfulResults.count) servers tested")
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.9)
            }
            .foregroundColor(.white)
            .padding(.vertical, 20)
        }
        .frame(height: 90)
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(spacing: 12) {
            // Header row
            HStack {
                Text("Provider")
                    .frame(width: 90, alignment: .leading)
                Text("Download")
                    .frame(width: 90, alignment: .trailing)
                Text("Upload")
                    .frame(width: 90, alignment: .trailing)
                Text("Latency")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)

            // Provider rows
            ForEach(sortedResults) { result in
                providerRow(result: result)
            }
        }
    }

    private func providerRow(result: SpeedTestResult) -> some View {
        let isFastest = result.downloadSpeed == fastestDownload

        return HStack {
            // Provider name with icon
            HStack(spacing: 6) {
                Image(systemName: providerIcon(result.provider))
                    .font(.system(size: 12))
                    .foregroundStyle(providerColor(result.provider))
                    .frame(width: 14)
                Text(result.provider)
                    .font(.system(size: 13, weight: isFastest ? .bold : .regular))
                if isFastest {
                    Image(systemName: "trophy")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 100, alignment: .leading)

            // Download speed
            Text(result.isSuccess ? formatSpeed(result.downloadSpeed) : "-")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(result.isSuccess ? .primary : .secondary)
                .frame(width: 90, alignment: .trailing)

            // Upload speed
            Text(result.isSuccess ? formatSpeed(result.uploadSpeed) : "-")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(result.isSuccess ? .primary : .secondary)
                .frame(width: 90, alignment: .trailing)

            // Latency
            Text(result.latency.map { String(format: "%.0f ms", $0) } ?? "-")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(isFastest ? providerColor(result.provider).opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: 12) {
            if let fastest = fastestProvider {
                HStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .foregroundColor(.orange)
                    Text("Fastest: \(fastest.provider)")
                        .font(.system(size: 15, weight: .semibold))
                    Text("@ \(formatSpeed(fastest.downloadSpeed))")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }

            // Speed range indicator
            if successfulResults.count >= 2 {
                let minSpeed = successfulResults.map(\.downloadSpeed).min() ?? 0
                let maxSpeed = successfulResults.map(\.downloadSpeed).max() ?? 0
                let variance = maxSpeed > 0 ? ((maxSpeed - minSpeed) / maxSpeed * 100) : 0

                HStack(spacing: 8) {
                    Image(systemName: varianceIcon(variance))
                        .foregroundColor(varianceColor(variance))
                    Text(varianceText(variance))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text(formattedTimestamp)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text("Tested with NetworkQuality")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var successfulResults: [SpeedTestResult] {
        results.filter { $0.isSuccess }
    }

    private var sortedResults: [SpeedTestResult] {
        results.sorted { $0.downloadSpeed > $1.downloadSpeed }
    }

    private var fastestProvider: SpeedTestResult? {
        successfulResults.max { $0.downloadSpeed < $1.downloadSpeed }
    }

    private var fastestDownload: Double {
        fastestProvider?.downloadSpeed ?? 0
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

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private func varianceIcon(_ variance: Double) -> String {
        switch variance {
        case 0..<15: return "checkmark.circle.fill"
        case 15..<30: return "info.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func varianceColor(_ variance: Double) -> Color {
        switch variance {
        case 0..<15: return .green
        case 15..<30: return .blue
        default: return .orange
        }
    }

    private func varianceText(_ variance: Double) -> String {
        switch variance {
        case 0..<15: return "Consistent speeds across servers"
        case 15..<30: return "Minor variations between servers"
        default: return "Significant speed differences detected"
        }
    }
}

// MARK: - Image Rendering

extension MultiServerShareCardView {
    /// Render the card as an NSImage for sharing
    @MainActor
    func renderAsImage() -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0 // Retina quality

        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cardWidth, height: cardHeight))
    }
}

// MARK: - Multi-Server Share Service

@MainActor
class MultiServerShareService {
    static let shared = MultiServerShareService()

    private init() {}

    // MARK: - Conversion helpers for StoredSpeedTestResult

    private func convertToSpeedTestResult(_ stored: StoredSpeedTestResult) -> SpeedTestResult {
        SpeedTestResult(
            provider: stored.provider,
            downloadSpeed: stored.downloadSpeed,
            uploadSpeed: stored.uploadSpeed,
            latency: stored.latency,
            serverLocation: stored.serverLocation,
            timestamp: stored.timestamp,
            error: stored.error
        )
    }

    private func convertResults(_ storedResults: [StoredSpeedTestResult]) -> [SpeedTestResult] {
        storedResults.map { convertToSpeedTestResult($0) }
    }

    // MARK: - StoredSpeedTestResult overloads

    /// Copy the comparison card image to clipboard (from history)
    func copyToClipboard(results: [StoredSpeedTestResult]) -> Bool {
        copyToClipboard(results: convertResults(results))
    }

    /// Save the comparison card to a file (from history)
    func saveCard(results: [StoredSpeedTestResult]) {
        saveCard(results: convertResults(results))
    }

    /// Generate text summary (from history)
    func textSummary(results: [StoredSpeedTestResult], speedUnit: SpeedUnit) -> String {
        textSummary(results: convertResults(results), speedUnit: speedUnit)
    }

    /// Generate PDF report (from history)
    func generatePDFReport(results: [StoredSpeedTestResult], timestamp: Date) -> Data? {
        generatePDFReport(results: convertResults(results), timestamp: timestamp)
    }

    /// Save PDF report (from history)
    func savePDFReport(results: [StoredSpeedTestResult], timestamp: Date) {
        savePDFReport(results: convertResults(results), timestamp: timestamp)
    }

    // MARK: - SpeedTestResult methods

    /// Copy the comparison card image to clipboard
    func copyToClipboard(results: [SpeedTestResult]) -> Bool {
        let cardView = MultiServerShareCardView(results: results)

        guard let image = cardView.renderAsImage() else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        return true
    }

    /// Save the comparison card to a file
    func saveCard(results: [SpeedTestResult]) {
        let cardView = MultiServerShareCardView(results: results)

        guard let image = cardView.renderAsImage() else {
            multiServerShareLogger.error("Failed to render multi-server card image")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "MultiServer-\(formattedDateForFilename()).png"
        savePanel.title = "Save Comparison Card"
        savePanel.message = "Choose where to save your multi-server comparison card"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                self.saveImage(image, to: url)
            }
        }
    }

    /// Generate text summary for sharing
    func textSummary(results: [SpeedTestResult], speedUnit: SpeedUnit) -> String {
        var lines: [String] = ["🖥️ Multi-Server Speed Test Results", ""]

        let sorted = results.sorted { $0.downloadSpeed > $1.downloadSpeed }

        for (index, result) in sorted.enumerated() {
            let medal = index == 0 ? "🥇" : (index == 1 ? "🥈" : "🥉")
            if result.isSuccess {
                let dl = speedUnit.format(result.downloadSpeed)
                let ul = speedUnit.format(result.uploadSpeed)
                lines.append("\(medal) \(result.provider): ↓\(dl.value) \(dl.unit) / ↑\(ul.value) \(ul.unit)")
            } else {
                lines.append("❌ \(result.provider): Failed")
            }
        }

        lines.append("")
        lines.append("Tested with NetworkQuality app")

        return lines.joined(separator: "\n")
    }

    /// Generate PDF report data
    func generatePDFReport(results: [SpeedTestResult], timestamp: Date = Date()) -> Data? {
        let reportView = MultiServerPDFReportView(results: results, timestamp: timestamp)
        return renderViewToPDF(reportView, pageWidth: 612) // Letter width
    }

    /// Save PDF report to file with save dialog
    func savePDFReport(results: [SpeedTestResult], timestamp: Date = Date()) {
        guard let pdfData = generatePDFReport(results: results, timestamp: timestamp) else {
            multiServerShareLogger.error("Failed to generate multi-server PDF report")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "MultiServer-Report-\(formattedDateForFilename()).pdf"
        savePanel.title = "Save PDF Report"
        savePanel.message = "Choose where to save your multi-server comparison report"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? pdfData.write(to: url)
            }
        }
    }

    private func renderViewToPDF<V: View>(_ view: V, pageWidth: CGFloat) -> Data? {
        // Render the view without height constraint to get natural size
        let contentView = view.frame(width: pageWidth).fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: contentView)
        renderer.scale = 2.0

        guard let cgImage = renderer.cgImage else { return nil }

        // Calculate actual content height from rendered image
        let contentHeight = CGFloat(cgImage.height) / renderer.scale
        let contentWidth = CGFloat(cgImage.width) / renderer.scale

        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        // Use actual content height for single-page PDF (with reasonable max)
        let actualPageHeight = min(contentHeight, 2000)
        let mediaBox = CGRect(origin: .zero, size: CGSize(width: pageWidth, height: actualPageHeight))
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)

        // Draw image
        let drawRect = CGRect(origin: .zero, size: CGSize(width: contentWidth, height: contentHeight))
        context.draw(cgImage, in: drawRect)

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            multiServerShareLogger.error("Failed to convert image to PNG format")
            return
        }

        do {
            try pngData.write(to: url)
        } catch {
            multiServerShareLogger.error("Failed to save image: \(error.localizedDescription)")
        }
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}

// MARK: - Multi-Server PDF Report View

struct MultiServerPDFReportView: View {
    let results: [SpeedTestResult]
    let timestamp: Date
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    init(results: [SpeedTestResult], timestamp: Date = Date()) {
        self.results = results
        self.timestamp = timestamp
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Main content
            VStack(spacing: 16) {
                // Summary section
                summarySection

                // Speed comparison chart
                speedComparisonSection

                // Detailed results table
                detailedResultsSection

                // Analysis section
                analysisSection

                // Recommendations
                if !recommendations.isEmpty {
                    recommendationsSection
                }

                Spacer(minLength: 0)

                // Footer
                footerSection
            }
            .padding(24)
            .background(Color.white)
        }
        .background(Color.white)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange, Color(red: 0.9, green: 0.4, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 24, weight: .semibold))
                        Text("Multi-Server Speed Test Report")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }

                    Text(formattedTimestamp)
                        .font(.system(size: 12))
                        .opacity(0.9)
                }

                Spacer()

                if let fastest = fastestProvider {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 12))
                            Text("Fastest")
                                .font(.system(size: 11))
                        }
                        .opacity(0.8)
                        Text(fastest.provider)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(height: 80)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: consistencyIcon)
                    .font(.system(size: 18))
                    .foregroundColor(consistencyColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(consistencyVerdict)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(consistencyColor)
                    Text(consistencyDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Quick stats
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(successfulResults.count)/\(results.count) servers tested")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if let variance = downloadVariancePercent {
                        Text(String(format: "%.0f%% variance", variance))
                            .font(.system(size: 10))
                            .foregroundColor(varianceColor(variance))
                    }
                }
            }
        }
        .padding(14)
        .background(consistencyColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Speed Comparison Section

    private var speedComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speed Comparison")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                // Download comparison
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("Download")
                            .font(.system(size: 11, weight: .medium))
                    }

                    ForEach(sortedByDownload) { result in
                        speedBar(
                            provider: result.provider,
                            speed: result.downloadSpeed,
                            maxSpeed: maxDownload,
                            color: providerColor(result.provider),
                            isFastest: result.id == fastestProvider?.id
                        )
                    }
                }

                Divider()

                // Upload comparison
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("Upload")
                            .font(.system(size: 11, weight: .medium))
                    }

                    ForEach(sortedByUpload) { result in
                        speedBar(
                            provider: result.provider,
                            speed: result.uploadSpeed,
                            maxSpeed: maxUpload,
                            color: providerColor(result.provider),
                            isFastest: result.id == fastestUploadProvider?.id
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func speedBar(provider: String, speed: Double, maxSpeed: Double, color: Color, isFastest: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: providerIcon(provider))
                    .font(.system(size: 10))
                    .foregroundColor(color)
                    .frame(width: 12)
                Text(provider)
                    .font(.system(size: 10))
                if isFastest {
                    Image(systemName: "trophy")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.gradient)
                        .frame(width: maxSpeed > 0 ? geo.size.width * CGFloat(speed / maxSpeed) : 0)
                }
            }
            .frame(height: 14)

            Text(formatSpeed(speed))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: - Detailed Results Section

    private var detailedResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Results")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                // Header row
                HStack {
                    Text("Provider")
                        .frame(width: 100, alignment: .leading)
                    Text("Download")
                        .frame(width: 90, alignment: .trailing)
                    Text("Upload")
                        .frame(width: 90, alignment: .trailing)
                    Text("Latency")
                        .frame(width: 60, alignment: .trailing)
                    Text("Server")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.1))

                // Result rows
                ForEach(results) { result in
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: providerIcon(result.provider))
                                .font(.system(size: 10))
                                .foregroundColor(providerColor(result.provider))
                                .frame(width: 12)
                            Text(result.provider)
                                .font(.system(size: 11, weight: .medium))
                            if result.id == fastestProvider?.id {
                                Image(systemName: "trophy")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }
                        }
                        .frame(width: 100, alignment: .leading)

                        Text(result.isSuccess ? formatSpeed(result.downloadSpeed) : "-")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(result.isSuccess ? .primary : .secondary)
                            .frame(width: 90, alignment: .trailing)

                        Text(result.isSuccess ? formatSpeed(result.uploadSpeed) : "-")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(result.isSuccess ? .primary : .secondary)
                            .frame(width: 90, alignment: .trailing)

                        Text(result.latency.map { String(format: "%.0f ms", $0) } ?? "-")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)

                        Text(result.serverLocation ?? "-")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(result.id == fastestProvider?.id ? providerColor(result.provider).opacity(0.08) : Color.clear)

                    if result.id != results.last?.id {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
            .background(Color.gray.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Analysis Section

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                // Download variance
                if let variance = downloadVariancePercent {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("Download Variance")
                            .font(.system(size: 11))
                        Spacer()
                        Text(String(format: "%.1f%%", variance))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(varianceColor(variance))
                    }
                }

                // Upload variance
                if let variance = uploadVariancePercent {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("Upload Variance")
                            .font(.system(size: 11))
                        Spacer()
                        Text(String(format: "%.1f%%", variance))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(varianceColor(variance))
                    }
                }

                // Latency comparison
                if let lowestLatency = lowestLatencyProvider {
                    HStack {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("Lowest Latency")
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(lowestLatency.provider) (\(String(format: "%.0f ms", lowestLatency.latency ?? 0)))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recommendations Section

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(recommendations, id: \.self) { recommendation in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(recommendation)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(14)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Generated by NetworkQuality for macOS")
                .font(.system(size: 9))
                .foregroundColor(Color.gray.opacity(0.6))

            Spacer()

            Text(timestamp, style: .date)
                .font(.system(size: 9))
                .foregroundColor(Color.gray.opacity(0.6))
        }
        .padding(.top, 8)
    }

    // MARK: - Computed Properties

    private var successfulResults: [SpeedTestResult] {
        results.filter { $0.isSuccess }
    }

    private var sortedByDownload: [SpeedTestResult] {
        successfulResults.sorted { $0.downloadSpeed > $1.downloadSpeed }
    }

    private var sortedByUpload: [SpeedTestResult] {
        successfulResults.sorted { $0.uploadSpeed > $1.uploadSpeed }
    }

    private var fastestProvider: SpeedTestResult? {
        successfulResults.max { $0.downloadSpeed < $1.downloadSpeed }
    }

    private var fastestUploadProvider: SpeedTestResult? {
        successfulResults.max { $0.uploadSpeed < $1.uploadSpeed }
    }

    private var lowestLatencyProvider: SpeedTestResult? {
        successfulResults.filter { $0.latency != nil }.min { ($0.latency ?? 999) < ($1.latency ?? 999) }
    }

    private var maxDownload: Double {
        successfulResults.map(\.downloadSpeed).max() ?? 1
    }

    private var maxUpload: Double {
        successfulResults.map(\.uploadSpeed).max() ?? 1
    }

    private var downloadVariancePercent: Double? {
        guard successfulResults.count >= 2 else { return nil }
        let downloads = successfulResults.map(\.downloadSpeed)
        let maxDl = downloads.max() ?? 0
        let minDl = downloads.min() ?? 0
        return maxDl > 0 ? ((maxDl - minDl) / maxDl * 100) : 0
    }

    private var uploadVariancePercent: Double? {
        guard successfulResults.count >= 2 else { return nil }
        let uploads = successfulResults.map(\.uploadSpeed)
        let maxUl = uploads.max() ?? 0
        let minUl = uploads.min() ?? 0
        return maxUl > 0 ? ((maxUl - minUl) / maxUl * 100) : 0
    }

    private var consistencyVerdict: String {
        guard let variance = downloadVariancePercent else { return "Insufficient Data" }
        switch variance {
        case 0..<15: return "Consistent Results"
        case 15..<30: return "Minor Variations"
        default: return "Significant Variation"
        }
    }

    private var consistencyDescription: String {
        guard let variance = downloadVariancePercent else {
            return "Run tests on at least 2 servers to compare"
        }
        switch variance {
        case 0..<15: return "Your connection performs similarly across all servers. No throttling detected."
        case 15..<30: return "Some speed differences between servers. This is normal due to routing and server load."
        default:
            let fastest = fastestProvider?.provider ?? ""
            let slowest = successfulResults.min { $0.downloadSpeed < $1.downloadSpeed }?.provider ?? ""
            return "\(fastest) is significantly faster than \(slowest). This could indicate routing issues or ISP throttling."
        }
    }

    private var consistencyIcon: String {
        guard let variance = downloadVariancePercent else { return "questionmark.circle.fill" }
        switch variance {
        case 0..<15: return "checkmark.circle.fill"
        case 15..<30: return "info.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var consistencyColor: Color {
        guard let variance = downloadVariancePercent else { return .secondary }
        return varianceColor(variance)
    }

    private func varianceColor(_ variance: Double) -> Color {
        switch variance {
        case 0..<15: return .green
        case 15..<30: return .blue
        default: return .orange
        }
    }

    private var recommendations: [String] {
        var recs: [String] = []

        guard let variance = downloadVariancePercent else { return recs }

        if variance > 30, let fastest = fastestProvider, let slowest = successfulResults.min(by: { $0.downloadSpeed < $1.downloadSpeed }) {
            recs.append("Consider using \(fastest.provider) for bandwidth-intensive tasks; \(slowest.provider) showed lower speeds.")
        }

        if let avgDownload = averageDownload {
            if avgDownload < 25 {
                recs.append("Your average download speed (\(String(format: "%.1f Mbps", avgDownload))) may limit HD streaming quality.")
            } else if avgDownload >= 100 {
                recs.append("Your connection supports high-bandwidth activities like 4K streaming and large downloads.")
            }
        }

        if let lowestLat = lowestLatencyProvider, let highestLat = successfulResults.filter({ $0.latency != nil }).max(by: { ($0.latency ?? 0) < ($1.latency ?? 0) }) {
            if let low = lowestLat.latency, let high = highestLat.latency, high > low * 2 {
                recs.append("Latency varies significantly. \(lowestLat.provider) offers the best responsiveness.")
            }
        }

        return recs
    }

    private var averageDownload: Double? {
        guard !successfulResults.isEmpty else { return nil }
        return successfulResults.map(\.downloadSpeed).reduce(0, +) / Double(successfulResults.count)
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    private func formatSpeed(_ mbps: Double) -> String {
        let formatted = speedUnit.format(mbps)
        return "\(formatted.value) \(formatted.unit)"
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
}

#Preview("Share Card") {
    let sampleResults = [
        SpeedTestResult(
            provider: "Apple",
            downloadSpeed: 245.5,
            uploadSpeed: 42.3,
            latency: 12.4,
            serverLocation: "Apple CDN",
            timestamp: Date(),
            error: nil
        ),
        SpeedTestResult(
            provider: "Cloudflare",
            downloadSpeed: 198.2,
            uploadSpeed: 38.7,
            latency: 15.2,
            serverLocation: "LAX",
            timestamp: Date(),
            error: nil
        ),
        SpeedTestResult(
            provider: "M-Lab",
            downloadSpeed: 156.8,
            uploadSpeed: 35.1,
            latency: 22.8,
            serverLocation: "Los Angeles, US",
            timestamp: Date(),
            error: nil
        )
    ]

    return MultiServerShareCardView(results: sampleResults)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("PDF Report") {
    let sampleResults = [
        SpeedTestResult(
            provider: "Apple",
            downloadSpeed: 245.5,
            uploadSpeed: 42.3,
            latency: 12.4,
            serverLocation: "Apple CDN",
            timestamp: Date(),
            error: nil
        ),
        SpeedTestResult(
            provider: "Cloudflare",
            downloadSpeed: 198.2,
            uploadSpeed: 38.7,
            latency: 15.2,
            serverLocation: "LAX",
            timestamp: Date(),
            error: nil
        ),
        SpeedTestResult(
            provider: "M-Lab",
            downloadSpeed: 156.8,
            uploadSpeed: 35.1,
            latency: 22.8,
            serverLocation: "Los Angeles, US",
            timestamp: Date(),
            error: nil
        )
    ]

    return MultiServerPDFReportView(results: sampleResults)
        .frame(width: 612)
        .background(Color.gray.opacity(0.2))
}
