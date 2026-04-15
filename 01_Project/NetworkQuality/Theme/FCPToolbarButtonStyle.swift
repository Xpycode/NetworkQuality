import SwiftUI

/// Flat, 4px-corner-radius toolbar button inspired by Final Cut Pro.
/// Replaces macOS Tahoe's default capsule/pill chrome on `NSToolbarItem`s.
///
/// Requires `UIDesignRequiresCompatibility = true` in Info.plist and
/// `.windowStyle(.hiddenTitleBar)` on the `WindowGroup` — otherwise the system
/// enforces capsule chrome regardless of the ButtonStyle.
struct FCPToolbarButtonStyle: ButtonStyle {
    var isOn: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundColor(isOn ? .white : .primary)
            .background(
                ZStack {
                    if isOn {
                        Theme.accent
                    } else {
                        Color(nsColor: .gray.withAlphaComponent(0.2))
                    }
                    if configuration.isPressed {
                        Color.black.opacity(0.2)
                    }
                }
            )
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isOn)
    }
}
