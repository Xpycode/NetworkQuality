import Foundation

// MARK: - Speed Test Provider Protocol

/// Protocol for network speed test providers.
/// Implementations should handle errors gracefully:
/// - `runTest` returns a result with the `error` field set on failure (does not throw for network errors)
/// - Throwing is reserved for programming errors or unrecoverable states
/// - Progress callbacks should be called throughout the test to update UI
protocol SpeedTestProvider: Sendable {
    var name: String { get }
    var icon: String { get }
    func runTest(onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async throws -> SpeedTestResult
    func cancel() async
}

// MARK: - Data Models

struct SpeedTestProgress: Sendable {
    let provider: String
    let phase: TestPhase
    let progress: Double // 0.0 - 1.0
    let currentSpeed: Double? // Mbps
    let downloadSpeed: Double? // For parallel tests (Apple)
    let uploadSpeed: Double? // For parallel tests (Apple)

    enum TestPhase: String, Sendable {
        case connecting = "Connecting"
        case download = "Download"
        case upload = "Upload"
        case parallel = "Testing" // For Apple's parallel mode
        case complete = "Complete"
        case failed = "Failed"
    }

    init(provider: String, phase: TestPhase, progress: Double, currentSpeed: Double?, downloadSpeed: Double? = nil, uploadSpeed: Double? = nil) {
        self.provider = provider
        self.phase = phase
        self.progress = progress
        self.currentSpeed = currentSpeed
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
    }
}

struct SpeedTestResult: Identifiable, Sendable {
    let id = UUID()
    let provider: String
    let downloadSpeed: Double // Mbps
    let uploadSpeed: Double // Mbps
    let latency: Double? // ms
    let serverLocation: String?
    let timestamp: Date
    let error: String?

