import Foundation
import SwiftUI
import Combine

@MainActor
class NetworkQualityViewModel: ObservableObject {
    @Published var testConfiguration = TestConfiguration()
    @Published var results: [NetworkQualityResult] = []
    @Published var speedHistory: [SpeedDataPoint] = []
    @Published var currentResult: NetworkQualityResult?
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var availableInterfaces: [String] = []

    let service = NetworkQualityService()
    private var cancellables = Set<AnyCancellable>()

    var isRunning: Bool {
        service.isRunning
    }

    var progress: String {
        service.progress
    }

    var currentDownloadSpeed: Double {
        service.currentDownloadSpeed
    }

    var currentUploadSpeed: Double {
        service.currentUploadSpeed
    }

    var verboseOutput: [String] {
        service.verboseOutput
    }

    init() {
        // Forward service's objectWillChange to this ViewModel so UI updates
        // Throttle to prevent AttributeGraph cycle errors from rapid updates
        service.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        loadInterfaces()
    }

    func loadInterfaces() {
        availableInterfaces = service.getAvailableInterfaces()
    }

    func runTest() async {
        errorMessage = nil
        showError = false

        do {
            let result = try await service.runTest(config: testConfiguration)
            currentResult = result
            results.append(result)

            // Add to speed history for graphing
            let dataPoint = SpeedDataPoint(
                timestamp: result.timestamp,
                downloadMbps: result.downloadSpeedMbps,
                uploadMbps: result.uploadSpeedMbps
            )
            speedHistory.append(dataPoint)

            // Keep only last 50 data points
            if speedHistory.count > 50 {
                speedHistory.removeFirst(speedHistory.count - 50)
            }
        } catch NetworkQualityError.cancelled {
            // User cancelled - don't show error
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func cancelTest() {
        service.cancelTest()
    }

    func clearHistory() {
        results.removeAll()
        speedHistory.removeAll()
        currentResult = nil
    }

    func exportResultsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportData: [[String: Any]] = results.map { result in
            var dict: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: result.timestamp),
                "download_mbps": result.downloadSpeedMbps,
                "upload_mbps": result.uploadSpeedMbps
            ]
            if let responsiveness = result.responsiveness {
                dict["responsiveness_rpm"] = responsiveness
            }
            if let baseRtt = result.baseRtt {
                dict["base_rtt_ms"] = baseRtt
            }
            if let interfaceName = result.interfaceName {
                dict["interface"] = interfaceName
            }
            return dict
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "[]"
    }

    func exportResultsCSV() -> String {
        var csv = "Timestamp,Download (Mbps),Upload (Mbps),Responsiveness (RPM),Latency (ms),Interface,Connection Type,WiFi SSID,WiFi Band,WiFi Channel,Signal Quality,Signal (dBm),Link Speed (Mbps)\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for result in results {
            var row: [String] = []

            // Timestamp
            row.append(escapeCSV(dateFormatter.string(from: result.timestamp)))

            // Speeds
            row.append(String(format: "%.2f", result.downloadSpeedMbps))
            row.append(String(format: "%.2f", result.uploadSpeedMbps))

            // Responsiveness
            if let rpm = result.responsivenessValue {
                row.append("\(rpm)")
            } else {
                row.append("")
            }

            // Latency
            if let rtt = result.baseRtt {
                row.append(String(format: "%.1f", rtt))
            } else {
                row.append("")
            }

            // Interface - escape in case of unusual interface names
            row.append(escapeCSV(result.interfaceName ?? ""))

            // Network metadata - escape all string fields (excluding IPs for privacy)
            if let metadata = result.networkMetadata {
                row.append(escapeCSV(metadata.connectionType.rawValue))
                row.append(escapeCSV(metadata.wifiSSID ?? ""))
                row.append(escapeCSV(metadata.wifiBand?.rawValue ?? ""))
                row.append(metadata.wifiChannel.map { "\($0)" } ?? "")
                row.append(escapeCSV(metadata.signalQuality ?? ""))
                row.append(metadata.wifiRSSI.map { "\($0)" } ?? "")
                row.append(metadata.wifiTxRate.map { String(format: "%.0f", $0) } ?? "")
            } else {
                row.append(contentsOf: ["", "", "", "", "", "", ""])
            }

            csv += row.joined(separator: ",") + "\n"
        }

        return csv
    }

    /// Escapes a string value for RFC 4180-compliant CSV output.
    /// Handles commas, quotes, newlines, and carriage returns by wrapping in quotes and escaping internal quotes.
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    func exportSingleResultCSV(_ result: NetworkQualityResult) -> String {
        var csv = "Timestamp,Download (Mbps),Upload (Mbps),Responsiveness (RPM),Latency (ms),Interface,Connection Type,WiFi SSID,WiFi Band,WiFi Channel,Signal Quality,Signal (dBm),Link Speed (Mbps)\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var row: [String] = []
        row.append(escapeCSV(dateFormatter.string(from: result.timestamp)))
        row.append(String(format: "%.2f", result.downloadSpeedMbps))
        row.append(String(format: "%.2f", result.uploadSpeedMbps))
        row.append(result.responsivenessValue.map { "\($0)" } ?? "")
        row.append(result.baseRtt.map { String(format: "%.1f", $0) } ?? "")
        row.append(escapeCSV(result.interfaceName ?? ""))

        // Network metadata (excluding IPs for privacy)
        if let metadata = result.networkMetadata {
            row.append(escapeCSV(metadata.connectionType.rawValue))
            row.append(escapeCSV(metadata.wifiSSID ?? ""))
            row.append(escapeCSV(metadata.wifiBand?.rawValue ?? ""))
            row.append(metadata.wifiChannel.map { "\($0)" } ?? "")
            row.append(escapeCSV(metadata.signalQuality ?? ""))
            row.append(metadata.wifiRSSI.map { "\($0)" } ?? "")
            row.append(metadata.wifiTxRate.map { String(format: "%.0f", $0) } ?? "")
        } else {
            row.append(contentsOf: ["", "", "", "", "", "", ""])
        }

        csv += row.joined(separator: ",") + "\n"
        return csv
    }

    func exportSingleResultJSON(_ result: NetworkQualityResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(result),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    var averageDownloadSpeed: Double {
        guard !results.isEmpty else { return 0 }
        return results.reduce(0.0) { $0 + $1.downloadSpeedMbps } / Double(results.count)
    }

    var averageUploadSpeed: Double {
        guard !results.isEmpty else { return 0 }
        return results.reduce(0.0) { $0 + $1.uploadSpeedMbps } / Double(results.count)
    }

    var maxDownloadSpeed: Double {
        results.map { $0.downloadSpeedMbps }.max() ?? 0
    }

    var maxUploadSpeed: Double {
        results.map { $0.uploadSpeedMbps }.max() ?? 0
    }
}
