import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case purple = "Purple"
    case blue = "Blue"
    case pink = "Pink"
    case green = "Green"
    case orange = "Orange"
    case graphite = "Graphite"
    case red = "Red"
    case teal = "Teal"
    case yellow = "Yellow"
    case indigo = "Indigo"
    case mint = "Mint"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .purple: return Color(red: 0.43, green: 0.37, blue: 0.95)
        case .blue: return Color(red: 0.20, green: 0.48, blue: 0.98)
        case .pink: return Color(red: 0.93, green: 0.31, blue: 0.60)
        case .green: return Color(red: 0.20, green: 0.70, blue: 0.44)
        case .orange: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .graphite: return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .red: return Color(red: 0.90, green: 0.26, blue: 0.24)
        case .teal: return Color(red: 0.19, green: 0.68, blue: 0.72)
        case .yellow: return Color(red: 0.93, green: 0.73, blue: 0.13)
        case .indigo: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .mint: return Color(red: 0.24, green: 0.78, blue: 0.65)
        }
    }
}

/// Drives app-wide text scaling (Cmd+= / Cmd+-) and the color theme.
/// Font scaling uses an explicit multiplier applied directly to point sizes
/// (see AppFontScale.swift) rather than SwiftUI's Dynamic Type system,
/// which doesn't reliably scale text on macOS.
@MainActor
final class AppSettings: ObservableObject {
    private static let minScale: CGFloat = 0.8
    private static let maxScale: CGFloat = 1.6
    private static let step: CGFloat = 0.1

    @Published var fontScale: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontScale), forKey: "fontScale") }
    }

    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "appTheme") }
    }

    init() {
        if let saved = UserDefaults.standard.object(forKey: "fontScale") as? Double {
            fontScale = CGFloat(saved)
        } else {
            fontScale = 1.0
        }

        if let savedTheme = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.theme = theme
        } else {
            self.theme = .purple
        }
    }

    func increaseFontSize() {
        fontScale = min(fontScale + Self.step, Self.maxScale)
    }

    func decreaseFontSize() {
        fontScale = max(fontScale - Self.step, Self.minScale)
    }
}
