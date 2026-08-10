import SwiftUI
import AppKit

struct PlayerBar: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var metadataStore: SongMetadataStore
    @EnvironmentObject private var edits: MetadataEditsStore
    @EnvironmentObject private var uiState: UIState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                // Transport controls, grouped tightly on the left.
                HStack(spacing: 6) {
                    PlayerControlButton(systemImage: "shuffle", isActive: player.isShuffling, tooltip: "Shuffle") {
                        player.isShuffling.toggle()
                    }
                    PlayerControlButton(systemImage: "backward.fill", tooltip: "Previous Track") {
                        player.playPrevious()
                    }
                    PlayerControlButton(
                        systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                        size: 18,
                        tooltip: player.isPlaying ? "Pause" : "Play"
                    ) {
                        player.togglePlayPause()
                    }
                    PlayerControlButton(systemImage: "forward.fill", tooltip: "Next Track") {
                        player.playNext()
                    }
                    PlayerControlButton(
                        systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                        isActive: player.repeatMode != .off,
                        tooltip: player.repeatMode.tooltip
                    ) {
                        player.cycleRepeatMode()
                    }
                }

                // Artwork + title, right next to the controls (not centered).
                HStack(spacing: 10) {
                    artworkView
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    if let song = player.currentSong {
                        MarqueeText(text: song.displayTitle(edits: edits, metadataStore: metadataStore), size: 14, weight: .semibold, autoScroll: true)
                    } else {
                        Text("No song playing")
                            .appCaptionFont()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Higher priority than the Spacer right after it, so this
                // claims the empty leftover space instead of splitting it
                // evenly with the Spacer (which just needs its 12pt minimum).
                .layoutPriority(1)

                Spacer(minLength: 12)

                // Everything else, pushed to the far right.
                HStack(spacing: 16) {
                    PlayerControlButton(
                        systemImage: "list.bullet",
                        isActive: uiState.showQueue,
                        tooltip: uiState.showQueue ? "Hide Queue" : "Show Queue"
                    ) {
                        uiState.showQueue.toggle()
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                            .appCaption2Font()
                            .foregroundStyle(.secondary)
                        Slider(value: $player.volume, in: 0...1)
                            .frame(width: 90)
                            .help("Volume")
                    }
                }
            }

            // Isolated into its own view so the 20x/sec clock ticks only
            // re-render this row — not the whole bar (which was very
            // plausibly interfering with the buttons' click handling above,
            // since the buttons don't need to know about playback time at all).
            PlayerProgressBar()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let song = player.currentSong, let artwork = song.effectiveArtwork(edits: edits, metadataStore: metadataStore) {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }

}

/// The thin scrubber + time labels — isolated here specifically so it's the
/// only thing that re-renders 20x/second while something plays.
private struct PlayerProgressBar: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var clock: PlaybackClock

    var body: some View {
        HStack(spacing: 8) {
            Text(formatTime(clock.currentTime))
                .appCaption2Font()
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)

            PlaybackScrubber(
                progress: player.duration > 0 ? clock.currentTime / player.duration : 0,
                onSeek: { fraction in player.seek(to: fraction * player.duration) }
            )
            .help("Seek")

            Text(formatTime(player.duration))
                .appCaption2Font()
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
