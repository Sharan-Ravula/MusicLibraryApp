import SwiftUI
import AppKit

/// Right-hand "queue" panel, styled after Apple Music's Continue Playing panel.
struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var metadataStore: SongMetadataStore
    @EnvironmentObject private var edits: MetadataEditsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Continue Playing")
                    .appHeadlineFont()
                Spacer()
                if !player.upcomingSongs.isEmpty {
                    Button("Clear") {
                        player.clearQueue()
                    }
                    .buttonStyle(.plain)
                    .appCaptionFont()
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if player.upcomingSongs.isEmpty {
                VStack {
                    Spacer()
                    Text("Nothing queued")
                        .appCaptionFont()
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(player.upcomingSongs) { song in
                    HStack(spacing: 10) {
                        artworkView(for: song)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayTitle(for: song))
                                .appCaptionFont()
                                .lineLimit(1)
                            if let artist = metadataStore.metadata(for: song)?.artist, !artist.isEmpty {
                                Text(artist)
                                    .appCaption2Font()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 4)

                        Menu {
                            Button("Play Now") {
                                player.queueNext(song)
                                player.playNext()
                            }
                            Button("Remove from Queue", role: .destructive) {
                                player.removeFromQueue(song)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("More Options")
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func artworkView(for song: Song) -> some View {
        if let artwork = effectiveArtwork(for: song) {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "music.note")
                        .appCaption2Font()
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func effectiveArtwork(for song: Song) -> NSImage? {
        if let data = edits.edit(for: song)?.artworkData, let image = NSImage(data: data) {
            return image
        }
        return metadataStore.metadata(for: song)?.artwork
    }

    private func displayTitle(for song: Song) -> String {
        if let t = edits.edit(for: song)?.title, !t.isEmpty { return t }
        if let t = metadataStore.metadata(for: song)?.title, !t.isEmpty { return t }
        return song.title
    }
}
