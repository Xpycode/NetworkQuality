import SwiftUI

struct SettingsView: View {
    @Binding var config: TestConfiguration
    let availableInterfaces: [String]
    @AppStorage("rpmRatingMode") private var rpmRatingModeRaw = RPMRatingMode.practical.rawValue

    private var rpmRatingMode: Binding<RPMRatingMode> {
        Binding(
            get: { RPMRatingMode(rawValue: rpmRatingModeRaw) ?? .practical },
            set: { rpmRatingModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("RPM Rating Mode") {
                Picker("Thresholds", selection: rpmRatingMode) {
                    ForEach(RPMRatingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(rpmRatingMode.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if rpmRatingMode.wrappedValue == .ietf {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("IETF Thresholds:")
                            .font(.caption.weight(.medium))
                        Text("Excellent: 6000+ RPM (≤10ms)")
                        Text("Good: 1000+ RPM (≤60ms)")
                        Text("Fair: 300+ RPM (≤200ms)")
                        Text("Poor: <300 RPM (>200ms)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }

            Section("Test Mode") {
                Picker("Mode", selection: $config.mode) {
                    ForEach(TestMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Protocol") {
                Picker("Protocol", selection: $config.protocolSelection) {
                    ForEach(ProtocolSelection.allCases, id: \.self) { proto in
                        Text(proto.rawValue).tag(proto)
                    }
                }

                HStack {
                    Text("L4S (Low Latency)")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { config.enableL4S.map { $0 ? 1 : 0 } ?? -1 },
                        set: { config.enableL4S = $0 == -1 ? nil : $0 == 1 }
                    )) {
                        Text("Auto").tag(-1)
                        Text("Enabled").tag(1)
                        Text("Disabled").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            Section("Network Interface") {
                Picker("Interface", selection: $config.networkInterface) {
                    Text("Default").tag("")
                    ForEach(availableInterfaces, id: \.self) { interface in
                        Text(interface).tag(interface)
                    }
                }

                Text("Select a specific network interface (e.g., en0 for Wi-Fi, en1 for Ethernet)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Multi-Server Testing") {
                Toggle("Apple Sequential Mode", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "appleSequentialMode") },
                    set: { UserDefaults.standard.set($0, forKey: "appleSequentialMode") }
                ))

                Text("Run Apple's download and upload tests separately instead of in parallel. Takes longer but may be more accurate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced Options") {
                HStack {
                    Text("Max Run Time (seconds)")
                    Spacer()
                    Text("0 = unlimited")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    TextField("", value: $config.maxRunTime, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }

                TextField("Custom Config URL", text: $config.customConfigURL)
                    .textFieldStyle(.roundedBorder)

                Toggle("Use iCloud Private Relay", isOn: $config.usePrivateRelay)

                Toggle("Disable TLS Verification", isOn: $config.disableTLSVerification)
                    .foregroundStyle(config.disableTLSVerification ? .red : .primary)

                Toggle("Verbose Output", isOn: $config.verbose)
            }
        }
        .formStyle(.grouped)
    }

    private var modeDescription: String {
        switch config.mode {
        case .parallel:
            return "Run upload and download tests simultaneously (default)"
        case .sequential:
            return "Run download test first, then upload test separately"
        case .downloadOnly:
            return "Only test download speed (implies sequential mode)"
        case .uploadOnly:
            return "Only test upload speed (implies sequential mode)"
        }
    }
}

#Preview {
    SettingsView(
        config: .constant(TestConfiguration()),
        availableInterfaces: ["en0", "en1", "lo0"]
    )
    .frame(width: 500, height: 600)
}
