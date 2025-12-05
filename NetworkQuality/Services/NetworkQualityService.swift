import Foundation
import Combine

enum NetworkQualityError: LocalizedError {
    case commandNotFound
    case executionFailed(String)
    case parseError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "networkQuality command not found"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .cancelled:
            return "Test was cancelled"
        }
    }
}

@MainActor
class NetworkQualityService: ObservableObject {
    @Published var isRunning = false
    @Published var progress: String = ""
    @Published var currentDownloadSpeed: Double = 0
    @Published var currentUploadSpeed: Double = 0
    @Published var verboseOutput: [String] = []
    @Published var elapsedTime: TimeInterval = 0
    @Published var progressLineCount: Int = 0

    var progressPercentage: Double {
        return min(Double(progressLineCount) / Double(NetworkQualityConstants.expectedProgressLines), NetworkQualityConstants.maxProgressPercentage)
    }

    private let runner = AppleNetworkQualityRunner()
    private var runningTask: Task<NetworkQualityResult, Error>?
    private var timerTask: Task<Void, Never>?
    private var verboseBuffer = RingBuffer<String>(capacity: NetworkQualityConstants.verboseOutputMaxLines)
    private var testStartTime: Date?

    func getAvailableInterfaces() -> [String] {
        // Synchronous wrapper for compatibility - prefer async version
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String] = ["en0", "en1", "pdp_ip0"]

        Task {
            result = await AppleNetworkQualityRunner.getAvailableInterfaces()
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    func getAvailableInterfacesAsync() async -> [String] {
        await AppleNetworkQualityRunner.getAvailableInterfaces()
    }

    func runTest(config: TestConfiguration) async throws -> NetworkQualityResult {
        guard !isRunning else {
            throw NetworkQualityError.executionFailed("Test already running")
        }

        // Reset state
        isRunning = true
        progress = "Starting test..."
        verboseOutput = []
        verboseBuffer.clear()
        currentDownloadSpeed = 0
        currentUploadSpeed = 0
        elapsedTime = 0
        progressLineCount = 0
        testStartTime = Date()

        // Reset the runner
        await runner.reset()

        // Start elapsed time timer using Task instead of Timer
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: NetworkQualityConstants.progressPollInterval)
                guard let self = self, let startTime = self.testStartTime else { continue }
                await MainActor.run {
                    self.elapsedTime = Date().timeIntervalSince(startTime)
                }
            }
        }

        defer {
            isRunning = false
            timerTask?.cancel()
            timerTask = nil
        }

        let runnerConfig = RunnerConfiguration(from: config)

        do {
            let result = try await runner.runTest(config: runnerConfig) { [weak self] progressUpdate in
                Task { @MainActor [weak self] in
                    self?.handleProgressUpdate(progressUpdate)
                }
            }

            progress = "Test completed"

            // Capture network metadata at time of test
            let networkMetadata = NetworkInfoService.shared.getCurrentMetadata()

            return NetworkQualityResult(
                downloadMbps: result.downloadMbps,
                uploadMbps: result.uploadMbps,
                responsivenessRPM: result.responsivenessRPM,
                idleLatencyMs: result.idleLatencyMs,
                interfaceName: config.networkInterface.isEmpty ? nil : config.networkInterface,
                networkMetadata: networkMetadata
            )
        } catch {
            progress = "Test failed"
            throw error
        }
    }

    func cancelTest() {
        Task {
            await runner.cancel()
        }
        runningTask?.cancel()
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
        progress = "Cancelled"
    }

    private func handleProgressUpdate(_ update: RunnerProgress) {
        currentDownloadSpeed = update.downloadSpeed
        currentUploadSpeed = update.uploadSpeed

        // Update progress text
        if update.downloadSpeed > 0 || update.uploadSpeed > 0 {
            progress = String(format: "↓ %.1f Mbps  ↑ %.1f Mbps", update.downloadSpeed, update.uploadSpeed)
        }

        // Count progress updates
        if update.downloadSpeed > 0 || update.uploadSpeed > 0 {
            progressLineCount += 1
        }

        // Add to verbose output using ring buffer
        let statusLine = String(format: "↓ %.1f Mbps  ↑ %.1f Mbps", update.downloadSpeed, update.uploadSpeed)
        if !statusLine.isEmpty {
            verboseBuffer.append(statusLine)
            verboseOutput = verboseBuffer.toArray()
        }
    }

    func discoverBonjourServers() async -> [String] {
        await AppleNetworkQualityRunner.discoverBonjourServers()
    }
}
