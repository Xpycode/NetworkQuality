import SwiftUI

struct SettingsView: View {
    @Binding var config: TestConfiguration
    let availableInterfaces: [String]

    var body: some View {
        Form {
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

            Section("Advanced Options") {
                HStack {
                    Text("Max Run Time (seconds)")
                    Spacer()
                    TextField("0 = unlimited", value: $config.maxRunTime, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
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
