import Foundation
import Combine

struct SongEdit: Codable {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
}

/// Holds user edits to song metadata, including custom artwork. These are
/// stored inside the app (keyed by the real file path) and layered on top
/// of what's read from the file's tags — they do NOT rewrite the actual
/// metadata bytes in the audio file itself. Most downloaded mp3s already
/// carry real embedded tags and artwork, which the app reads directly
/// (see SongMetadataStore) — this store is just for the cases where you
/// want to override that from within the app.
@MainActor
final class MetadataEditsStore: ObservableObject {
    @Published private(set) var edits: [String: SongEdit] = [:]
    private let fileURL: URL

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appDir = supportDir?.appendingPathComponent("MusicLibrary", isDirectory: true)
        if let appDir {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        fileURL = (appDir ?? FileManager.default.temporaryDirectory).appendingPathComponent("metadata_edits.json")
        load()
    }

    func edit(for song: Song) -> SongEdit? {
        edits[song.playbackURL.path]
    }

    func save(title: String, artist: String, album: String, artworkData: Data?, for song: Song) {
        var current = edits[song.playbackURL.path] ?? SongEdit()
        current.title = title
        current.artist = artist
        current.album = album
        current.artworkData = artworkData
        edits[song.playbackURL.path] = current
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(edits) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: SongEdit].self, from: data)
        else { return }
        edits = decoded
    }
}
