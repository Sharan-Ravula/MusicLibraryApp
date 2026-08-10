import SwiftUI

/// A lightweight, custom-drawn seek bar for playback progress.
///
/// Deliberately NOT a native `Slider`: profiling showed a real NSSlider
/// redraws expensively under SwiftUI (it re-resolves theme/appearance
/// assets on every draw), and playback progress needs to redraw ~10x/sec
/// for as long as anything plays — that was worth ~30-35 points of CPU by
/// itself. A plain Shape-based track is just a couple of fills, effectively
/// free to redraw at any rate.
struct PlaybackScrubber: View {
    /// 0...1
    var progress: Double
    /// Called with the seeked-to fraction (0...1) once the drag ends.
    var onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    private let trackHeight: CGFloat = 4
    private let knobDiameter: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = min(max(isDragging ? dragFraction : progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: width * fraction, height: trackHeight)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: width * fraction - knobDiameter / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        isDragging = true
                        dragFraction = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        guard width > 0 else { return }
                        let final = min(max(value.location.x / width, 0), 1)
                        isDragging = false
                        onSeek(final)
                    }
            )
        }
        .frame(height: knobDiameter)
    }
}
