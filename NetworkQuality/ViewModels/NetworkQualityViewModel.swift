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
        service.objectWillChange
            .receive(on: RunLoop.main)
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

    func exportResults() -> String {
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
