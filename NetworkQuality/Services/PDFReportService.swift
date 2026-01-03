import Foundation
import AppKit
import PDFKit
import SwiftUI

@MainActor
class PDFReportService {
    static let shared = PDFReportService()

    private init() {}

    /// Generate a PDF report for a single test result
    func generateReport(for result: NetworkQualityResult) -> Data? {
        let reportView = PDFReportView(result: result, allResults: [result])
        return renderViewToPDF(reportView, pageSize: CGSize(width: 612, height: 792)) // Letter size
    }

    /// Generate a PDF report with historical trends
    func generateReport(for result: NetworkQualityResult, history: [NetworkQualityResult]) -> Data? {
        let reportView = PDFReportView(result: result, allResults: history)
        return renderViewToPDF(reportView, pageSize: CGSize(width: 612, height: 792))
    }

    /// Generate a summary report for multiple results
    func generateSummaryReport(results: [NetworkQualityResult]) -> Data? {
        guard let latest = results.first else { return nil }
        let reportView = PDFReportView(result: latest, allResults: results)
        return renderViewToPDF(reportView, pageSize: CGSize(width: 612, height: 792))
    }

    /// Save PDF to file with save dialog
    func saveReport(for result: NetworkQualityResult, history: [NetworkQualityResult] = []) {
        guard let pdfData = generateReport(for: result, history: history.isEmpty ? [result] : history) else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "NetworkQuality-Report-\(formattedDateForFilename()).pdf"
        savePanel.title = "Save PDF Report"
        savePanel.message = "Choose where to save your network quality report"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? pdfData.write(to: url)
            }
        }
    }

    private func renderViewToPDF<V: View>(_ view: V, pageSize: CGSize) -> Data? {
        // Render the view without height constraint to get natural size
        let contentView = view.frame(width: pageSize.width).fixedSize(horizontal: false, vertical: true)
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
        let actualPageHeight = min(contentHeight, 2000) // Cap at reasonable max
        let mediaBox = CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: actualPageHeight))
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)

        // Draw image scaled to fit the page
        let drawRect = CGRect(origin: .zero, size: CGSize(width: contentWidth, height: contentHeight))
        context.draw(cgImage, in: drawRect)

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}

// MARK: - PDF Report View