    var isSuccess: Bool { error == nil }
}

// MARK: - Apple NetworkQuality Provider

actor AppleSpeedTestProvider: SpeedTestProvider {
    nonisolated let name = "Apple"
    nonisolated let icon = "apple.logo"

    private let runner = AppleNetworkQualityRunner()

    private var isSequentialMode: Bool {
        UserDefaults.standard.bool(forKey: "appleSequentialMode")
    }

    func runTest(onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async throws -> SpeedTestResult {
        let providerName = name
        onProgress(SpeedTestProgress(provider: providerName, phase: .connecting, progress: 0, currentSpeed: nil))

        await runner.reset()

        var config = RunnerConfiguration()
        config.mode = isSequentialMode ? .sequential : .parallel

        do {
            let result = try await runner.runTest(config: config) { progress in
                let phase: SpeedTestProgress.TestPhase
                switch progress.phase {
                case .connecting: phase = .connecting
                case .download: phase = .download
                case .upload: phase = .upload
                case .parallel: phase = .parallel
                case .complete: phase = .complete
                }

                onProgress(SpeedTestProgress(
                    provider: providerName,
                    phase: phase,
                    progress: progress.progressPercentage,
                    currentSpeed: max(progress.downloadSpeed, progress.uploadSpeed),
                    downloadSpeed: progress.downloadSpeed > 0 ? progress.downloadSpeed : nil,
                    uploadSpeed: progress.uploadSpeed > 0 ? progress.uploadSpeed : nil
                ))
            }

            onProgress(SpeedTestProgress(provider: providerName, phase: .complete, progress: 1.0, currentSpeed: result.downloadMbps))

            return SpeedTestResult(
                provider: providerName,
                downloadSpeed: result.downloadMbps,
                uploadSpeed: result.uploadMbps,
                latency: result.idleLatencyMs,
                serverLocation: "Apple CDN",
                timestamp: Date(),
                error: nil
            )
        } catch {
            onProgress(SpeedTestProgress(provider: providerName, phase: .failed, progress: 0, currentSpeed: nil))
            return SpeedTestResult(
                provider: providerName,
                downloadSpeed: 0,
                uploadSpeed: 0,
                latency: nil,
                serverLocation: nil,
                timestamp: Date(),
                error: error.localizedDescription
            )
        }
    }

    func cancel() async {
        await runner.cancel()
    }
}

// MARK: - Cloudflare Speed Test Provider

actor CloudflareSpeedTestProvider: SpeedTestProvider {
    nonisolated let name = "Cloudflare"
    nonisolated let icon = "cloud.fill"

    private let baseURL = "https://speed.cloudflare.com"
    private let downloadSizes = [100_000, 1_000_000, 10_000_000, 25_000_000] // 100KB, 1MB, 10MB, 25MB
    private let uploadSizes = [100_000, 1_000_000, 5_000_000] // 100KB, 1MB, 5MB

    // Reusable upload buffer to reduce allocations
    private var uploadBuffer: Data?
    private var currentTask: Task<SpeedTestResult, Error>?

    func runTest(onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async throws -> SpeedTestResult {
        let providerName = name
        onProgress(SpeedTestProgress(provider: providerName, phase: .connecting, progress: 0, currentSpeed: nil))

        // Pre-allocate upload buffer for largest size
        let maxUploadSize = uploadSizes.max() ?? 5_000_000
        if uploadBuffer == nil || uploadBuffer!.count < maxUploadSize {
            uploadBuffer = generateRandomData(size: maxUploadSize)
        }

        // Measure latency first
        let latency = await measureLatency()

        // Download test
        onProgress(SpeedTestProgress(provider: providerName, phase: .download, progress: 0.1, currentSpeed: nil))
        let downloadSpeed = await measureDownload(onProgress: onProgress)

        // Check for cancellation
        if Task.isCancelled {
            return SpeedTestResult(
                provider: providerName,
                downloadSpeed: 0,
                uploadSpeed: 0,
                latency: nil,
                serverLocation: nil,
                timestamp: Date(),
                error: "Cancelled"
            )
        }

        // Upload test
        onProgress(SpeedTestProgress(provider: providerName, phase: .upload, progress: 0.6, currentSpeed: nil))
        let uploadSpeed = await measureUpload(onProgress: onProgress)

        onProgress(SpeedTestProgress(provider: providerName, phase: .complete, progress: 1.0, currentSpeed: downloadSpeed))

        return SpeedTestResult(
            provider: providerName,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            latency: latency,
            serverLocation: "Cloudflare Edge",
            timestamp: Date(),
            error: nil
        )
    }

    func cancel() async {
        currentTask?.cancel()
    }

    /// Measures network latency by timing multiple small requests.
    /// - Returns: Minimum observed latency in milliseconds, or `nil` if all ping attempts fail.
    ///   Returning `nil` is a normal condition when latency cannot be determined; tests should continue.
    private func measureLatency() async -> Double? {
        guard let url = URL(string: "\(baseURL)/__down?bytes=0") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        var latencies: [Double] = []

        for _ in 0..<5 {
            if Task.isCancelled { break }

            let start = Date()
            do {
                let (_, _) = try await URLSession.shared.data(for: request)
                let elapsed = Date().timeIntervalSince(start) * 1000 // Convert to ms
                latencies.append(elapsed)
            } catch {
                continue
            }
        }

        guard !latencies.isEmpty else { return nil }
        return latencies.min()
    }

    private func measureDownload(onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async -> Double {
        var totalBytes: Int64 = 0
        var totalTime: TimeInterval = 0
        var speeds: [Double] = []
        let providerName = name

        for (index, size) in downloadSizes.enumerated() {
            if Task.isCancelled { break }

            guard let url = URL(string: "\(baseURL)/__down?bytes=\(size)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30

            let start = Date()
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let elapsed = Date().timeIntervalSince(start)

                totalBytes += Int64(data.count)
                totalTime += elapsed

                let speedMbps = Double(data.count * NetworkQualityConstants.bitsPerByte) / elapsed / NetworkQualityConstants.megabit
                speeds.append(speedMbps)

                let progress = 0.1 + (Double(index + 1) / Double(downloadSizes.count)) * 0.4
                onProgress(SpeedTestProgress(provider: providerName, phase: .download, progress: progress, currentSpeed: speedMbps))
            } catch {
                continue
            }
        }

        guard !speeds.isEmpty else { return 0 }
        return Double(totalBytes * Int64(NetworkQualityConstants.bitsPerByte)) / totalTime / NetworkQualityConstants.megabit
    }

    private func measureUpload(onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async -> Double {
        var totalBytes: Int64 = 0
        var totalTime: TimeInterval = 0
        var speeds: [Double] = []
        let providerName = name

        guard let buffer = uploadBuffer else { return 0 }

        for (index, size) in uploadSizes.enumerated() {
            if Task.isCancelled { break }

            guard let url = URL(string: "\(baseURL)/__up") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            // Reuse buffer - just slice to needed size
            request.httpBody = buffer.prefix(size)
            request.timeoutInterval = 30

            let start = Date()
            do {
                let (_, _) = try await URLSession.shared.data(for: request)
                let elapsed = Date().timeIntervalSince(start)

                totalBytes += Int64(size)
                totalTime += elapsed

                let speedMbps = Double(size * NetworkQualityConstants.bitsPerByte) / elapsed / NetworkQualityConstants.megabit
                speeds.append(speedMbps)

                let progress = 0.6 + (Double(index + 1) / Double(uploadSizes.count)) * 0.35
                onProgress(SpeedTestProgress(provider: providerName, phase: .upload, progress: progress, currentSpeed: speedMbps))
            } catch {
                continue
            }
        }

        guard !speeds.isEmpty else { return 0 }
        return Double(totalBytes * Int64(NetworkQualityConstants.bitsPerByte)) / totalTime / NetworkQualityConstants.megabit
    }

    private func generateRandomData(size: Int) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            arc4random_buf(baseAddress, size)
        }
        return data
    }
}

// MARK: - Completion Guard (for WebSocket race safety)

/// Actor to guard against multiple completions in async callback scenarios.
/// Ensures continuation is resumed exactly once even with competing callbacks.
private actor CompletionGuard<T: Sendable> {
    private var hasCompleted = false
    private var continuation: CheckedContinuation<T, Never>?

    func setContinuation(_ cont: CheckedContinuation<T, Never>) {
        self.continuation = cont
    }

    /// Attempts to complete with the given value. Returns true if this was the first completion.
    func tryComplete(with value: T) -> Bool {
        guard !hasCompleted, let cont = continuation else { return false }
        hasCompleted = true
        continuation = nil
        cont.resume(returning: value)
        return true
    }

    var isCompleted: Bool { hasCompleted }
}

// MARK: - Download Test State (actor-isolated shared state)

/// Actor to safely manage shared state during NDT7 download test.
private actor DownloadTestState {
    private var totalBytes: Int64 = 0
    private var startTime = Date()
    private var lastMeasurement: NDT7Measurement?

    func addBytes(_ count: Int64) {
        totalBytes += count
    }

    func setMeasurement(_ measurement: NDT7Measurement) {
        lastMeasurement = measurement
    }

    func getMeasurement() -> NDT7Measurement? {
        lastMeasurement
    }

    func getStats() -> (totalBytes: Int64, elapsed: TimeInterval) {
        (totalBytes, Date().timeIntervalSince(startTime))
    }
}

// MARK: - Upload Test State (actor-isolated shared state)

/// Actor to safely manage shared state during NDT7 upload test.
private actor UploadTestState {
    private var totalBytesSent: Int64 = 0
    private var startTime = Date()
    private var lastMeasurement: NDT7Measurement?

    func addBytesSent(_ count: Int64) {
        totalBytesSent += count
    }

    func setMeasurement(_ measurement: NDT7Measurement) {
        lastMeasurement = measurement
    }

    func getMeasurement() -> NDT7Measurement? {
        lastMeasurement
    }

    func getStats() -> (totalBytesSent: Int64, elapsed: TimeInterval) {
        (totalBytesSent, Date().timeIntervalSince(startTime))
    }
}

// MARK: - M-Lab NDT7 Speed Test Provider

actor MLabSpeedTestProvider: SpeedTestProvider {
    nonisolated let name = "M-Lab"
    nonisolated let icon = "globe.americas.fill"

    private let locateURL = "https://locate.measurementlab.net/v2/nearest/ndt/ndt7"
    private let downloadTimeout: TimeInterval = 12
    private let uploadTimeout: TimeInterval = 10
    private let uploadChunkSize = 1 << 13 // 8KB chunks

    private var currentWebSocketTask: URLSessionWebSocketTask?

    func runTest(onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async throws -> SpeedTestResult {
        let providerName = name
        onProgress(SpeedTestProgress(provider: providerName, phase: .connecting, progress: 0, currentSpeed: nil))

        // Discover nearest server
        guard let serverInfo = await discoverServer() else {
            return SpeedTestResult(
                provider: providerName,
                downloadSpeed: 0,
                uploadSpeed: 0,
                latency: nil,
                serverLocation: nil,
                timestamp: Date(),
                error: "Failed to discover M-Lab server"
            )
        }

        onProgress(SpeedTestProgress(provider: providerName, phase: .download, progress: 0.1, currentSpeed: nil))

        // Run download test
        let downloadResult = await runDownloadTest(url: serverInfo.downloadURL, onProgress: onProgress)

        if Task.isCancelled {
            return SpeedTestResult(
                provider: providerName,
                downloadSpeed: 0,
                uploadSpeed: 0,
                latency: nil,
                serverLocation: nil,
                timestamp: Date(),
                error: "Cancelled"
            )
        }

        onProgress(SpeedTestProgress(provider: providerName, phase: .upload, progress: 0.55, currentSpeed: nil))

        // Run upload test
        let uploadResult = await runUploadTest(url: serverInfo.uploadURL, onProgress: onProgress)

        onProgress(SpeedTestProgress(provider: providerName, phase: .complete, progress: 1.0, currentSpeed: downloadResult.speed))

        return SpeedTestResult(
            provider: providerName,
            downloadSpeed: downloadResult.speed,
            uploadSpeed: uploadResult.speed,
            latency: downloadResult.latency ?? uploadResult.latency,
            serverLocation: serverInfo.location,
            timestamp: Date(),
            error: downloadResult.error ?? uploadResult.error
        )
    }

    func cancel() async {
        currentWebSocketTask?.cancel(with: .goingAway, reason: nil)
        currentWebSocketTask = nil
    }

    private struct ServerInfo {
        let downloadURL: String
        let uploadURL: String
        let location: String
    }

    /// Discovers the nearest M-Lab NDT7 server using the locate API.
    /// - Returns: ServerInfo with download/upload URLs on success, or `nil` if server discovery fails.
    ///   Callers should handle `nil` by reporting an error to the user.
    private func discoverServer() async -> ServerInfo? {
        guard let url = URL(string: locateURL) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let first = results.first {

                let location: String
                if let loc = first["location"] as? [String: Any] {
                    let city = loc["city"] as? String ?? ""
                    let country = loc["country"] as? String ?? ""
                    location = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
                } else {
                    location = "Unknown"
                }

                if let urls = first["urls"] as? [String: String] {
                    let downloadURL = urls["wss:///ndt/v7/download"] ?? ""
                    let uploadURL = urls["wss:///ndt/v7/upload"] ?? ""

                    if !downloadURL.isEmpty && !uploadURL.isEmpty {
                        return ServerInfo(downloadURL: downloadURL, uploadURL: uploadURL, location: location)
                    }
                }
            }
        } catch {
            NetworkQualityLogger.multiServer.error("M-Lab server discovery failed: \(error.localizedDescription)")
        }

        return nil
    }

    private struct TestResult {
        let speed: Double
        let latency: Double?
        let error: String?
    }

    private func runDownloadTest(url: String, onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async -> TestResult {
        guard let wsURL = URL(string: url) else {
            return TestResult(speed: 0, latency: nil, error: "Invalid download URL")
        }

        let providerName = name
        let guard_ = CompletionGuard<TestResult>()

        return await withCheckedContinuation { continuation in
            Task {
                await guard_.setContinuation(continuation)
            }

            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: wsURL, protocols: ["net.measurementlab.ndt.v7"])
            currentWebSocketTask = task

            // Shared state protected by actor isolation
            let state = DownloadTestState()

            @Sendable func receiveMessage() {
                Task {
                    guard await !guard_.isCompleted && !Task.isCancelled else { return }

                    task.receive { result in
                        Task {
                            switch result {
                            case .success(let message):
                                switch message {
                                case .data(let data):
                                    await state.addBytes(Int64(data.count))
                                    let (totalBytes, elapsed) = await state.getStats()
                                    let speedMbps = Double(totalBytes * Int64(NetworkQualityConstants.bitsPerByte)) / elapsed / NetworkQualityConstants.megabit
                                    let progress = min(0.1 + elapsed / 10.0 * 0.4, 0.5)
                                    onProgress(SpeedTestProgress(provider: providerName, phase: .download, progress: progress, currentSpeed: speedMbps))

                                case .string(let text):
                                    if let data = text.data(using: .utf8),
                                       let measurement = try? JSONDecoder().decode(NDT7Measurement.self, from: data) {
                                        await state.setMeasurement(measurement)
                                    }

                                @unknown default:
                                    break
                                }

                                receiveMessage()

                            case .failure:
                                let (totalBytes, elapsed) = await state.getStats()
                                let speedMbps = totalBytes > 0 ? Double(totalBytes * Int64(NetworkQualityConstants.bitsPerByte)) / elapsed / NetworkQualityConstants.megabit : 0
                                let measurement = await state.getMeasurement()
                                let latency = measurement?.tcpInfo?.minRTT.map { Double($0) / 1000.0 }
                                _ = await guard_.tryComplete(with: TestResult(speed: speedMbps, latency: latency, error: nil))
                            }
                        }
                    }
                }
            }

            task.resume()
            receiveMessage()

            // Timeout task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(downloadTimeout) * NetworkQualityConstants.secondInNanoseconds)
                guard await !guard_.isCompleted else { return }
                task.cancel(with: .goingAway, reason: nil)
                let (totalBytes, elapsed) = await state.getStats()
                let speedMbps = totalBytes > 0 ? Double(totalBytes * Int64(NetworkQualityConstants.bitsPerByte)) / elapsed / NetworkQualityConstants.megabit : 0
                let measurement = await state.getMeasurement()
                let latency = measurement?.tcpInfo?.minRTT.map { Double($0) / 1000.0 }
                _ = await guard_.tryComplete(with: TestResult(speed: speedMbps, latency: latency, error: nil))
            }
        }
    }

    private func runUploadTest(url: String, onProgress: @escaping @Sendable (SpeedTestProgress) -> Void) async -> TestResult {
        guard let wsURL = URL(string: url) else {
            return TestResult(speed: 0, latency: nil, error: "Invalid upload URL")
        }

        let providerName = name
        let chunkSize = uploadChunkSize
        let timeout = uploadTimeout
        let guard_ = CompletionGuard<TestResult>()
        let state = UploadTestState()

        // Pre-generate upload chunk (as let constant for Sendable safety)
        let uploadChunk: Data = {
            var data = Data(count: chunkSize)
            data.withUnsafeMutableBytes { ptr in
                guard let baseAddress = ptr.baseAddress else { return }
                arc4random_buf(baseAddress, chunkSize)
            }
            return data
        }()

        return await withCheckedContinuation { continuation in
            Task {
                await guard_.setContinuation(continuation)
            }

            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: wsURL, protocols: ["net.measurementlab.ndt.v7"])
            currentWebSocketTask = task

            @Sendable func sendData() {
                Task {
                    guard await !guard_.isCompleted && !Task.isCancelled else { return }

                    let (_, elapsed) = await state.getStats()
                    if elapsed >= timeout {
                        task.cancel(with: .goingAway, reason: nil)
                        let (totalBytesSent, finalElapsed) = await state.getStats()
                        let speedMbps = totalBytesSent > 0 ? Double(totalBytesSent * Int64(NetworkQualityConstants.bitsPerByte)) / finalElapsed / NetworkQualityConstants.megabit : 0
                        let measurement = await state.getMeasurement()
                        let latency = measurement?.tcpInfo?.minRTT.map { Double($0) / 1000.0 }
                        _ = await guard_.tryComplete(with: TestResult(speed: speedMbps, latency: latency, error: nil))
                        return
                    }

                    task.send(.data(uploadChunk)) { error in
                        Task {
                            if error != nil {
                                let (totalBytesSent, elapsed) = await state.getStats()
                                let speedMbps = totalBytesSent > 0 ? Double(totalBytesSent * Int64(NetworkQualityConstants.bitsPerByte)) / elapsed / NetworkQualityConstants.megabit : 0
                                _ = await guard_.tryComplete(with: TestResult(speed: speedMbps, latency: nil, error: nil))
                                return
                            }

                            await state.addBytesSent(Int64(chunkSize))
                            let (totalBytesSent, elapsed) = await state.getStats()
                            let speedMbps = Double(totalBytesSent * Int64(NetworkQualityConstants.bitsPerByte)) / elapsed / NetworkQualityConstants.megabit
                            let progress = 0.55 + elapsed / 10.0 * 0.4
                            onProgress(SpeedTestProgress(provider: providerName, phase: .upload, progress: min(progress, 0.95), currentSpeed: speedMbps))

                            sendData()
                        }
                    }
                }
            }

            @Sendable func receiveMessages() {
                Task {
                    guard await !guard_.isCompleted && !Task.isCancelled else { return }

                    task.receive { result in
                        Task {
                            if case .success(let message) = result,
                               case .string(let text) = message,
                               let data = text.data(using: .utf8),
                               let measurement = try? JSONDecoder().decode(NDT7Measurement.self, from: data) {
                                await state.setMeasurement(measurement)
                            }
                            receiveMessages()
                        }
                    }
                }
            }

            task.resume()
            sendData()
            receiveMessages()
        }
    }
}

// MARK: - NDT7 Measurement Models

struct NDT7Measurement: Codable, Sendable {
    let appInfo: AppInfo?
    let origin: String?
    let test: String?
    let tcpInfo: TCPInfo?

