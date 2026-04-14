import Foundation
import os.log

// MARK: - Shared Constants

enum NetworkQualityConstants {
    // Paths
    static let networkQualityPath = "/usr/bin/networkQuality"
    static let scriptPath = "/usr/bin/script"
    static let ifconfigPath = "/sbin/ifconfig"

    // Regex patterns for parsing
    enum Patterns {
        static let speedValue = "[\\d.]+"
        static let speedMbps = "([\\d.]+)\\s*Mbps"
        static let downlinkProgress = "Downlink:\\s*([\\d.]+)\\s*Mbps"
        static let uplinkProgress = "Uplink:\\s*([\\d.]+)\\s*Mbps"
        static let downlinkCapacity = "Downlink capacity:\\s*([\\d.]+)\\s*Mbps"
        static let uplinkCapacity = "Uplink capacity:\\s*([\\d.]+)\\s*Mbps"
        static let idleLatency = "Idle Latency:\\s*([\\d.]+)"
        static let rpmValue = "(\\d+)\\s*RPM"
        static let responsivenessRPM = "Responsiveness.*?(\\d+)\\s*RPM"
    }

    // Timing
    static let progressPollInterval: UInt64 = 100_000_000  // 100ms in nanoseconds
    static let secondInNanoseconds: UInt64 = 1_000_000_000
    static let expectedProgressLines = 100
    static let maxProgressPercentage = 0.99

    // Buffer sizes
    static let verboseOutputMaxLines = 100
    static let bitsPerByte = 8
    static let megabit = 1_000_000.0
}

// MARK: - Logger

enum NetworkQualityLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "NetworkQuality"

    static let runner = Logger(subsystem: subsystem, category: "AppleNetworkQualityRunner")
    static let service = Logger(subsystem: subsystem, category: "NetworkQualityService")
    static let multiServer = Logger(subsystem: subsystem, category: "MultiServerTest")
    static let geoIP = Logger(subsystem: subsystem, category: "GeoIP")
    static let vpn = Logger(subsystem: subsystem, category: "VPN")
    static let history = Logger(subsystem: subsystem, category: "History")
}

// MARK: - Ring Buffer for Verbose Output

struct RingBuffer<Element> {
    private var buffer: [Element?]
    private var writeIndex = 0
    private var count_ = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    var count: Int { count_ }
    var isEmpty: Bool { count_ == 0 }

    mutating func append(_ element: Element) {
        buffer[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count_ = min(count_ + 1, capacity)
    }

    func toArray() -> [Element] {
        guard count_ > 0 else { return [] }

        if count_ < capacity {
            return buffer[0..<count_].compactMap { $0 }
        }

        // Buffer is full - read from writeIndex to end, then start to writeIndex
        var result: [Element] = []
        result.reserveCapacity(capacity)
        for i in 0..<capacity {
            let index = (writeIndex + i) % capacity
            if let element = buffer[index] {
                result.append(element)
            }
        }
        return result
    }

    mutating func clear() {
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count_ = 0
    }
}

// MARK: - Sendable Ring Buffer (Actor-based)

actor SendableRingBuffer<Element: Sendable> {
    private var buffer: RingBuffer<Element>

    init(capacity: Int) {
        self.buffer = RingBuffer(capacity: capacity)
    }

    func append(_ element: Element) {
        buffer.append(element)
    }

    func toArray() -> [Element] {
        buffer.toArray()
    }

    func clear() {
        buffer.clear()
    }

    var count: Int { buffer.count }
}

// MARK: - Process Output Accumulator (Actor-based)

actor ProcessOutputAccumulator {
    private var outputData = Data()
    private var errorData = Data()

    func appendOutput(_ data: Data) {
        outputData.append(data)
    }

    func appendError(_ data: Data) {
        errorData.append(data)
    }

    func getOutputData() -> Data {
        outputData
    }

    func getErrorData() -> Data {
        errorData
    }

    func getOutputString() -> String? {
        String(data: outputData, encoding: .utf8)
    }

    func getErrorString() -> String? {
        String(data: errorData, encoding: .utf8)
    }
}

// MARK: - Runner Configuration

struct RunnerConfiguration {
    var mode: TestMode = .parallel
    var protocolSelection: ProtocolSelection = .auto
    var networkInterface: String = ""
    var customConfigURL: String = ""
    var maxRunTime: Int = 0
    var disableTLSVerification: Bool = false
    var usePrivateRelay: Bool = false
    var verbose: Bool = false
    var enableL4S: Bool? = nil
    var useJSONOutput: Bool = false

