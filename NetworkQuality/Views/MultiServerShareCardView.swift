import SwiftUI
import AppKit

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
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
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
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
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
            print("Failed to render multi-server card image")
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

    private func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("Failed to convert image to PNG")
            return
        }

        do {
            try pngData.write(to: url)
        } catch {
            print("Failed to save image: \(error)")
        }
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}

#Preview {
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
