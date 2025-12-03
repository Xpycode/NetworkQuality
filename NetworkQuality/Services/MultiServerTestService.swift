import Foundation

// MARK: - Speed Test Provider Protocol

protocol SpeedTestProvider {
    var name: String { get }
    var icon: String { get }
    func runTest(onProgress: @escaping (SpeedTestProgress) -> Void) async throws -> SpeedTestResult
}

// MARK: - Data Models

struct SpeedTestProgress {
    let provider: String
    let phase: TestPhase
    let progress: Double // 0.0 - 1.0
    let currentSpeed: Double? // Mbps
    let downloadSpeed: Double? // For parallel tests (Apple)
    let uploadSpeed: Double? // For parallel tests (Apple)

    enum TestPhase: String {
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

struct SpeedTestResult: Identifiable {
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

// Thread-safe state container for Apple speed test
private final class AppleTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var _downloadSpeed: Double = 0
    private var _uploadSpeed: Double = 0
    private var _output: String = ""
    private var _inUploadPhase: Bool = false
    private var _uploadPhaseStartTime: Date?

    var downloadSpeed: Double {
        get { lock.withLock { _downloadSpeed } }
        set { lock.withLock { _downloadSpeed = newValue } }
    }

    var uploadSpeed: Double {
        get { lock.withLock { _uploadSpeed } }
        set { lock.withLock { _uploadSpeed = newValue } }
    }

    var output: String {
        get { lock.withLock { _output } }
        set { lock.withLock { _output = newValue } }
    }

    var inUploadPhase: Bool {
        get { lock.withLock { _inUploadPhase } }
        set { lock.withLock { _inUploadPhase = newValue } }
    }

    var uploadPhaseStartTime: Date? {
        get { lock.withLock { _uploadPhaseStartTime } }
        set { lock.withLock { _uploadPhaseStartTime = newValue } }
    }

    func appendOutput(_ text: String) {
        lock.withLock { _output += text }
    }
}

final class AppleSpeedTestProvider: SpeedTestProvider, @unchecked Sendable {
    let name = "Apple"
    let icon = "apple.logo"

    private var isSequentialMode: Bool {
        UserDefaults.standard.bool(forKey: "appleSequentialMode")
    }

    func runTest(onProgress: @escaping (SpeedTestProgress) -> Void) async throws -> SpeedTestResult {
        onProgress(SpeedTestProgress(provider: name, phase: .connecting, progress: 0, currentSpeed: nil))

        let providerName = name
        let sequentialMode = isSequentialMode

        return await withCheckedContinuation { continuation in
            let process = Process()
            // Use 'script' to allocate a pseudo-TTY for real-time progress output
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            let nqCommand = sequentialMode ? "/usr/bin/networkQuality -s" : "/usr/bin/networkQuality"
            process.arguments = ["-q", "/dev/null", "/bin/sh", "-c", nqCommand]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            let state = AppleTestState()
            let startTime = Date()

            // Parse live progress output
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

                state.appendOutput(output)

                // Parse progress lines like: "Downlink: 123.456 Mbps" and "Uplink: 8.200 Mbps"
                let lines = output.components(separatedBy: CharacterSet(charactersIn: "\r\n"))

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    // Parse downlink speed
                    if let downlinkRange = trimmed.range(of: "Downlink:\\s*([\\d.]+)\\s*Mbps", options: .regularExpression) {
                        let match = trimmed[downlinkRange]
                        if let speedMatch = match.range(of: "[\\d.]+", options: .regularExpression) {
                            if let speed = Double(match[speedMatch]) {
                                state.downloadSpeed = speed
                            }
                        }
                    }

                    // Parse uplink speed
                    if let uplinkRange = trimmed.range(of: "Uplink:\\s*([\\d.]+)\\s*Mbps", options: .regularExpression) {
                        let match = trimmed[uplinkRange]
                        if let speedMatch = match.range(of: "[\\d.]+", options: .regularExpression) {
                            if let speed = Double(match[speedMatch]) {
                                state.uploadSpeed = speed
                            }
                        }
                    }
                }

                // Determine phase and progress
                let elapsed = Date().timeIntervalSince(startTime)
                let currentDownload = state.downloadSpeed
                let currentUpload = state.uploadSpeed

                if sequentialMode {
                    // Sequential mode: track phase transitions properly
                    // Once we enter upload phase, we never go back
                    if currentUpload > 0 && !state.inUploadPhase {
                        state.inUploadPhase = true
                        state.uploadPhaseStartTime = Date()
                    }

                    let phase: SpeedTestProgress.TestPhase
                    let currentSpeed: Double?
                    let progress: Double

                    if state.inUploadPhase {
                        phase = .upload
                        currentSpeed = currentUpload
                        // Upload is second half: 0.5 to 1.0
                        let uploadElapsed = Date().timeIntervalSince(state.uploadPhaseStartTime ?? Date())
                        progress = min(0.5 + uploadElapsed / 12.0 * 0.45, 0.95)
                    } else if currentDownload > 0 {
                        phase = .download
                        currentSpeed = currentDownload
                        // Download is first half: 0.0 to 0.5
                        progress = min(elapsed / 12.0 * 0.5, 0.5)
                    } else {
                        phase = .connecting
                        currentSpeed = nil
                        progress = 0.05
                    }

                    onProgress(SpeedTestProgress(
                        provider: providerName,
                        phase: phase,
                        progress: progress,
                        currentSpeed: currentSpeed
                    ))
                } else {
                    // Parallel mode - show both speeds
                    let progress = min(elapsed / 15.0, 0.95)
                    let phase: SpeedTestProgress.TestPhase = (currentDownload > 0 || currentUpload > 0) ? .parallel : .connecting
                    onProgress(SpeedTestProgress(
                        provider: providerName,
                        phase: phase,
                        progress: progress,
                        currentSpeed: max(currentDownload, currentUpload),
                        downloadSpeed: currentDownload > 0 ? currentDownload : nil,
                        uploadSpeed: currentUpload > 0 ? currentUpload : nil
                    ))
                }
            }

