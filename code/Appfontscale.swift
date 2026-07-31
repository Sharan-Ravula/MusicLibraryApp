import SwiftUI

private struct AppFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var appFontScale: CGFloat {
        get { self[AppFontScaleKey.self] }
        set { self[AppFontScaleKey.self] = newValue }
    }
}

/// Applies an explicit point size, scaled by the app's current font-size
/// setting. This is used instead of SwiftUI's built-in Dynamic Type system
/// (`.dynamicTypeSize`) because that has inconsistent/limited effect on
/// macOS — this guarantees text actually visibly changes size.
private struct ScaledFontModifier: ViewModifier {
    @Environment(\.appFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}

extension View {
    func appFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight))
    }

    // Convenience presets matching the semantic styles this app used to use.
    func appHeadlineFont() -> some View { appFont(13, weight: .semibold) }
    func appCaptionFont() -> some View { appFont(11) }
    func appCaptionBoldFont() -> some View { appFont(11, weight: .bold) }
    func appCaption2Font() -> some View { appFont(10) }
}
