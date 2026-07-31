import SwiftUI
import AppKit

struct PlayerBar: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var metadataStore: SongMetadataStore
    @EnvironmentObject private var edits: MetadataEditsStore
    @EnvironmentObject private var uiState: UIState

    /// Both side zones use this same fixed width, so a plain HStack with
    /// Spacers on either side of the center content truly centers it —
    /// no ZStack needed. This also means the layout can never overlap:
    /// HStack children reserve their own space by definition, unlike
    /// ZStack layers which can visually collide at narrow window widths.
    private let sideZoneWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                artworkView
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer(minLength: 0)
            }
            .frame(width: sideZoneWidth, alignment: .leading)

            VStack(spacing: 6) {
                if let song = player.currentSong {
                    MarqueeText(text: displayTitle(for: song), size: 14, weight: .semibold, autoScroll: true)
                        .frame(maxWidth: 600)

                    HStack(spacing: 8) {
                        Text(formatTime(clock.currentTime))
                            .appCaption2Font()
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { clock.currentTime },
                                set: { player.seek(to: $0) }
                            ),
                            in: 0...max(player.duration, 1)
                        )
                        .animation(.linear(duration: 0.02), value: clock.currentTime)
                        .help("Seek")

                        Text(formatTime(player.duration))
                            .appCaption2Font()
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .leading)
                    }
                    .frame(maxWidth: 640)
                } else {
                    Text("No song playing")
                        .appCaptionFont()
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
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
                        tooltip: repeatTooltip
                    ) {
                        player.cycleRepeatMode()
                    }
                }
            }
            .frame(minWidth: 320, maxWidth: 700)
            .layoutPriority(1)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
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
            .frame(width: sideZoneWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let song = player.currentSong, let artwork = effectiveArtwork(for: song) {
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

    private func displayTitle(for song: Song) -> String {
        if let t = edits.edit(for: song)?.title, !t.isEmpty { return t }
        let tagTitle = metadataStore.metadata(for: song)?.title
        if let tagTitle, !tagTitle.isEmpty { return tagTitle }
        return song.title
    }

    private func effectiveArtwork(for song: Song) -> NSImage? {
        if let data = edits.edit(for: song)?.artworkData, let image = NSImage(data: data) {
            return image
        }
        return metadataStore.metadata(for: song)?.artwork
    }

    private var repeatTooltip: String {
        switch player.repeatMode {
        case .off: return "Repeat"
        case .all: return "Repeat All"
        case .one: return "Repeat One"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