            process.terminationHandler = { _ in
                outputPipe.fileHandleForReading.readabilityHandler = nil

                // Parse final results from text output
                var finalDownload: Double = 0
                var finalUpload: Double = 0
                var latency: Double? = nil

                let allOutput = state.output
                let fallbackDownload = state.downloadSpeed
                let fallbackUpload = state.uploadSpeed

                // Parse "Downlink capacity: X.XXX Mbps"
                if let range = allOutput.range(of: "Downlink capacity:\\s*([\\d.]+)\\s*Mbps", options: .regularExpression) {
                    let match = allOutput[range]
                    if let speedMatch = match.range(of: "[\\d.]+", options: .regularExpression) {
                        finalDownload = Double(match[speedMatch]) ?? fallbackDownload
                    }
                } else {
                    finalDownload = fallbackDownload
                }

                // Parse "Uplink capacity: X.XXX Mbps"
                if let range = allOutput.range(of: "Uplink capacity:\\s*([\\d.]+)\\s*Mbps", options: .regularExpression) {
                    let match = allOutput[range]
                    if let speedMatch = match.range(of: "[\\d.]+", options: .regularExpression) {
                        finalUpload = Double(match[speedMatch]) ?? fallbackUpload
                    }
                } else {
                    finalUpload = fallbackUpload
                }

                // Parse "Idle Latency: X.XXX milliseconds"
                if let range = allOutput.range(of: "Idle Latency:\\s*([\\d.]+)", options: .regularExpression) {
                    let match = allOutput[range]
                    if let latencyMatch = match.range(of: "[\\d.]+", options: .regularExpression) {
                        latency = Double(match[latencyMatch])
                    }
                }

                onProgress(SpeedTestProgress(provider: providerName, phase: .complete, progress: 1.0, currentSpeed: finalDownload))

                continuation.resume(returning: SpeedTestResult(
                    provider: providerName,
                    downloadSpeed: finalDownload,
                    uploadSpeed: finalUpload,
                    latency: latency,
                    serverLocation: "Apple CDN",
                    timestamp: Date(),
                    error: nil
                ))
            }

