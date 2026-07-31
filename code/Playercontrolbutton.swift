import SwiftUI

/// A player/toolbar icon button that gets a small rounded highlight on hover,
/// and a stronger tinted background when it represents an "on" state
/// (like shuffle or repeat being active). Fixes tiny, feedback-less hit targets.
struct PlayerControlButton: View {
    let systemImage: String
    var isActive: Bool = false
    var size: CGFloat = 16
    var tooltip: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: size + 20, height: size + 20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .help(tooltip ?? "")
    }

    private var backgroundColor: Color {
        if isActive { return Color.accentColor.opacity(0.18) }
        if isHovered { return Color.secondary.opacity(0.15) }
        return .clear
    }
}
