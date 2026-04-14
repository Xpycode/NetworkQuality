import SwiftUI

struct LANSpeedTestView: View {
    @ObservedObject var historyManager: HistoryManager
    @StateObject private var service = LANSpeedService()
    @State private var selectedDevice: LANDevice?
    @AppStorage("speedUnit") private var speedUnitRaw = SpeedUnit.mbps.rawValue

    private var speedUnit: SpeedUnit {
        SpeedUnit(rawValue: speedUnitRaw) ?? .mbps
    }

    var body: some View {
        HSplitView {
            // Left panel: Server mode and device list
            leftPanel
                .frame(minWidth: 280, maxWidth: 350)

            // Right panel: Test results
            rightPanel
        }
        .onAppear {
            service.startDiscovery()
        }
        .onDisappear {
            service.stopDiscovery()
        }
        .onChange(of: service.lastResult?.id) { _, newId in
            // Save to history when test completes
            if let result = service.lastResult, newId != nil {
                historyManager.saveLANSpeedResult(
                    peerName: result.peerName,
                    downloadSpeed: result.downloadSpeed,
                    uploadSpeed: result.uploadSpeed,
                    latency: result.latency,
                    bytesTransferred: result.bytesTransferred,
                    duration: result.duration
                )
            }
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "network")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("LAN Speed Test")
                        .font(.headline)
                }

                Text("Test network speed between Macs on your local network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            Divider()

            // Server toggle
            serverSection
                .padding()

            Divider()

            // Device list
            deviceListSection
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server Mode")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { service.isServerRunning },
                    set: { newValue in
                        if newValue {
                            service.startServer()
                        } else {
                            service.stopServer()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(service.isServerRunning ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(service.serverStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !service.connectedClients.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(service.connectedClients, id: \.self) { client in
                        Text(client)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Enable server mode to allow other Macs to test speed to this device.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available Devices")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Button {
                    service.startDiscovery()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if service.discoveredDevices.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Searching for devices...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Make sure other Macs have Server Mode enabled")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List(service.discoveredDevices, selection: $selectedDevice) { device in
                    DeviceRow(device: device, isSelected: selectedDevice == device)
                        .tag(device)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 20) {
            if let device = selectedDevice {
                // Selected device header
                HStack {
                    Image(systemName: "desktopcomputer")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text(device.name)
                            .font(.headline)
                        Text("Selected for testing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if service.isClientRunning {
                        Button("Cancel") {
                            service.cancelTest()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Run Test") {
                            service.runSpeedTest(to: device)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Progress or results
                if service.isClientRunning {
                    testProgressView
                } else if let result = service.lastResult {
                    resultView(result)
                } else {
                    emptyResultView
                }
            } else {
                noSelectionView
            }

            Spacer()
        }
        .padding()
    }

    private var testProgressView: some View {
        VStack(spacing: 16) {
            // Phase indicator
            HStack {
                Image(systemName: phaseIcon(service.testProgress.phase))
                    .font(.title3)
                    .foregroundStyle(.blue)

                Text(service.testProgress.phase.rawValue)
                    .font(.headline)

                Spacer()

                if let speed = service.testProgress.currentSpeed {
                    let formatted = speedUnit.format(speed)
                    Text("\(formatted.value) \(formatted.unit)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }

            ProgressView(value: service.testProgress.progress)
                .progressViewStyle(.linear)

            Text(service.testProgress.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resultView(_ result: LANSpeedResult) -> some View {
        let dlFormatted = speedUnit.format(result.downloadSpeed)
        let ulFormatted = speedUnit.format(result.uploadSpeed)

        return VStack(spacing: 16) {
            // Speed results
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    Text(dlFormatted.value)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("\(dlFormatted.unit) Download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                    Text(ulFormatted.value)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("\(ulFormatted.unit) Upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Additional stats
            HStack(spacing: 30) {
                StatItem(label: "Latency", value: String(format: "%.1f ms", result.latency), icon: "clock")
                StatItem(label: "Transferred", value: formatBytes(result.bytesTransferred), icon: "arrow.left.arrow.right")
                StatItem(label: "Duration", value: String(format: "%.1fs", result.duration), icon: "timer")
            }

            // Timestamp
            Text("Tested at \(result.timestamp.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "speedometer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Ready to test")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Click 'Run Test' to measure speed to the selected device")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Select a device")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Choose a Mac from the list to test network speed")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func phaseIcon(_ phase: LANTestProgress.Phase) -> String {
        switch phase {
        case .idle: return "circle"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .measuringLatency: return "clock"
        case .download: return "arrow.down.circle"
        case .upload: return "arrow.up.circle"
        case .complete: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: LANDevice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                Text("Available")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.5))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    LANSpeedTestView(historyManager: HistoryManager())
        .frame(width: 800, height: 500)
}