    enum CodingKeys: String, CodingKey {
        case appInfo = "AppInfo"
        case origin = "Origin"
        case test = "Test"
        case tcpInfo = "TCPInfo"
    }

    struct AppInfo: Codable, Sendable {
        let elapsedTime: Int?
        let numBytes: Int?

        enum CodingKeys: String, CodingKey {
            case elapsedTime = "ElapsedTime"
            case numBytes = "NumBytes"
        }
    }

    struct TCPInfo: Codable, Sendable {
        let minRTT: Int?
        let rtt: Int?
        let bytesAcked: Int?
        let bytesSent: Int?

        enum CodingKeys: String, CodingKey {
            case minRTT = "MinRTT"
            case rtt = "RTT"
            case bytesAcked = "BytesAcked"
            case bytesSent = "BytesSent"
        }
    }
}

// MARK: - Speed Test Error

enum SpeedTestError: LocalizedError {
    case parseError(String)
    case networkError(String)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .parseError(let msg): return "Parse error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .timeout: return "Test timed out"
        case .cancelled: return "Test cancelled"
        }
    }
}

// MARK: - Multi-Server Test Coordinator

@MainActor
class MultiServerTestCoordinator: ObservableObject {
    @Published var results: [SpeedTestResult] = []
    @Published var progress: [String: SpeedTestProgress] = [:]
    @Published var isRunning = false
    @Published var currentProvider: String?

