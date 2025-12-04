import Foundation
import Network
import Combine

// MARK: - LAN Device

struct LANDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LANDevice, rhs: LANDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Test Result

struct LANSpeedResult: Identifiable {
    let id = UUID()
    let timestamp: Date
    let peerName: String
    let downloadSpeed: Double // Mbps
    let uploadSpeed: Double // Mbps
    let latency: Double // ms
    let bytesTransferred: Int64
    let duration: TimeInterval
}

// MARK: - Test Progress

struct LANTestProgress {
    enum Phase: String {
        case idle = "Idle"
        case connecting = "Connecting"
        case measuringLatency = "Measuring Latency"
        case download = "Download Test"
        case upload = "Upload Test"
        case complete = "Complete"
        case failed = "Failed"
    }

    var phase: Phase = .idle
    var progress: Double = 0 // 0.0 - 1.0
    var currentSpeed: Double? // Mbps
    var message: String = ""
}

// MARK: - LAN Speed Service

@MainActor
class LANSpeedService: ObservableObject {
    @Published var isServerRunning = false
    @Published var isClientRunning = false
    @Published var discoveredDevices: [LANDevice] = []
    @Published var testProgress = LANTestProgress()
    @Published var lastResult: LANSpeedResult?
    @Published var serverStatus = "Not running"
    @Published var connectedClients: [String] = []

    private let serviceType = "_nqspeedtest._tcp"
    private let serviceDomain = "local."
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnection: NWConnection?
    private var serverConnections: [NWConnection] = []

    private let testDuration: TimeInterval = 5.0 // seconds per direction
    private let chunkSize = 64 * 1024 // 64KB chunks

    // MARK: - Server Mode

