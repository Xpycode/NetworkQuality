import SwiftUI
import AppKit
import os.log

private let shareLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NetworkQuality", category: "Share")

/// A visually appealing result card designed for social sharing
struct ShareableResultCardView: View {
    let result: NetworkQualityResult
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    private let cardWidth: CGFloat = 400
    private let cardHeight: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient
            headerSection

            // Main content
            VStack(spacing: 20) {
                // Speed metrics
                speedSection

                Divider()
                    .padding(.horizontal)

                // Responsiveness and latency
                qualitySection

                // Network info (if available)
                if let metadata = result.networkMetadata {
                    Divider()
                        .padding(.horizontal)
                    networkSection(metadata: metadata)
                }

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
            // Gradient background - Orange/Amber theme
            LinearGradient(
                colors: [Color.orange, Color(red: 0.9, green: 0.4, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Network Quality")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                if let rating = overallRating {
                    Text(rating.headline)
                        .font(.system(size: 14, weight: .medium))
                        .opacity(0.9)
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 20)
        }
        .frame(height: 90)
    }

    // MARK: - Speed Section

    private var speedSection: some View {
        HStack(spacing: 24) {
            SpeedMetricView(
                title: "Download",
                value: speedUnit.formatBps(result.dlThroughput),
                icon: "arrow.down.circle.fill",
                color: .blue
            )

            SpeedMetricView(
                title: "Upload",
                value: speedUnit.formatBps(result.ulThroughput),
                icon: "arrow.up.circle.fill",
                color: .green
            )
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        HStack(spacing: 24) {
            if let rpm = result.responsivenessValue {
                QualityMetricView(
                    title: "Responsiveness",
                    value: "\(rpm)",
                    unit: "RPM",
                    subtitle: result.responsivenessRating,
                    color: responsivenessColor(rpm)
                )
            }

            if let rtt = result.baseRtt {
                QualityMetricView(
                    title: "Latency",
                    value: String(format: "%.0f", rtt),
                    unit: "ms",
                    subtitle: latencyRating(rtt),
                    color: latencyColor(rtt)
                )
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Network Section

    private func networkSection(metadata: NetworkMetadata) -> some View {
        HStack(spacing: 16) {
            Image(systemName: metadata.connectionType.icon)
                .font(.system(size: 20))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(metadata.connectionType.rawValue)
                        .font(.system(size: 14, weight: .medium))

                    if let ssid = metadata.wifiSSID, !ssid.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(ssid)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                if metadata.connectionType == .wifi {
                    HStack(spacing: 12) {
                        if let band = metadata.wifiBand {
                            Label(band.rawValue, systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let quality = metadata.signalQuality {
                            Label(quality, systemImage: "wifi")
                                .font(.caption)
                                .foregroundColor(signalColor(metadata))
                        }
                    }
                }
            }

            Spacer()
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

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: result.timestamp)
    }

    private var overallRating: (headline: String, color: Color)? {
        guard let rpm = result.responsivenessValue else { return nil }

        switch rpm {
        case 0..<200:
            return ("Network needs improvement", .red)
        case 200..<800:
            return ("Good for basic tasks", .orange)
        case 800..<1500:
            return ("Great for most activities", .blue)
        default:
            return ("Excellent network quality", .green)
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

    private func signalColor(_ metadata: NetworkMetadata) -> Color {
        guard let rssi = metadata.wifiRSSI else { return .secondary }
        switch rssi {
        case -50...0: return .green
        case -60..<(-50): return .blue
        case -70..<(-60): return .orange
        default: return .red
        }
    }
}

// MARK: - Subviews

struct SpeedMetricView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 13, weight: .medium))

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct QualityMetricView: View {
    let title: String
    let value: String
    let unit: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Image Rendering

extension ShareableResultCardView {
    /// Render the card as an NSImage for sharing
    @MainActor
    func renderAsImage() -> NSImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0 // Retina quality

        guard let cgImage = renderer.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cardWidth, height: cardHeight))
    }
}

// MARK: - Share Service

@MainActor
class ShareService {
    static let shared = ShareService()

    private init() {}

    /// Share the result card image using macOS sharing services
    func shareResultCard(result: NetworkQualityResult, from view: NSView) {
        let cardView = ShareableResultCardView(result: result)

        guard let image = cardView.renderAsImage() else {
            shareLogger.error("Failed to render result card image for sharing")
            return
        }

        let sharingPicker = NSSharingServicePicker(items: [image])
        sharingPicker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Save the result card image to a file
    func saveResultCard(result: NetworkQualityResult) {
        let cardView = ShareableResultCardView(result: result)

        guard let image = cardView.renderAsImage() else {
            shareLogger.error("Failed to render result card image for saving")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "NetworkQuality-\(formattedDateForFilename()).png"
        savePanel.title = "Save Result Card"
        savePanel.message = "Choose where to save your network quality result card"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                self.saveImage(image, to: url)
            }
        }
    }

    /// Copy the result card image to clipboard
    func copyResultCardToClipboard(result: NetworkQualityResult) -> Bool {
        let cardView = ShareableResultCardView(result: result)

        guard let image = cardView.renderAsImage() else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        return true
    }

    private func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            shareLogger.error("Failed to convert image to PNG format")
            return
        }

        do {
            try pngData.write(to: url)
        } catch {
            shareLogger.error("Failed to save image: \(error.localizedDescription)")
        }
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}

// MARK: - SwiftUI Share Button Helper

struct ShareButtonView: NSViewRepresentable {
    let result: NetworkQualityResult
    let action: ShareAction

    enum ShareAction {
        case share
        case save
        case copy
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked(_:))
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.result = result
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(result: result, action: action)
    }

    class Coordinator: NSObject {
        var result: NetworkQualityResult
        var action: ShareAction

        init(result: NetworkQualityResult, action: ShareAction) {
            self.result = result
            self.action = action
        }

        @objc func buttonClicked(_ sender: NSButton) {
            Task { @MainActor in
                switch action {
                case .share:
                    ShareService.shared.shareResultCard(result: result, from: sender)
                case .save:
                    ShareService.shared.saveResultCard(result: result)
                case .copy:
                    _ = ShareService.shared.copyResultCardToClipboard(result: result)
                }
            }
        }
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

    return ShareableResultCardView(result: sampleResult)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