    init() {}

    init(from config: TestConfiguration) {
        self.mode = config.mode
        self.protocolSelection = config.protocolSelection
        self.networkInterface = config.networkInterface
        self.customConfigURL = config.customConfigURL
        self.maxRunTime = config.maxRunTime
        self.disableTLSVerification = config.disableTLSVerification
        self.usePrivateRelay = config.usePrivateRelay
        self.verbose = config.verbose
        self.enableL4S = config.enableL4S
    }
}

// MARK: - Runner Progress

struct RunnerProgress: Sendable {
    let downloadSpeed: Double
    let uploadSpeed: Double
    let phase: Phase
    let progressPercentage: Double

    enum Phase: Sendable {
        case connecting
        case download
        case upload
        case parallel
        case complete
    }
}

// MARK: - Runner Result

struct RunnerResult: Sendable {
    let downloadMbps: Double
    let uploadMbps: Double
    let responsivenessRPM: Double?
    let idleLatencyMs: Double?
    let rawOutput: String
}

// MARK: - Apple NetworkQuality Runner

actor AppleNetworkQualityRunner {
    private var currentProcess: Process?
    private var isCancelled = false

    // MARK: - Build Arguments

    nonisolated func buildArguments(for config: RunnerConfiguration) -> [String] {
        var args: [String] = []

        // Mode flags
        switch config.mode {
        case .sequential:
            args.append("-s")
        case .downloadOnly:
            args.append("-d")
        case .uploadOnly:
            args.append("-u")
        case .parallel:
            break
        }

        // Protocol selection
        if config.protocolSelection != .auto {
            var protocols: [String] = []
            switch config.protocolSelection {
            case .h1:
                protocols.append("h1")
            case .h2:
                protocols.append("h2")
            case .h3:
                protocols.append("h3")
            case .auto:
                break
            }
            if let enableL4S = config.enableL4S {
                protocols.append(enableL4S ? "L4S" : "noL4S")
            }
            if !protocols.isEmpty {
                args.append("-f")
                args.append(protocols.joined(separator: ","))
            }
        } else if let enableL4S = config.enableL4S {
            args.append("-f")
            args.append(enableL4S ? "L4S" : "noL4S")
        }

        // Interface
        if !config.networkInterface.isEmpty {
            args.append("-I")
            args.append(config.networkInterface)
        }

        // Custom config URL
        if !config.customConfigURL.isEmpty {
            args.append("-C")
            args.append(config.customConfigURL)
        }

        // Max run time
        if config.maxRunTime > 0 {
            args.append("-M")
            args.append(String(config.maxRunTime))
        }

        // TLS verification
        if config.disableTLSVerification {
            args.append("-k")
        }

        // Private relay
        if config.usePrivateRelay {
            args.append("-p")
        }

        // Verbose
        if config.verbose {
            args.append("-v")
        }

        // JSON output
        if config.useJSONOutput {
            args.append("-c")
        }

        return args
    }

    // MARK: - Run Test with Live Progress

    func runTest(
        config: RunnerConfiguration,
        onProgress: @escaping @Sendable (RunnerProgress) -> Void
    ) async throws -> RunnerResult {
        guard !isCancelled else {
            throw NetworkQualityError.cancelled
        }

        // Verify networkQuality exists
        guard FileManager.default.fileExists(atPath: NetworkQualityConstants.networkQualityPath) else {
            throw NetworkQualityError.commandNotFound
        }

        let logger = NetworkQualityLogger.runner

        // Build arguments for networkQuality
        let nqArgs = buildArguments(for: config)
        logger.debug("Running networkQuality with args: \(nqArgs.joined(separator: " "))")

        // Create process using script for pseudo-TTY (enables real-time output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: NetworkQualityConstants.scriptPath)

        // Build arguments for script: -q /dev/null networkQuality [args...]
        // Using script directly with networkQuality avoids shell interpolation
        var scriptArgs = ["-q", "/dev/null", NetworkQualityConstants.networkQualityPath]
        scriptArgs.append(contentsOf: nqArgs)
        process.arguments = scriptArgs

        currentProcess = process

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let accumulator = ProcessOutputAccumulator()

        // State tracking for progress
        let progressState = ProgressState()
        let startTime = Date()
        let isSequential = config.mode == .sequential

        // Setup output handlers
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            Task {
                await accumulator.appendOutput(data)
                if let output = String(data: data, encoding: .utf8) {
                    await self.parseProgress(output, state: progressState, isSequential: isSequential, startTime: startTime, onProgress: onProgress)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            Task {
                await accumulator.appendError(data)
                if let output = String(data: data, encoding: .utf8) {
                    await self.parseProgress(output, state: progressState, isSequential: isSequential, startTime: startTime, onProgress: onProgress)
                }
            }
        }

        do {
            try process.run()
        } catch {
            logger.error("Failed to start networkQuality: \(error.localizedDescription)")
            throw NetworkQualityError.executionFailed(error.localizedDescription)
        }

        // Wait for process to complete
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume()
            }
        }

        // Read any remaining data
        let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
        await accumulator.appendOutput(remainingOutput)
        await accumulator.appendError(remainingError)

        currentProcess = nil

        // Check termination status
        if process.terminationStatus != 0 {
            if isCancelled {
                throw NetworkQualityError.cancelled
            }
            let errorString = await accumulator.getErrorString() ?? "Unknown error"
            logger.error("networkQuality failed with status \(process.terminationStatus): \(errorString)")
            throw NetworkQualityError.executionFailed(errorString)
        }

        // Parse results
        guard let fullOutput = await accumulator.getOutputString() else {
            throw NetworkQualityError.parseError("Could not decode output")
        }

        let result = parseResults(from: fullOutput)

        // Send completion progress
        onProgress(RunnerProgress(
            downloadSpeed: result.downloadMbps,
            uploadSpeed: result.uploadMbps,
            phase: .complete,
            progressPercentage: 1.0
        ))

        logger.info("Test complete: \(result.downloadMbps) Mbps down, \(result.uploadMbps) Mbps up")

        return result
    }

