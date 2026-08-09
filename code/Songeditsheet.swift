import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SongEditSheet: View {
    @EnvironmentObject private var metadataStore: SongMetadataStore
    @EnvironmentObject private var edits: MetadataEditsStore
    @Environment(\.dismiss) private var dismiss
    let song: Song

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var artworkPreview: NSImage?
    @State private var artworkJPEG: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Song Info")
                .appHeadlineFont()

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    artworkView
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        Button("Choose…") { chooseImage() }
                            .appCaption2Font()
                        if artworkPreview != nil {
                            Button("Remove") {
                                artworkPreview = nil
                                artworkJPEG = nil
                            }
                            .appCaption2Font()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Title") { TextField("Title", text: $title) }
                    LabeledContent("Artist") { TextField("Artist", text: $artist) }
                    LabeledContent("Album") { TextField("Album", text: $album) }
                }
            }

            Text("Saved in the app and shown here — this doesn't rewrite the tags inside the audio file itself.")
                .appCaptionFont()
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    // Only persist fields that were actually changed from
                    // their tag/filename fallback — otherwise every save
                    // would freeze all four fields as permanent overrides
                    // (since the form pre-fills them with the fallback),
                    // and a later tag fix or "Refresh Metadata" would never
                    // show through again. Storing "" (or nil for artwork)
                    // is exactly what every read site already treats as
                    // "no override, use the fallback."
                    let tags = metadataStore.metadata(for: song)
                    edits.save(
                        title: title == fallbackTitle(tags) ? "" : title,
                        artist: artist == fallbackArtist(tags) ? "" : artist,
                        album: album == fallbackAlbum(tags) ? "" : album,
                        artworkData: artworkJPEG == tags?.artworkData ? nil : artworkJPEG,
                        for: song
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            let existingEdit = edits.edit(for: song)
            let tags = metadataStore.metadata(for: song)
            if let t = existingEdit?.title, !t.isEmpty {
                title = t
            } else {
                title = fallbackTitle(tags)
            }
            if let a = existingEdit?.artist, !a.isEmpty {
                artist = a
            } else {
                artist = fallbackArtist(tags)
            }
            if let al = existingEdit?.album, !al.isEmpty {
                album = al
            } else {
                album = fallbackAlbum(tags)
            }

            if let overrideData = existingEdit?.artworkData {
                artworkJPEG = overrideData
                artworkPreview = NSImage(data: overrideData)
            } else {
                artworkPreview = tags?.artwork
                artworkJPEG = tags?.artworkData
            }
        }
    }

    /// The title/artist/album shown when there's no explicit override —
    /// shared between pre-filling the form and, at save time, deciding
    /// whether a field still matches the fallback (and so shouldn't be
    /// persisted as an override at all).
    private func fallbackTitle(_ tags: SongMetadata?) -> String {
        if let t = tags?.title, !t.isEmpty { return t }
        return song.title
    }

    private func fallbackArtist(_ tags: SongMetadata?) -> String {
        tags?.artist ?? ""
    }

    private func fallbackAlbum(_ tags: SongMetadata?) -> String {
        tags?.album ?? ""
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artworkPreview {
            Image(nsImage: artworkPreview)
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

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic, .bmp]
        panel.message = "Choose an image to use as this song's artwork"

        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        artworkPreview = image
        artworkJPEG = jpegData(from: image)
    }

    private func jpegData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