            do {
                try process.run()
            } catch {
                onProgress(SpeedTestProgress(provider: providerName, phase: .failed, progress: 0, currentSpeed: nil))
                continuation.resume(returning: SpeedTestResult(
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
    }
}

// MARK: - Cloudflare Speed Test Provider

final class CloudflareSpeedTestProvider: SpeedTestProvider, @unchecked Sendable {
    let name = "Cloudflare"
    let icon = "cloud.fill"

    private let baseURL = "https://speed.cloudflare.com"
    private let downloadSizes = [100_000, 1_000_000, 10_000_000, 25_000_000] // 100KB, 1MB, 10MB, 25MB
    private let uploadSizes = [100_000, 1_000_000, 5_000_000] // 100KB, 1MB, 5MB

    func runTest(onProgress: @escaping (SpeedTestProgress) -> Void) async throws -> SpeedTestResult {
        onProgress(SpeedTestProgress(provider: name, phase: .connecting, progress: 0, currentSpeed: nil))

        // Measure latency first
        let latency = await measureLatency()

        // Download test
        onProgress(SpeedTestProgress(provider: name, phase: .download, progress: 0.1, currentSpeed: nil))
        let downloadSpeed = await measureDownload(onProgress: onProgress)

        // Upload test
        onProgress(SpeedTestProgress(provider: name, phase: .upload, progress: 0.6, currentSpeed: nil))
        let uploadSpeed = await measureUpload(onProgress: onProgress)

        onProgress(SpeedTestProgress(provider: name, phase: .complete, progress: 1.0, currentSpeed: downloadSpeed))

        return SpeedTestResult(
            provider: name,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            latency: latency,
            serverLocation: "Cloudflare Edge",
            timestamp: Date(),
            error: nil
        )
    }

    private func measureLatency() async -> Double? {
        let url = URL(string: "\(baseURL)/__down?bytes=0")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        var latencies: [Double] = []

        for _ in 0..<5 {
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
        // Return minimum latency (closest to actual RTT)
        return latencies.min()
    }

    private func measureDownload(onProgress: @escaping (SpeedTestProgress) -> Void) async -> Double {
        var totalBytes: Int64 = 0
        var totalTime: TimeInterval = 0
        var speeds: [Double] = []

        for (index, size) in downloadSizes.enumerated() {
            let url = URL(string: "\(baseURL)/__down?bytes=\(size)")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 30

            let start = Date()
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let elapsed = Date().timeIntervalSince(start)

                totalBytes += Int64(data.count)
                totalTime += elapsed

                let speedMbps = Double(data.count * 8) / elapsed / 1_000_000
                speeds.append(speedMbps)

                let progress = 0.1 + (Double(index + 1) / Double(downloadSizes.count)) * 0.4
                onProgress(SpeedTestProgress(provider: name, phase: .download, progress: progress, currentSpeed: speedMbps))
            } catch {
                continue
            }
        }

        // Return average speed weighted toward larger transfers
        guard !speeds.isEmpty else { return 0 }
        return Double(totalBytes * 8) / totalTime / 1_000_000
    }

    private func measureUpload(onProgress: @escaping (SpeedTestProgress) -> Void) async -> Double {
        var totalBytes: Int64 = 0
        var totalTime: TimeInterval = 0
        var speeds: [Double] = []

        for (index, size) in uploadSizes.enumerated() {
            let url = URL(string: "\(baseURL)/__up")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = generateRandomData(size: size)
            request.timeoutInterval = 30

            let start = Date()
            do {
                let (_, _) = try await URLSession.shared.data(for: request)
                let elapsed = Date().timeIntervalSince(start)

                totalBytes += Int64(size)
                totalTime += elapsed

                let speedMbps = Double(size * 8) / elapsed / 1_000_000
                speeds.append(speedMbps)

                let progress = 0.6 + (Double(index + 1) / Double(uploadSizes.count)) * 0.35
                onProgress(SpeedTestProgress(provider: name, phase: .upload, progress: progress, currentSpeed: speedMbps))
            } catch {
                continue
            }
        }

        guard !speeds.isEmpty else { return 0 }
        return Double(totalBytes * 8) / totalTime / 1_000_000
    }

    private func generateRandomData(size: Int) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress!, size)
        }
        return data
    }
}

// MARK: - M-Lab NDT7 Speed Test Provider

final class MLabSpeedTestProvider: SpeedTestProvider, @unchecked Sendable {
    let name = "M-Lab"
    let icon = "globe.americas.fill"

    private let locateURL = "https://locate.measurementlab.net/v2/nearest/ndt/ndt7"

