import Foundation
import Combine

/// Holds just the fast-changing playback position, separate from
/// AudioPlayerManager. Only views that actually show a progress bar
/// (PlayerBar) should observe this — keeping it separate means the rest of
/// the app (song list, sidebar) doesn't re-render 20x/second just because
/// the clock ticked.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var currentTime: TimeInterval = 0
}
