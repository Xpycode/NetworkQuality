import SwiftUI

@main
struct NetworkQualityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Test") {
                Button("Run Speed Test") {
                    NotificationCenter.default.post(name: .runSpeedTest, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Cancel Test") {
                    NotificationCenter.default.post(name: .cancelSpeedTest, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Clear History") {
                    NotificationCenter.default.post(name: .clearHistory, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }

        Settings {
            SettingsWindowView()
        }
    }
}

struct SettingsWindowView: View {
    @AppStorage("defaultInterface") private var defaultInterface = ""
    @AppStorage("defaultProtocol") private var defaultProtocol = "Auto"
    @AppStorage("defaultMode") private var defaultMode = "Parallel"
    @AppStorage("autoRunOnLaunch") private var autoRunOnLaunch = false

    var body: some View {
        Form {
            Section("Default Settings") {
                TextField("Default Interface", text: $defaultInterface)
                    .textFieldStyle(.roundedBorder)

                Picker("Default Protocol", selection: $defaultProtocol) {
                    Text("Auto").tag("Auto")
                    Text("HTTP/1.1").tag("HTTP/1.1")
                    Text("HTTP/2").tag("HTTP/2")
                    Text("HTTP/3 (QUIC)").tag("HTTP/3 (QUIC)")
                }

                Picker("Default Mode", selection: $defaultMode) {
                    Text("Parallel").tag("Parallel")
                    Text("Sequential").tag("Sequential")
                    Text("Download Only").tag("Download Only")
                    Text("Upload Only").tag("Upload Only")
                }
            }

            Section("Behavior") {
                Toggle("Run test on app launch", isOn: $autoRunOnLaunch)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 250)
        .padding()
    }
}

extension Notification.Name {
    static let runSpeedTest = Notification.Name("runSpeedTest")
    static let cancelSpeedTest = Notification.Name("cancelSpeedTest")
    static let clearHistory = Notification.Name("clearHistory")
}