    func runTest(onProgress: @escaping (SpeedTestProgress) -> Void) async throws -> SpeedTestResult {
        onProgress(SpeedTestProgress(provider: name, phase: .connecting, progress: 0, currentSpeed: nil))

        // Discover nearest server
        guard let serverInfo = await discoverServer() else {
            return SpeedTestResult(
                provider: name,
                downloadSpeed: 0,
                uploadSpeed: 0,
                latency: nil,
                serverLocation: nil,
                timestamp: Date(),
                error: "Failed to discover M-Lab server"
            )
        }

        onProgress(SpeedTestProgress(provider: name, phase: .download, progress: 0.1, currentSpeed: nil))

        // Run download test
        let downloadResult = await runDownloadTest(url: serverInfo.downloadURL, onProgress: onProgress)

        onProgress(SpeedTestProgress(provider: name, phase: .upload, progress: 0.55, currentSpeed: nil))

        // Run upload test
        let uploadResult = await runUploadTest(url: serverInfo.uploadURL, onProgress: onProgress)

        onProgress(SpeedTestProgress(provider: name, phase: .complete, progress: 1.0, currentSpeed: downloadResult.speed))

        return SpeedTestResult(
            provider: name,
            downloadSpeed: downloadResult.speed,
            uploadSpeed: uploadResult.speed,
            latency: downloadResult.latency ?? uploadResult.latency,
            serverLocation: serverInfo.location,
            timestamp: Date(),
            error: downloadResult.error ?? uploadResult.error
        )
    }

    private struct ServerInfo {
        let downloadURL: String
        let uploadURL: String
        let location: String
    }

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
            print("M-Lab server discovery failed: \(error)")
        }

        return nil
    }

    private struct TestResult {
        let speed: Double
        let latency: Double?
        let error: String?
    }

    private func runDownloadTest(url: String, onProgress: @escaping (SpeedTestProgress) -> Void) async -> TestResult {
        guard let wsURL = URL(string: url) else {
            return TestResult(speed: 0, latency: nil, error: "Invalid download URL")
        }

        return await withCheckedContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: wsURL, protocols: ["net.measurementlab.ndt.v7"])

            var totalBytes: Int64 = 0
            let startTime = Date()
            var lastMeasurement: NDT7Measurement?
            var completed = false

            func receiveMessage() {
                guard !completed else { return }

                task.receive { result in
                    switch result {
                    case .success(let message):
                        switch message {
                        case .data(let data):
                            totalBytes += Int64(data.count)
                            let elapsed = Date().timeIntervalSince(startTime)
                            let speedMbps = Double(totalBytes * 8) / elapsed / 1_000_000
                            let progress = min(0.1 + elapsed / 10.0 * 0.4, 0.5)
                            onProgress(SpeedTestProgress(provider: self.name, phase: .download, progress: progress, currentSpeed: speedMbps))

                        case .string(let text):
                            if let data = text.data(using: .utf8),
                               let measurement = try? JSONDecoder().decode(NDT7Measurement.self, from: data) {
                                lastMeasurement = measurement
                            }

                        @unknown default:
                            break
                        }

                        receiveMessage()

                    case .failure:
                        completed = true
                        let elapsed = Date().timeIntervalSince(startTime)
                        let speedMbps = totalBytes > 0 ? Double(totalBytes * 8) / elapsed / 1_000_000 : 0
                        let latency = lastMeasurement?.tcpInfo?.minRTT.map { Double($0) / 1000.0 }
                        continuation.resume(returning: TestResult(speed: speedMbps, latency: latency, error: nil))
                    }
                }
            }

            task.resume()
            receiveMessage()

            // Timeout after 12 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                guard !completed else { return }
                completed = true
                task.cancel(with: .goingAway, reason: nil)
                let elapsed = Date().timeIntervalSince(startTime)
                let speedMbps = totalBytes > 0 ? Double(totalBytes * 8) / elapsed / 1_000_000 : 0
                let latency = lastMeasurement?.tcpInfo?.minRTT.map { Double($0) / 1000.0 }
                continuation.resume(returning: TestResult(speed: speedMbps, latency: latency, error: nil))
            }
        }
    }

    private func runUploadTest(url: String, onProgress: @escaping (SpeedTestProgress) -> Void) async -> TestResult {
        guard let wsURL = URL(string: url) else {
            return TestResult(speed: 0, latency: nil, error: "Invalid upload URL")
        }

        return await withCheckedContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: wsURL, protocols: ["net.measurementlab.ndt.v7"])

            var totalBytesSent: Int64 = 0
            let startTime = Date()
            var lastMeasurement: NDT7Measurement?
            var completed = false
            let chunkSize = 1 << 13 // 8KB chunks

            func sendData() {
                guard !completed else { return }

                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= 10 {
                    // Test complete
                    completed = true
                    task.cancel(with: .goingAway, reason: nil)
                    let speedMbps = totalBytesSent > 0 ? Double(totalBytesSent * 8) / elapsed / 1_000_000 : 0
                    let latency = lastMeasurement?.tcpInfo?.minRTT.map { Double($0) / 1000.0 }
                    continuation.resume(returning: TestResult(speed: speedMbps, latency: latency, error: nil))
                    return
                }

                var data = Data(count: chunkSize)
                data.withUnsafeMutableBytes { ptr in
                    arc4random_buf(ptr.baseAddress!, chunkSize)
                }

                task.send(.data(data)) { error in
                    if error != nil {
                        guard !completed else { return }
                        completed = true
                        let elapsed = Date().timeIntervalSince(startTime)
                        let speedMbps = totalBytesSent > 0 ? Double(totalBytesSent * 8) / elapsed / 1_000_000 : 0
                        continuation.resume(returning: TestResult(speed: speedMbps, latency: nil, error: nil))
                        return
                    }

                    totalBytesSent += Int64(chunkSize)
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speedMbps = Double(totalBytesSent * 8) / elapsed / 1_000_000
                    let progress = 0.55 + elapsed / 10.0 * 0.4
                    onProgress(SpeedTestProgress(provider: self.name, phase: .upload, progress: min(progress, 0.95), currentSpeed: speedMbps))

                    sendData()
                }
            }

            func receiveMessages() {
                guard !completed else { return }

                task.receive { result in
                    if case .success(let message) = result,
                       case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let measurement = try? JSONDecoder().decode(NDT7Measurement.self, from: data) {
                        lastMeasurement = measurement
                    }
                    receiveMessages()
                }
            }

            task.resume()
            sendData()
            receiveMessages()
        }
    }
}