    private let appleProvider = AppleSpeedTestProvider()
    private let cloudflareProvider = CloudflareSpeedTestProvider()
    private let mlabProvider = MLabSpeedTestProvider()

    private var providers: [any SpeedTestProvider] {
        [appleProvider, cloudflareProvider, mlabProvider]
    }

    private var runningTask: Task<Void, Never>?

    var availableProviders: [(name: String, icon: String)] {
        providers.map { ($0.name, $0.icon) }
    }

    func stopAllTests() {
        runningTask?.cancel()
        runningTask = nil

        // Cancel all providers
        Task {
            await appleProvider.cancel()
            await cloudflareProvider.cancel()
            await mlabProvider.cancel()
        }

        currentProvider = nil
        isRunning = false
    }

    func runAllTests() {
        guard !isRunning else { return }

        isRunning = true
        results.removeAll()
        progress.removeAll()

        // Initialize progress for all providers
        for provider in providers {
            progress[provider.name] = SpeedTestProgress(
                provider: provider.name,
                phase: .connecting,
                progress: 0,
                currentSpeed: nil
            )
        }

        runningTask = Task { [weak self] in
            guard let self = self else { return }

            for provider in self.providers {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.currentProvider = provider.name
                }

                do {
                    let result = try await provider.runTest { [weak self] progressUpdate in
                        Task { @MainActor in
                            self?.progress[provider.name] = progressUpdate
                        }
                    }

                    if Task.isCancelled { break }

                    await MainActor.run {
                        self.results.append(result)
                    }
                } catch {
                    if Task.isCancelled { break }

                    await MainActor.run {
                        self.results.append(SpeedTestResult(
                            provider: provider.name,
                            downloadSpeed: 0,
                            uploadSpeed: 0,
                            latency: nil,
                            serverLocation: nil,
                            timestamp: Date(),
                            error: error.localizedDescription
                        ))
                    }
                }
            }

            await MainActor.run {
                self.currentProvider = nil
                self.isRunning = false
            }
        }
    }

    func runSingleTest(providerName: String) {
        guard !isRunning else { return }

        let provider: (any SpeedTestProvider)?
        switch providerName {
        case "Apple": provider = appleProvider
        case "Cloudflare": provider = cloudflareProvider
        case "M-Lab": provider = mlabProvider
        default: provider = nil
        }

        guard let provider = provider else { return }

        isRunning = true
        currentProvider = providerName

        // Remove existing result for this provider
        results.removeAll { $0.provider == providerName }

        progress[providerName] = SpeedTestProgress(
            provider: providerName,
            phase: .connecting,
            progress: 0,
            currentSpeed: nil
        )

        runningTask = Task { [weak self] in
            do {
                let result = try await provider.runTest { [weak self] progressUpdate in
                    Task { @MainActor in
                        self?.progress[providerName] = progressUpdate
                    }
                }
                await MainActor.run { [weak self] in
                    self?.results.append(result)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.results.append(SpeedTestResult(
                        provider: providerName,
                        downloadSpeed: 0,
                        uploadSpeed: 0,
                        latency: nil,
                        serverLocation: nil,
                        timestamp: Date(),
                        error: error.localizedDescription
                    ))
                }
            }

            await MainActor.run { [weak self] in
                self?.currentProvider = nil
                self?.isRunning = false
            }
        }
    }

    func cancelTests() {
        stopAllTests()
    }
}
