import SwiftUI
import AppKit

struct MenuBarPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var metadataStore: SongMetadataStore
    @EnvironmentObject private var edits: MetadataEditsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let song = player.currentSong {
                HStack(spacing: 12) {
                    artworkView(for: song)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.displayTitle(edits: edits, metadataStore: metadataStore))
                            .appHeadlineFont()
                            .lineLimit(1)
                        if let artist = metadataStore.metadata(for: song)?.artist, !artist.isEmpty {
                            Text(artist)
                                .appCaptionFont()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }

                // Isolated so the 20x/sec clock ticks only re-render this
                // row — not the buttons below, which don't need playback
                // time at all and shouldn't be re-evaluated because of it.
                MenuBarProgressBar()

                HStack(spacing: 6) {
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
                    Spacer()
                    PlayerControlButton(systemImage: "shuffle", isActive: player.isShuffling, tooltip: "Shuffle") {
                        player.isShuffling.toggle()
                    }
                    PlayerControlButton(
                        systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                        isActive: player.repeatMode != .off,
                        tooltip: player.repeatMode.tooltip
                    ) {
                        player.cycleRepeatMode()
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .appCaptionFont()
                        .foregroundStyle(.secondary)
                    Slider(value: $player.volume, in: 0...1)
                }
            } else {
                Text("Nothing playing")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                // If the main window was closed entirely, there's no
                // visible window to bring forward — open a fresh one
                // instead of silently doing nothing.
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            } label: {
                Text("Open MusicLibrary")
            }
            .buttonStyle(.plain)

            Button("Quit MusicLibrary") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 260)
    }

    @ViewBuilder
    private func artworkView(for song: Song) -> some View {
        if let artwork = song.effectiveArtwork(edits: edits, metadataStore: metadataStore) {
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
private struct MenuBarProgressBar: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var clock: PlaybackClock

    var body: some View {
        HStack(spacing: 6) {
            Text(formatTime(clock.currentTime))
                .appCaption2Font()
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Slider(
                value: Binding(
                    get: { clock.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .animation(.linear(duration: 0.02), value: clock.currentTime)

            Text(formatTime(player.duration))
                .appCaption2Font()
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
