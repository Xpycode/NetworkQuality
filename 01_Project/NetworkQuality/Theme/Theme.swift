import SwiftUI

// MARK: - Theme Manager

@Observable
class ThemeManager {
    static let shared = ThemeManager()

    // Brand accent — change here to retune the whole app.
    // Current choice: a warm Apple-blue (matches NetworkQuality's legacy identity
    // while the shell migration is in progress).
    static let brandAccent = Color(red: 0.0, green: 0.48, blue: 1.0)

    var accentColor: Color {
        didSet { saveColor(accentColor, forKey: "accentColor") }
    }
    var primaryTextColor: Color {
        didSet { saveColor(primaryTextColor, forKey: "primaryTextColor") }
    }

    var secondaryTextColor: Color {
        primaryTextColor.opacity(0.65)
    }

    private init() {
        self.accentColor = Self.loadColor(forKey: "accentColor") ?? Self.brandAccent
        self.primaryTextColor = Self.loadColor(forKey: "primaryTextColor") ?? .white
    }

    private func saveColor(_ color: Color, forKey key: String) {
        let nsColor = NSColor(color)
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: nsColor, requiringSecureCoding: false
        ) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadColor(forKey key: String) -> Color? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let nsColor = try? NSKeyedUnarchiver.unarchivedObject(
                  ofClass: NSColor.self, from: data
              ) else {
            return nil
        }
        return Color(nsColor: nsColor)
    }
}

// MARK: - Theme Struct

struct Theme {
    static var primaryBackground: Color { Color(white: 0.10) }   // graphite
    static var secondaryBackground: Color { Color(white: 0.15) } // charcoal
    static var accent: Color { ThemeManager.shared.accentColor }
    static var primaryText: Color { ThemeManager.shared.primaryTextColor }
    static var secondaryText: Color { ThemeManager.shared.secondaryTextColor }
}
