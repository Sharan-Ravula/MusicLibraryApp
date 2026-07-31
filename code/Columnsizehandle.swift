import SwiftUI
import AppKit

/// A thin draggable divider — between table columns (fixed short height) or
/// between full-height panels like the queue sidebar (fullHeight: true).
struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    var fullHeight: Bool = false
    /// True when this handle sits on the LEFT edge of the thing it resizes
    /// (like the queue panel) rather than the right edge (like a table
    /// column) — the drag direction needs to be flipped in that case.
    var invertDrag: Bool = false

    @State private var dragStartWidth: CGFloat?
    @State private var dragStartX: CGFloat?

    var body: some View {
        Group {
            if fullHeight {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .frame(width: 9)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1, height: 16)
                    .frame(width: 9, height: 20)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            // Anchored to the global cursor position rather than
            // translation-in-local-space: since this handle moves to the
            // right as the column widens, using local translation causes
            // a feedback loop where the resize accelerates and never
            // settles. Anchoring to a fixed global start point avoids that.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                        dragStartX = value.startLocation.x
                    }
                    let delta = value.location.x - (dragStartX ?? value.startLocation.x)
                    let signedDelta = invertDrag ? -delta : delta
                    let proposed = (dragStartWidth ?? width) + signedDelta
                    width = min(max(proposed, minWidth), maxWidth)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    dragStartX = nil
                }
        )
    }
}
