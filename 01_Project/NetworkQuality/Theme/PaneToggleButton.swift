import SwiftUI

/// Toolbar toggle that lights up with the accent color when `isOn` is true.
/// Use for sidebar/inspector/pane-visibility toggles in the main toolbar.
struct PaneToggleButton: View {
    @Binding var isOn: Bool
    let iconName: String
    let help: String

    var body: some View {
        Button(action: { withAnimation { isOn.toggle() } }) {
            Image(systemName: iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        }
        .help(help)
        .buttonStyle(FCPToolbarButtonStyle(isOn: isOn))
    }
}