// MARK: - NDT7 Measurement Models

struct NDT7Measurement: Codable {
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

    struct AppInfo: Codable {
        let elapsedTime: Int?
        let numBytes: Int?

        enum CodingKeys: String, CodingKey {
            case elapsedTime = "ElapsedTime"
            case numBytes = "NumBytes"
        }
    }

    struct TCPInfo: Codable {
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

    var errorDescription: String? {
        switch self {
        case .parseError(let msg): return "Parse error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .timeout: return "Test timed out"
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

    private let providers: [SpeedTestProvider] = [
        AppleSpeedTestProvider(),
        CloudflareSpeedTestProvider(),
        MLabSpeedTestProvider()
    ]

    private var runningTask: Task<Void, Never>?

    var availableProviders: [(name: String, icon: String)] {
        providers.map { ($0.name, $0.icon) }
    }

    func stopAllTests() {
        runningTask?.cancel()
        runningTask = nil
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

        // Capture providers list before the task
        let providersToTest = providers

        // Run tests in a task (survives view destruction since we hold reference)
        runningTask = Task { [weak self] in
            for provider in providersToTest {
                // Check for cancellation before each test
                if Task.isCancelled { break }

                await MainActor.run { [weak self] in
                    self?.currentProvider = provider.name
                }

                do {
                    let result = try await provider.runTest { [weak self] progressUpdate in
                        Task { @MainActor in
                            self?.progress[provider.name] = progressUpdate
                        }
                    }

                    // Check for cancellation after test
                    if Task.isCancelled { break }

                    await MainActor.run { [weak self] in
                        self?.results.append(result)
                    }
                } catch {
                    if Task.isCancelled { break }

                    await MainActor.run { [weak self] in
                        self?.results.append(SpeedTestResult(
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

            await MainActor.run { [weak self] in
                self?.currentProvider = nil
                self?.isRunning = false
            }
        }
    }

    func runSingleTest(providerName: String) {
        guard let provider = providers.first(where: { $0.name == providerName }) else { return }
        guard !isRunning else { return }

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

        // Capture self weakly for the detached task
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
        runningTask?.cancel()
        runningTask = nil
        currentProvider = nil
        isRunning = false
    }
}
