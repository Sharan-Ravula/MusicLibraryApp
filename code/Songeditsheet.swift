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
                    edits.save(title: title, artist: artist, album: album, artworkData: artworkJPEG, for: song)
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
            title = existingEdit?.title ?? tags?.title ?? song.title
            artist = existingEdit?.artist ?? tags?.artist ?? ""
            album = existingEdit?.album ?? tags?.album ?? ""

            if let overrideData = existingEdit?.artworkData {
                artworkJPEG = overrideData
                artworkPreview = NSImage(data: overrideData)
            } else {
                artworkPreview = tags?.artwork
                artworkJPEG = tags?.artworkData
            }
        }
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
