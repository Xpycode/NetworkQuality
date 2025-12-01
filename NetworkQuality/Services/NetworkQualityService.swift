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

    private var process: Process?
    private var wasCancelled = false

    func getAvailableInterfaces() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
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
            print("Failed to get interfaces: \(error)")
        }

        return ["en0", "en1", "pdp_ip0"]
    }

    func runTest(config: TestConfiguration) async throws -> NetworkQualityResult {
        guard !isRunning else {
            throw NetworkQualityError.executionFailed("Test already running")
        }

        isRunning = true
        wasCancelled = false
        progress = "Starting test..."
        verboseOutput = []
        currentDownloadSpeed = 0
        currentUploadSpeed = 0

        defer {
            isRunning = false
            process = nil
        }

        let process = Process()
        self.process = process
        // Use 'script' to allocate a pseudo-TTY, which makes networkQuality output real-time progress
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")

        var nqArguments: [String] = []

        switch config.mode {
        case .sequential:
            nqArguments.append("-s")
        case .downloadOnly:
            nqArguments.append("-d")
        case .uploadOnly:
            nqArguments.append("-u")
        case .parallel:
            break
        }

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
                nqArguments.append("-f")
                nqArguments.append(protocols.joined(separator: ","))
            }
        } else if let enableL4S = config.enableL4S {
            nqArguments.append("-f")
            nqArguments.append(enableL4S ? "L4S" : "noL4S")
        }

        if !config.networkInterface.isEmpty {
            nqArguments.append("-I")
            nqArguments.append(config.networkInterface)
        }

        if !config.customConfigURL.isEmpty {
            nqArguments.append("-C")
            nqArguments.append(config.customConfigURL)
        }

        if config.maxRunTime > 0 {
            nqArguments.append("-M")
            nqArguments.append(String(config.maxRunTime))
        }

        if config.disableTLSVerification {
            nqArguments.append("-k")
        }

        if config.usePrivateRelay {
            nqArguments.append("-p")
        }

        if config.verbose {
            nqArguments.append("-v")
        }

        // Build the networkQuality command string for script
        let nqCommand = "/usr/bin/networkQuality " + nqArguments.joined(separator: " ")
        // script args: -q (quiet), /dev/null (no output file), /bin/sh -c "command"
        process.arguments = ["-q", "/dev/null", "/bin/sh", "-c", nqCommand]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Thread-safe data accumulator
        let dataAccumulator = DataAccumulator()

        // Read stderr incrementally for progress updates
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                dataAccumulator.appendError(data)
                if let output = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self?.parseProgressOutput(output)
                    }
                }
            }
        }

        // Also read stdout incrementally (progress may appear there too)
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                dataAccumulator.appendOutput(data)
                if let output = String(data: data, encoding: .utf8) {
                    // Parse for progress
                    Task { @MainActor in
                        self?.parseProgressOutput(output)
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            throw NetworkQualityError.executionFailed(error.localizedDescription)
        }

        // Wait for process to complete without blocking the main thread
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                // Clean up handlers
                errorPipe.fileHandleForReading.readabilityHandler = nil
                outputPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume()
            }
        }

        // Read any remaining data
        dataAccumulator.appendOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())
        dataAccumulator.appendError(errorPipe.fileHandleForReading.readDataToEndOfFile())

        progress = "Test completed"
        let outputData = dataAccumulator.outputData
        let errorData = dataAccumulator.errorData

        if process.terminationStatus != 0 {
            if wasCancelled {
                throw NetworkQualityError.cancelled
            }
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NetworkQualityError.executionFailed(errorString)
        }

        guard let fullOutput = String(data: outputData, encoding: .utf8) else {
            throw NetworkQualityError.parseError("Could not decode output")
        }

        // Parse text summary output
        // Format:
        // ==== SUMMARY ====
        // Uplink capacity: 8.934 Mbps
        // Downlink capacity: 120.050 Mbps
        // Uplink Responsiveness: High (45.859 milliseconds | 1308 RPM)
        // Idle Latency: 52.130 milliseconds | 1150 RPM

        var downloadMbps: Double = 0
        var uploadMbps: Double = 0
        var responsivenessRPM: Double?
        var idleLatencyMs: Double?

        let lines = fullOutput.components(separatedBy: CharacterSet(charactersIn: "\r\n"))

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse "Downlink capacity: XXX Mbps"
            if trimmed.contains("Downlink capacity:") {
                if let match = trimmed.range(of: "[\\d.]+(?=\\s*Mbps)", options: .regularExpression) {
                    downloadMbps = Double(trimmed[match]) ?? 0
                }
            }

            // Parse "Uplink capacity: XXX Mbps"
            if trimmed.contains("Uplink capacity:") {
                if let match = trimmed.range(of: "[\\d.]+(?=\\s*Mbps)", options: .regularExpression) {
                    uploadMbps = Double(trimmed[match]) ?? 0
                }
            }

            // Parse responsiveness: "... | 1308 RPM)" - take the first RPM value found
            if responsivenessRPM == nil && trimmed.contains("RPM") && trimmed.contains("Responsiveness") {
                if let match = trimmed.range(of: "\\d+(?=\\s*RPM)", options: .regularExpression) {
                    responsivenessRPM = Double(trimmed[match])
                }
            }

            // Parse "Idle Latency: XX.XXX milliseconds | YYY RPM"
            if trimmed.contains("Idle Latency:") {
                if let match = trimmed.range(of: "[\\d.]+(?=\\s*milliseconds)", options: .regularExpression) {
                    idleLatencyMs = Double(trimmed[match])
                }
            }
        }

        // Validate we got at least some results
        if downloadMbps == 0 && uploadMbps == 0 {
            throw NetworkQualityError.parseError("Could not parse results from output: \(fullOutput.prefix(500))")
        }

        return NetworkQualityResult(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            responsivenessRPM: responsivenessRPM,
            idleLatencyMs: idleLatencyMs,
            interfaceName: config.networkInterface.isEmpty ? nil : config.networkInterface
        )
    }

    func cancelTest() {
        wasCancelled = true
        process?.terminate()
        isRunning = false
        progress = "Cancelled"
    }

    private func parseProgressOutput(_ output: String) {
        // Parse progress lines like: "Downlink: 123.456 Mbps, 472 RPM - Uplink: 8.200 Mbps, 1130 RPM"
        // The output may contain carriage returns for terminal updates
        let lines = output.components(separatedBy: CharacterSet(charactersIn: "\r\n"))

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse downlink speed
            if let downlinkRange = trimmed.range(of: "Downlink:\\s*([\\d.]+)\\s*Mbps", options: .regularExpression) {
                let match = trimmed[downlinkRange]
                if let speedMatch = match.range(of: "[\\d.]+", options: .regularExpression) {
                    if let speed = Double(match[speedMatch]) {
                        currentDownloadSpeed = speed
                    }
                }
            }

            // Parse uplink speed
            if let uplinkRange = trimmed.range(of: "Uplink:\\s*([\\d.]+)\\s*Mbps", options: .regularExpression) {
                let match = trimmed[uplinkRange]
                if let speedMatch = match.range(of: "[\\d.]+", options: .regularExpression) {
                    if let speed = Double(match[speedMatch]) {
                        currentUploadSpeed = speed
                    }
                }
            }

            // Update progress text if we have any speeds
            if currentDownloadSpeed > 0 || currentUploadSpeed > 0 {
                progress = String(format: "↓ %.1f Mbps  ↑ %.1f Mbps", currentDownloadSpeed, currentUploadSpeed)
            }

            // Add to verbose output if enabled
            if !trimmed.isEmpty && !trimmed.hasPrefix("\u{1B}") {
                verboseOutput.append(trimmed)
                // Keep only last 100 lines
                if verboseOutput.count > 100 {
                    verboseOutput.removeFirst()
                }
            }
        }
    }

    private func parseSpeedString(_ speedString: String) -> Double? {
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

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000)
        } else if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        } else {
            return String(format: "%.0f Kbps", mbps * 1000)
        }
    }

    func discoverBonjourServers() async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
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
            print("Failed to discover Bonjour servers: \(error)")
        }

        return []
    }
}

// Thread-safe data accumulator for capturing process output
private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _outputData = Data()
    private var _errorData = Data()

    var outputData: Data {
        lock.lock()
        defer { lock.unlock() }
        return _outputData
    }

    var errorData: Data {
        lock.lock()
        defer { lock.unlock() }
        return _errorData
    }

    func appendOutput(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        _outputData.append(data)
    }

    func appendError(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        _errorData.append(data)
    }
}