struct PDFReportView: View {
    let result: NetworkQualityResult
    let allResults: [NetworkQualityResult]
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Main content
            VStack(spacing: 14) {
                // Overall Summary
                overallSummarySection

                // Speed results
                speedResultsSection

                // Quality metrics
                qualityMetricsSection

                // Bufferbloat visualization
                if let idleLatency = result.baseRtt, let rpm = result.responsivenessValue {
                    bufferbloatSection(idleLatency: idleLatency, rpm: rpm)
                }

                // Network info
                if let metadata = result.networkMetadata {
                    networkInfoSection(metadata)
                }

                // What can you do section
                capabilitiesSection

                // Historical trends (if multiple results)
                if allResults.count > 1 {
                    historicalTrendsSection
                }

                Spacer(minLength: 0)

                // Footer
                footerSection
            }
            .padding(20)
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
                        Image(systemName: "network")
                            .font(.system(size: 24, weight: .semibold))
                        Text("Network Quality Report")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }

                    Text(formattedTimestamp)
                        .font(.system(size: 12))
                        .opacity(0.9)
                }

                Spacer()

                if let rating = overallRating {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(rating.label)
                            .font(.system(size: 14, weight: .semibold))
                        Text(rating.description)
                            .font(.system(size: 11))
                            .opacity(0.8)
                    }
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(height: 80)
    }

    // MARK: - Overall Summary

    private var overallSummarySection: some View {
        let summary = NetworkInsights.overallSummary(
            downloadMbps: result.downloadSpeedMbps,
            uploadMbps: result.uploadSpeedMbps,
            rpm: result.responsivenessValue,
            mode: .practical
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: summaryIcon(for: summary.overallRating))
                    .font(.system(size: 20))
                    .foregroundColor(summary.overallRating.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.overallRating.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(summary.overallRating.color)
                    Text(summary.headline)
                        .font(.system(size: 12, weight: .medium))
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 10))
                        Text("Speed")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                    Text(summary.speedSummary)
                        .font(.system(size: 11))
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10))
                        Text("Responsiveness")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                    Text(summary.responsivenessSummary)
                        .font(.system(size: 11))
                }
            }

            if let recommendation = summary.topRecommendation {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(recommendation)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(summary.overallRating.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func summaryIcon(for rating: NetworkInsights.OverallRating) -> String {
        switch rating {
        case .poor: return "exclamationmark.triangle.fill"
        case .fair: return "minus.circle.fill"
        case .good: return "checkmark.circle.fill"
        case .excellent: return "star.circle.fill"
        }
    }

    // MARK: - Speed Results

    private var speedResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speed Test Results")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // Download
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Download")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text(speedUnit.formatBps(result.dlThroughput))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Upload
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                        Text("Upload")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text(speedUnit.formatBps(result.ulThroughput))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quality Metrics

    private var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality Metrics")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // Responsiveness
                if let rpm = result.responsivenessValue {
                    VStack(spacing: 4) {
                        Text("Responsiveness")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(rpm)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("RPM")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Text(result.responsivenessRating)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(responsivenessColor(rpm))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(responsivenessColor(rpm).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                }

                // Latency
                if let rtt = result.baseRtt {
                    VStack(spacing: 4) {
                        Text("Latency")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(String(format: "%.0f", rtt))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("ms")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Text(latencyRating(rtt))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(latencyColor(rtt))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(latencyColor(rtt).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Network Info

    private func networkInfoSection(_ metadata: NetworkMetadata) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Details")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 24) {
                // Connection type
                VStack(alignment: .leading, spacing: 2) {
                    Text("Type")
                        .font(.system(size: 10))
                        .foregroundColor(Color.gray.opacity(0.6))
                    HStack(spacing: 4) {
                        Image(systemName: metadata.connectionType.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text(metadata.connectionType.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                }

                // Interface
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interface")
                        .font(.system(size: 10))
                        .foregroundColor(Color.gray.opacity(0.6))
                    Text(metadata.interfaceName)
                        .font(.system(size: 12, weight: .medium))
                }

                // WiFi details
                if metadata.connectionType == .wifi {
                    if let ssid = metadata.wifiSSID {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Network")
                                .font(.system(size: 10))
                                .foregroundColor(Color.gray.opacity(0.6))
                            Text(ssid)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }

                    if let band = metadata.wifiBand {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Band")
                                .font(.system(size: 10))
                                .foregroundColor(Color.gray.opacity(0.6))
                            Text(band.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }

                    if let quality = metadata.signalQuality {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signal")
                                .font(.system(size: 10))
                                .foregroundColor(Color.gray.opacity(0.6))
                            Text(quality)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bufferbloat

    private func bufferbloatSection(idleLatency: Double, rpm: Int) -> some View {
        let loadedLatency = 60000.0 / Double(rpm)
        let bufferbloatMs = max(0, loadedLatency - idleLatency)
        let multiplier = idleLatency > 0 ? loadedLatency / idleLatency : 1

        let severity: (label: String, color: Color, explanation: String) = {
            switch multiplier {
            case ..<1.5: return ("Minimal", .green, "Your network maintains low latency even under load.")
            case 1.5..<3: return ("Moderate", .blue, "Some latency increase under load, but acceptable.")
            case 3..<6: return ("Significant", .orange, "Noticeable delay when network is busy.")
            default: return ("Severe", .red, "High latency under load. Consider enabling SQM.")
            }
        }()

        let maxLatency = max(loadedLatency, idleLatency)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(severity.color)
                Text("Bufferbloat")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(severity.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(severity.color)
            }

            // Latency bars
            VStack(alignment: .leading, spacing: 6) {
                // Idle bar
                HStack(spacing: 8) {
                    Text("Idle")
                        .font(.system(size: 10))
                        .frame(width: 45, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(idleLatency / maxLatency))
                        }
                    }
                    .frame(height: 16)
                    Text(String(format: "%.0f ms", idleLatency))
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 50, alignment: .trailing)
                }

                // Loaded bar
                HStack(spacing: 8) {
                    Text("Loaded")
                        .font(.system(size: 10))
                        .frame(width: 45, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(severity.color)
                                .frame(width: geo.size.width * CGFloat(loadedLatency / maxLatency))
                        }
                    }
                    .frame(height: 16)
                    Text(String(format: "%.0f ms", loadedLatency))
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            HStack {
                Text("Latency increase under load: ")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("+\(Int(bufferbloatMs)) ms")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(severity.color)
                Text("(\(String(format: "%.1f", multiplier))× slower)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(severity.explanation)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Capabilities

    private var capabilitiesSection: some View {
        let speedInsight = NetworkInsights.speedInsight(
            downloadMbps: result.downloadSpeedMbps,
            uploadMbps: result.uploadSpeedMbps
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("What can you do with this connection?")
                .font(.system(size: 13, weight: .semibold))

            Text(speedInsight.headline)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Use a simpler grid without ForEach
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    capabilityItem(speedInsight.capabilities, index: 0)
                    capabilityItem(speedInsight.capabilities, index: 1)
                    capabilityItem(speedInsight.capabilities, index: 2)
                }
                HStack(spacing: 6) {
                    capabilityItem(speedInsight.capabilities, index: 3)
                    capabilityItem(speedInsight.capabilities, index: 4)
                    capabilityItem(speedInsight.capabilities, index: 5)
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func capabilityItem(_ capabilities: [NetworkInsights.ActivityCapability], index: Int) -> some View {
        if index < capabilities.count {
            let capability = capabilities[index]
            HStack(spacing: 4) {
                Image(systemName: capability.icon)
                    .font(.system(size: 10))
                    .foregroundColor(capability.supported ? .green : .red)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(capability.activity)
                        .font(.system(size: 9, weight: .medium))
                    Text(capability.detail)
                        .font(.system(size: 8))
                        .foregroundColor(capability.supported ? .green : .orange)
                }
                Spacer()
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(generateInsights(), id: \.self) { insight in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text(insight)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Historical Trends

    private var historicalTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historical Comparison (\(allResults.count) tests)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // Download average
                VStack(spacing: 4) {
                    Text("Avg Download")
                        .font(.system(size: 10))
                        .foregroundColor(Color.gray.opacity(0.6))
                    Text(speedUnit.formatBps(Int64(averageDownload * 1_000_000)))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }

                // Upload average
                VStack(spacing: 4) {
                    Text("Avg Upload")
                        .font(.system(size: 10))
                        .foregroundColor(Color.gray.opacity(0.6))
                    Text(speedUnit.formatBps(Int64(averageUpload * 1_000_000)))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }

                // Latency average
                if let avgLatency = averageLatency {
                    VStack(spacing: 4) {
                        Text("Avg Latency")
                            .font(.system(size: 10))
                            .foregroundColor(Color.gray.opacity(0.6))
                        Text(String(format: "%.0f ms", avgLatency))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Generated by NetworkQuality for macOS")
                .font(.system(size: 9))
                .foregroundColor(Color.gray.opacity(0.6))

            Spacer()

            Text(Date(), style: .date)
                .font(.system(size: 9))
                .foregroundColor(Color.gray.opacity(0.6))
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: result.timestamp)
    }

    private var overallRating: (label: String, description: String)? {
        guard let rpm = result.responsivenessValue else { return nil }

        switch rpm {
        case 0..<200:
            return ("Needs Improvement", "Consider troubleshooting your connection")
        case 200..<800:
            return ("Good", "Suitable for basic activities")
        case 800..<1500:
            return ("Great", "Good for most activities")
        default:
            return ("Excellent", "Outstanding network quality")
        }
    }

    private func responsivenessColor(_ rpm: Int) -> Color {
        switch rpm {
        case 0..<200: return .red
        case 200..<800: return .orange
        case 800..<1500: return .blue
        default: return .green
        }
    }

    private func latencyRating(_ ms: Double) -> String {
        switch ms {
        case 0..<20: return "Excellent"
        case 20..<50: return "Good"
        case 50..<100: return "Fair"
        default: return "High"
        }
    }

    private func latencyColor(_ ms: Double) -> Color {
        switch ms {
        case 0..<20: return .green
        case 20..<50: return .blue
        case 50..<100: return .orange
        default: return .red
        }
    }

    private func generateInsights() -> [String] {
        var insights: [String] = []

        // Speed insights
        let downloadMbps = result.downloadSpeedMbps
        if downloadMbps >= 100 {
            insights.append("Your download speed supports 4K streaming and large file transfers.")
        } else if downloadMbps >= 25 {
            insights.append("Your download speed is suitable for HD streaming and video calls.")
        } else {
            insights.append("Consider upgrading your connection for better streaming quality.")
        }

        // RPM insights
        if let rpm = result.responsivenessValue {
            if rpm >= 1000 {
                insights.append("Excellent responsiveness for gaming and real-time applications.")
            } else if rpm >= 400 {
                insights.append("Good responsiveness for video conferencing and web browsing.")
            } else {
                insights.append("Lower responsiveness may affect real-time application performance.")
            }
        }

        // Latency insights
        if let rtt = result.baseRtt {
            if rtt < 20 {
                insights.append("Low latency ideal for competitive gaming and trading.")
            } else if rtt > 100 {
                insights.append("High latency may cause noticeable delays in interactive apps.")
            }
        }

        return insights
    }

    private var averageDownload: Double {
        let downloads = allResults.compactMap { $0.dlThroughput }.map { Double($0) / 1_000_000 }
        return downloads.isEmpty ? 0 : downloads.reduce(0, +) / Double(downloads.count)
    }

    private var averageUpload: Double {
        let uploads = allResults.compactMap { $0.ulThroughput }.map { Double($0) / 1_000_000 }
        return uploads.isEmpty ? 0 : uploads.reduce(0, +) / Double(uploads.count)
    }

    private var averageLatency: Double? {
        let latencies = allResults.compactMap { $0.baseRtt }
        return latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
    }
}

#Preview {
    let sampleResult = NetworkQualityResult(
        downloadMbps: 245.5,
        uploadMbps: 42.3,
        responsivenessRPM: 892,
        idleLatencyMs: 12.4,
        interfaceName: "en0",
        networkMetadata: NetworkMetadata(
            connectionType: .wifi,
            interfaceName: "en0",
            localIPAddress: "192.168.1.100",
            publicIPAddress: "203.0.113.42",
            wifiSSID: "Home Network",
            wifiBSSID: nil,
            wifiRSSI: -52,
            wifiNoise: -90,
            wifiChannel: 36,
            wifiBand: .band5GHz,
            wifiTxRate: 866,
            wifiSecurity: .wpa3Personal
        )
    )

    return PDFReportView(result: sampleResult, allResults: [sampleResult])
        .frame(width: 612, height: 792)
        .background(Color.gray.opacity(0.2))
}