    // MARK: - Cancel

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        NetworkQualityLogger.runner.info("Test cancelled")
    }

    func reset() {
        isCancelled = false
        currentProcess = nil
    }

    // MARK: - Simple Run (No Progress)

    func runSimple(config: RunnerConfiguration) async throws -> RunnerResult {
        guard !isCancelled else {
            throw NetworkQualityError.cancelled
        }

        guard FileManager.default.fileExists(atPath: NetworkQualityConstants.networkQualityPath) else {
            throw NetworkQualityError.commandNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: NetworkQualityConstants.networkQualityPath)
        process.arguments = buildArguments(for: config)

        currentProcess = process

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw NetworkQualityError.executionFailed(error.localizedDescription)
        }

        currentProcess = nil

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            if isCancelled {
                throw NetworkQualityError.cancelled
            }
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NetworkQualityError.executionFailed(errorString)
        }

        guard let fullOutput = String(data: outputData, encoding: .utf8) else {
            throw NetworkQualityError.parseError("Could not decode output")
        }

        return parseResults(from: fullOutput)
    }

    // MARK: - Progress Parsing

    private func parseProgress(
        _ output: String,
        state: ProgressState,
        isSequential: Bool,
        startTime: Date,
        onProgress: @escaping @Sendable (RunnerProgress) -> Void
    ) async {
        let lines = output.components(separatedBy: CharacterSet(charactersIn: "\r\n"))

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse downlink speed
            if let speed = extractSpeed(from: trimmed, pattern: NetworkQualityConstants.Patterns.downlinkProgress) {
                await state.setDownloadSpeed(speed)
            }

            // Parse uplink speed
            if let speed = extractSpeed(from: trimmed, pattern: NetworkQualityConstants.Patterns.uplinkProgress) {
                await state.setUploadSpeed(speed)
                let inUploadPhase = await state.isInUploadPhase
                if isSequential && !inUploadPhase {
                    await state.enterUploadPhase()
                }
            }
        }

        // Calculate progress
        let downloadSpeed = await state.downloadSpeed
        let uploadSpeed = await state.uploadSpeed
        let elapsed = Date().timeIntervalSince(startTime)

        let phase: RunnerProgress.Phase
        let progressPercentage: Double

        if isSequential {
            if await state.isInUploadPhase {
                phase = .upload
                let uploadStartTime = await state.uploadPhaseStartTime ?? Date()
                let uploadElapsed = Date().timeIntervalSince(uploadStartTime)
                progressPercentage = min(0.5 + uploadElapsed / 12.0 * 0.45, 0.95)
            } else if downloadSpeed > 0 {
                phase = .download
                progressPercentage = min(elapsed / 12.0 * 0.5, 0.5)
            } else {
                phase = .connecting
                progressPercentage = 0.05
            }
        } else {
            if downloadSpeed > 0 || uploadSpeed > 0 {
                phase = .parallel
            } else {
                phase = .connecting
            }
            progressPercentage = min(elapsed / 15.0, 0.95)
        }

        onProgress(RunnerProgress(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            phase: phase,
            progressPercentage: progressPercentage
        ))
    }

    // MARK: - Result Parsing

    /// Parses test results from networkQuality output.
    /// Attempts JSON parsing first (for `-c` output), falls back to text parsing for human-readable output.
    /// - Parameter output: The raw output string from networkQuality command
    /// - Returns: Parsed RunnerResult with speed and quality metrics
    nonisolated func parseResults(from output: String) -> RunnerResult {
        // Try JSON parsing first (for -c output)
        if let jsonResult = parseJSONResults(from: output) {
            return jsonResult
        }

        // Fall back to text parsing for human-readable output
        return parseTextResults(from: output)
    }

    /// Parses JSON output from networkQuality -c command.
    /// JSON format provides more reliable parsing compared to text output.
    private nonisolated func parseJSONResults(from output: String) -> RunnerResult? {
        // Find JSON object in output (may be mixed with other text)
        guard let jsonStart = output.firstIndex(of: "{"),
              let jsonEnd = output.lastIndex(of: "}") else {
            return nil
        }

        let jsonString = String(output[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return nil
            }

            // Extract download throughput (in bits per second, convert to Mbps)
            let downloadBps = json["dl_throughput"] as? Double ?? 0
            let downloadMbps = downloadBps / NetworkQualityConstants.megabit

            // Extract upload throughput (in bits per second, convert to Mbps)
            let uploadBps = json["ul_throughput"] as? Double ?? 0
            let uploadMbps = uploadBps / NetworkQualityConstants.megabit

            // Extract responsiveness (RPM)
            let responsivenessRPM: Double?
            if let rpm = json["responsiveness"] as? Int {
                responsivenessRPM = Double(rpm)
            } else if let rpm = json["responsiveness"] as? Double {
                responsivenessRPM = rpm
            } else {
                responsivenessRPM = nil
            }

            // Extract base RTT (idle latency in milliseconds)
            let idleLatencyMs: Double?
            if let rtt = json["base_rtt"] as? Int {
                idleLatencyMs = Double(rtt)
            } else if let rtt = json["base_rtt"] as? Double {
                idleLatencyMs = rtt
            } else {
                idleLatencyMs = nil
            }

            NetworkQualityLogger.runner.debug("Parsed JSON results: dl=\(downloadMbps) ul=\(uploadMbps) rpm=\(responsivenessRPM ?? 0)")

            return RunnerResult(
                downloadMbps: downloadMbps,
                uploadMbps: uploadMbps,
                responsivenessRPM: responsivenessRPM,
                idleLatencyMs: idleLatencyMs,
                rawOutput: output
            )
        } catch {
            NetworkQualityLogger.runner.debug("JSON parsing failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Parses human-readable text output from networkQuality command.
    /// Used as fallback when JSON output is not available.
    private nonisolated func parseTextResults(from output: String) -> RunnerResult {
        var downloadMbps: Double = 0
        var uploadMbps: Double = 0
        var responsivenessRPM: Double?
        var idleLatencyMs: Double?

        let lines = output.components(separatedBy: CharacterSet(charactersIn: "\r\n"))

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse "Downlink capacity: XXX Mbps"
            if trimmed.contains("Downlink capacity:") {
                if let speed = extractSpeed(from: trimmed, pattern: NetworkQualityConstants.Patterns.downlinkCapacity) {
                    downloadMbps = speed
                }
            }

            // Parse "Uplink capacity: XXX Mbps"
            if trimmed.contains("Uplink capacity:") {
                if let speed = extractSpeed(from: trimmed, pattern: NetworkQualityConstants.Patterns.uplinkCapacity) {
                    uploadMbps = speed
                }
            }

            // Parse responsiveness RPM
            if responsivenessRPM == nil && trimmed.contains("RPM") && trimmed.contains("Responsiveness") {
                if let range = trimmed.range(of: NetworkQualityConstants.Patterns.rpmValue, options: .regularExpression) {
                    let match = trimmed[range]
                    if let numRange = match.range(of: "\\d+", options: .regularExpression) {
                        responsivenessRPM = Double(match[numRange])
                    }
                }
            }

            // Parse "Idle Latency: XX.XXX milliseconds"
            if trimmed.contains("Idle Latency:") {
                if let range = trimmed.range(of: NetworkQualityConstants.Patterns.idleLatency, options: .regularExpression) {
                    let match = trimmed[range]
                    if let numRange = match.range(of: NetworkQualityConstants.Patterns.speedValue, options: .regularExpression) {
                        idleLatencyMs = Double(match[numRange])
                    }
                }
            }
        }

        return RunnerResult(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            responsivenessRPM: responsivenessRPM,
            idleLatencyMs: idleLatencyMs,
            rawOutput: output
        )
    }

    // MARK: - Helpers

    nonisolated private func extractSpeed(from text: String, pattern: String) -> Double? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let match = text[range]
        guard let speedRange = match.range(of: NetworkQualityConstants.Patterns.speedValue, options: .regularExpression) else { return nil }
        return Double(match[speedRange])
    }

    // MARK: - Static Utilities

    static func getAvailableInterfaces() async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: NetworkQualityConstants.ifconfigPath)
        process.arguments = ["-l"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: " ")
                    .filter { !$0.isEmpty }
            }
        } catch {
            NetworkQualityLogger.runner.error("Failed to get interfaces: \(error.localizedDescription)")
        }

        return ["en0", "en1", "pdp_ip0"]
    }

    static func discoverBonjourServers() async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: NetworkQualityConstants.networkQualityPath)
        process.arguments = ["-b"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains("Discovering") }
            }
        } catch {
            NetworkQualityLogger.runner.error("Failed to discover Bonjour servers: \(error.localizedDescription)")
        }

        return []
    }
}

// MARK: - Progress State (Actor)

private actor ProgressState {
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0
    var isInUploadPhase = false
    var uploadPhaseStartTime: Date?

    func setDownloadSpeed(_ speed: Double) {
        downloadSpeed = speed
    }

    func setUploadSpeed(_ speed: Double) {
        uploadSpeed = speed
    }

    func enterUploadPhase() {
        isInUploadPhase = true
        uploadPhaseStartTime = Date()
    }
}

// MARK: - Speed Formatting Utility

enum SpeedFormatter {
    static func format(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000)
        } else if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        } else if mbps > 0 {
            return String(format: "%.0f Kbps", mbps * 1000)
        } else {
            return "0 Mbps"
        }
    }

    static func parse(_ speedString: String) -> Double? {
        let components = speedString.components(separatedBy: " ")
        guard components.count >= 2,
              let value = Double(components[0]) else {
            return nil
        }

        let unit = components[1].lowercased()
        switch unit {
        case "gbps":
            return value * 1000
        case "mbps":
            return value
        case "kbps":
            return value / 1000
        default:
            return value
        }
    }
}