    func startServer() {
        guard !isServerRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            listener = try NWListener(using: parameters)
            listener?.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: serviceType)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: .main)
            isServerRunning = true
            serverStatus = "Starting..."

        } catch {
            serverStatus = "Failed: \(error.localizedDescription)"
        }
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        serverConnections.forEach { $0.cancel() }
        serverConnections.removeAll()
        connectedClients.removeAll()
        isServerRunning = false
        serverStatus = "Not running"
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port {
                serverStatus = "Listening on port \(port)"
            } else {
                serverStatus = "Ready"
            }
        case .failed(let error):
            serverStatus = "Failed: \(error.localizedDescription)"
            isServerRunning = false
        case .cancelled:
            serverStatus = "Stopped"
            isServerRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        serverConnections.append(connection)

        let clientName = connection.endpoint.debugDescription
        connectedClients.append(clientName)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.handleServerConnection(connection)
                case .failed, .cancelled:
                    self?.removeServerConnection(connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func removeServerConnection(_ connection: NWConnection) {
        if let index = serverConnections.firstIndex(where: { $0 === connection }) {
            serverConnections.remove(at: index)
        }
        let clientName = connection.endpoint.debugDescription
        connectedClients.removeAll { $0 == clientName }
    }

    private func handleServerConnection(_ connection: NWConnection) {
        // Handle commands sequentially in a task
        Task {
            await self.serverCommandLoop(connection)
        }
    }

    private func serverCommandLoop(_ connection: NWConnection) async {
        while true {
            // Wait for next command
            let command = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                    if let data = data, let cmd = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: cmd)
                    } else if isComplete || error != nil {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }

            guard let command = command else { break }

            let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first ?? ""

            switch cmd {
            case "PING":
                let response = "PONG\n".data(using: .utf8)!
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    connection.send(content: response, completion: .contentProcessed { _ in
                        continuation.resume()
                    })
                }

            case "DOWNLOAD":
                // Client wants to download - server sends data, wait for completion
                await sendTestData(connection)

            case "UPLOAD":
                // Client wants to upload - server receives data, wait for completion
                await receiveTestData(connection)

            default:
                break
            }
        }
    }

    private func sendTestData(_ connection: NWConnection) async {
        let chunk = Data(repeating: 0xAB, count: chunkSize)
        let endTime = Date().addingTimeInterval(testDuration)

        while Date() < endTime {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                connection.send(content: chunk, completion: .contentProcessed { _ in
                    continuation.resume()
                })
            }
        }

        // Send end marker and wait for it to be sent
        let endMarker = "END\n".data(using: .utf8)!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: endMarker, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    private func receiveTestData(_ connection: NWConnection) async {
        var totalReceived: Int64 = 0
        let startTime = Date()

        while true {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: chunkSize * 2) { data, _, _, error in
                    if error != nil {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: data)
                    }
                }
            }

            guard let data = result, !data.isEmpty else { break }

            // Check for end marker anywhere in the data
            if let str = String(data: data, encoding: .utf8), str.contains("END") {
                // Don't count the END marker bytes
                let endIndex = str.range(of: "END")?.lowerBound
                if let idx = endIndex {
                    let bytesBeforeEnd = str.distance(from: str.startIndex, to: idx)
                    totalReceived += Int64(bytesBeforeEnd)
                }
                break
            }

            totalReceived += Int64(data.count)

            // Timeout after testDuration + buffer
            if Date().timeIntervalSince(startTime) > testDuration + 3 {
                break
            }
        }

        // Send acknowledgment with bytes received
        let ack = "ACK \(totalReceived)\n".data(using: .utf8)!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: ack, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    // MARK: - Client Mode (Discovery)

    func startDiscovery() {
        stopDiscovery()
        discoveredDevices.removeAll()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed(let error) = state {
                    print("Browser failed: \(error)")
                    self?.stopDiscovery()
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.updateDiscoveredDevices(results)
            }
        }

        browser?.start(queue: .main)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }

    private func updateDiscoveredDevices(_ results: Set<NWBrowser.Result>) {
        var devices: [LANDevice] = []

        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                let device = LANDevice(
                    id: "\(name).\(type).\(domain)",
                    name: name,
                    host: name,
                    port: 0 // Will resolve when connecting
                )
                devices.append(device)
            }
        }

        discoveredDevices = devices
    }

    // MARK: - Speed Test

    func runSpeedTest(to device: LANDevice) {
        guard !isClientRunning else { return }
        isClientRunning = true
        testProgress = LANTestProgress(phase: .connecting, progress: 0, message: "Connecting to \(device.name)...")

        // Find the browser result for this device
        guard let results = browser?.browseResults,
              let result = results.first(where: {
                  if case .service(let name, _, _, _) = $0.endpoint {
                      return name == device.name
                  }
                  return false
              }) else {
            testProgress = LANTestProgress(phase: .failed, message: "Device not found")
            isClientRunning = false
            return
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: result.endpoint, using: parameters)
        activeConnection = connection

        // Connection timeout
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
            await MainActor.run {
                if self.isClientRunning && self.testProgress.phase == .connecting {
                    self.testProgress = LANTestProgress(phase: .failed, message: "Connection timeout - is server mode enabled?")
                    connection.cancel()
                    self.activeConnection = nil
                    self.isClientRunning = false
                }
            }
        }

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    timeoutTask.cancel()
                    self?.performSpeedTest(connection, deviceName: device.name)
                case .failed(let error):
                    timeoutTask.cancel()
                    self?.testProgress = LANTestProgress(phase: .failed, message: error.localizedDescription)
                    self?.isClientRunning = false
                case .cancelled:
                    timeoutTask.cancel()
                    self?.isClientRunning = false
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    func cancelTest() {
        activeConnection?.cancel()
        activeConnection = nil
        isClientRunning = false
        testProgress = LANTestProgress(phase: .idle, message: "Cancelled")
    }

    private func performSpeedTest(_ connection: NWConnection, deviceName: String) {
        Task {
            // 1. Measure latency
            testProgress = LANTestProgress(phase: .measuringLatency, progress: 0.05, message: "Measuring latency...")
            let latency = await measureLatency(connection)

            // Check for timeout (-1 indicates failure)
            if latency < 0 {
                testProgress = LANTestProgress(phase: .failed, message: "No response - is server mode enabled?")
                connection.cancel()
                activeConnection = nil
                isClientRunning = false
                return
            }

            // 2. Download test (receive from server)
            testProgress = LANTestProgress(phase: .download, progress: 0.1, message: "Download test...")
            let downloadResult = await performDownloadTest(connection)

            // 3. Upload test (send to server)
            testProgress = LANTestProgress(phase: .upload, progress: 0.55, message: "Upload test...")
            let uploadResult = await performUploadTest(connection)

            // 4. Complete
            let result = LANSpeedResult(
                timestamp: Date(),
                peerName: deviceName,
                downloadSpeed: downloadResult.speed,
                uploadSpeed: uploadResult.speed,
                latency: latency,
                bytesTransferred: downloadResult.bytes + uploadResult.bytes,
                duration: downloadResult.duration + uploadResult.duration
            )

            lastResult = result
            testProgress = LANTestProgress(phase: .complete, progress: 1.0, message: "Complete")

            connection.cancel()
            activeConnection = nil
            isClientRunning = false
        }
    }

    private func measureLatency(_ connection: NWConnection) async -> Double {
        var latencies: [Double] = []

        for _ in 0..<5 {
            let start = Date()

            // Send PING with timeout
            let ping = "PING\n".data(using: .utf8)!

            let success = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        connection.send(content: ping, completion: .contentProcessed { _ in
                            continuation.resume()
                        })
                    }
                    // Wait for PONG
                    let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                            continuation.resume(returning: data)
                        }
                    }
                    return data != nil
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second timeout per ping
                    return false
                }
                if let result = await group.next() {
                    group.cancelAll()
                    return result
                }
                return false
            }

            if !success {
                // Timeout or failure - return early with failure indicator
                return -1
            }

            let elapsed = Date().timeIntervalSince(start) * 1000 // ms
            latencies.append(elapsed)
        }

        return latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
    }

    private func performDownloadTest(_ connection: NWConnection) async -> (speed: Double, bytes: Int64, duration: TimeInterval) {
        // Tell server to send data
        let cmd = "DOWNLOAD\n".data(using: .utf8)!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: cmd, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }

        var totalReceived: Int64 = 0
        let startTime = Date()

        while true {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: chunkSize * 2) { data, _, _, _ in
                    continuation.resume(returning: data)
                }
            }

            guard let data = result else { break }

            // Check for end marker
            if data.count < 10, let str = String(data: data, encoding: .utf8), str.contains("END") {
                break
            }

            totalReceived += Int64(data.count)

            let elapsed = Date().timeIntervalSince(startTime)
            let speedMbps = Double(totalReceived * 8) / elapsed / 1_000_000
            let progress = 0.1 + min(elapsed / testDuration, 1.0) * 0.4

            await MainActor.run {
                testProgress = LANTestProgress(phase: .download, progress: progress, currentSpeed: speedMbps, message: String(format: "%.1f Mbps", speedMbps))
            }

            if elapsed > testDuration + 2 {
                break
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let speed = totalReceived > 0 ? Double(totalReceived * 8) / duration / 1_000_000 : 0

        return (speed, totalReceived, duration)
    }

    private func performUploadTest(_ connection: NWConnection) async -> (speed: Double, bytes: Int64, duration: TimeInterval) {
        // Tell server to receive data
        let cmd = "UPLOAD\n".data(using: .utf8)!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: cmd, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }

        let chunk = Data(repeating: 0xCD, count: chunkSize)
        var totalSent: Int64 = 0
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(testDuration)

        while Date() < endTime {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                connection.send(content: chunk, completion: .contentProcessed { _ in
                    continuation.resume()
                })
            }

            totalSent += Int64(chunkSize)

            let elapsed = Date().timeIntervalSince(startTime)
            let speedMbps = Double(totalSent * 8) / elapsed / 1_000_000
            let progress = 0.55 + min(elapsed / testDuration, 1.0) * 0.4

            await MainActor.run {
                testProgress = LANTestProgress(phase: .upload, progress: progress, currentSpeed: speedMbps, message: String(format: "%.1f Mbps", speedMbps))
            }
        }

        // Send end marker
        let endMarker = "END\n".data(using: .utf8)!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: endMarker, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }

        // Wait for ACK with timeout
        let ackReceived = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let _ = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                        continuation.resume(returning: data)
                    }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second timeout
                return false
            }
            // Return first completed
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return false
        }
        _ = ackReceived

        let duration = Date().timeIntervalSince(startTime)
        let speed = totalSent > 0 ? Double(totalSent * 8) / duration / 1_000_000 : 0

        return (speed, totalSent, duration)
    }
}
