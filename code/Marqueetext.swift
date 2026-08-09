import SwiftUI

/// Shows text normally (truncated with an ellipsis) until it needs to
/// scroll to reveal overflow content. Two modes:
/// - autoScroll = false (default): only scrolls on hover — used for table
///   rows, so idle rows in a long list don't all animate at once.
/// - autoScroll = true: scrolls continuously, back and forth, on its own —
///   used for the single now-playing title in the player bar.
struct MarqueeText: View {
    let text: String
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    var autoScroll: Bool = false
    /// Used when the text fits without needing to scroll. Once it overflows
    /// and needs to scroll, it always left-anchors regardless of this,
    /// since scrolling only makes sense starting from the left edge.
    var alignment: Alignment = .center

    @Environment(\.appFontScale) private var fontScale
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var scrolled = false

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .appFont(size, weight: weight)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { textGeo in
                        Color.clear
                            .onAppear { textWidth = textGeo.size.width }
                            .onChange(of: textGeo.size.width) {
                                textWidth = textGeo.size.width
                            }
                    }
                )
                // Only left-anchor (so it can scroll from the start) once it
                // actually overflows — otherwise it should sit centered like
                // any normal short title, not hug the left edge.
                .frame(width: geo.size.width, alignment: overflows ? .leading : alignment)
                .offset(x: offsetX)
                .animation(animation, value: scrolled)
                .onAppear {
                    containerWidth = geo.size.width
                    startAutoScrollIfNeeded()
                }
                .onChange(of: geo.size.width) {
                    containerWidth = geo.size.width
                }
                .onChange(of: text) {
                    scrolled = false
                    startAutoScrollIfNeeded()
                }
                .onHover { hovering in
                    guard !autoScroll, overflows else { return }
                    scrolled = hovering
                }
        }
        // Was a hardcoded 18pt, which clipped text once the font-size
        // setting scaled text taller than that. Now grows with it.
        .frame(height: (size * fontScale) + 6)
        .clipped()
    }

    private var animation: Animation? {
        guard overflows else { return nil }
        if autoScroll {
            return .linear(duration: Double(textWidth) / 100)
                .delay(0.4)
                .repeatForever(autoreverses: true)
        }
        return .linear(duration: Double(textWidth) / 130).delay(1.0)
    }

    private func startAutoScrollIfNeeded() {
        guard autoScroll else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            scrolled = overflows
        }
    }

    private var overflows: Bool {
        textWidth > containerWidth + 1
    }

    private var offsetX: CGFloat {
        guard overflows, scrolled else { return 0 }
        return -(textWidth - containerWidth)
    }
}
