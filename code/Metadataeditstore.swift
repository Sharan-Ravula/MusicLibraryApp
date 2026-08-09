import Foundation
import AppKit
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
    /// Decoding a JPEG/PNG from Data on every access (every row render, every
    /// scroll frame) was showing up as unnecessary CPU work — this caches
    /// the decoded image per song so it only happens once until the artwork
    /// actually changes.
    private var decodedArtworkCache: [String: NSImage] = [:]

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

    /// Decoded custom artwork for this song, if any edit set it — cached
    /// after the first decode.
    func artwork(for song: Song) -> NSImage? {
        let path = song.playbackURL.path
        guard let data = edits[path]?.artworkData else { return nil }
        if let cached = decodedArtworkCache[path] {
            return cached
        }
        let image = NSImage(data: data)
        decodedArtworkCache[path] = image
        return image
    }

    func save(title: String, artist: String, album: String, artworkData: Data?, for song: Song) {
        let path = song.playbackURL.path
        var current = edits[path] ?? SongEdit()
        current.title = title
        current.artist = artist
        current.album = album
        current.artworkData = artworkData
        edits[path] = current
        decodedArtworkCache[path] = nil
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
