import Foundation
import AVFoundation
import AppKit
import Combine

struct SongMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: NSImage?
    /// The raw artwork bytes as read from the file's tag (JPEG/PNG as
    /// embedded). Kept separately from the decoded NSImage so unchanged
    /// artwork can be carried forward byte-for-byte when re-writing tags
    /// for a title/artist/album edit.
    var artworkData: Data?
    var duration: TimeInterval?
    var bitrateKbps: Int?
    var dateAdded: Date?
}

/// The subset of SongMetadata that's cheap to store and doesn't include
/// artwork (which would bloat the cache file) — this is what gets saved to
/// disk so duration/bitrate/tags don't need to be re-scanned every launch.
private struct PersistedSongMetadata: Codable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var bitrateKbps: Int?
    var dateAdded: Date?
}

/// Loads ID3/metadata tags, duration, and bitrate for songs on demand and
/// caches the results — in memory for this session, and (minus artwork) in
/// a JSON file on disk so relaunching doesn't require re-scanning every
/// file again. Built for large libraries: the on-disk cache is kept in
/// memory for O(1) lookups, and writes are debounced so scanning hundreds
/// or thousands of songs at once doesn't rewrite the whole file after each one.
@MainActor
final class SongMetadataStore: ObservableObject {
    @Published private(set) var cache: [URL: SongMetadata] = [:]

    private var diskCache: [String: PersistedSongMetadata] = [:]
    private var saveTask: Task<Void, Never>?
    private let fileURL: URL

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appDir = supportDir?.appendingPathComponent("MusicLibrary", isDirectory: true)
        if let appDir {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        fileURL = (appDir ?? FileManager.default.temporaryDirectory).appendingPathComponent("metadata_cache.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: PersistedSongMetadata].self, from: data) {
            diskCache = decoded
        }
    }

    func metadata(for song: Song) -> SongMetadata? {
        cache[song.id]
    }

    /// Forces a fresh re-scan of a song, ignoring any cached value (in
    /// memory or on disk). Use sparingly — this is for a manual "Refresh"
    /// action, not routine loading.
    func refresh(for song: Song) {
        cache[song.id] = nil
        load(for: song)
    }

    func load(for song: Song) {
        guard cache[song.id] == nil else { return }
        let url = song.playbackURL
        let path = url.path

        // Fast path: if we've scanned this file before, show those values
        // immediately instead of dashes while the fresh scan (below) runs
        // in the background — mainly to pick up artwork, which isn't persisted.
        if let persisted = diskCache[path] {
            cache[song.id] = SongMetadata(
                title: persisted.title,
                artist: persisted.artist,
                album: persisted.album,
                artwork: nil,
                artworkData: nil,
                duration: persisted.duration,
                bitrateKbps: persisted.bitrateKbps,
                dateAdded: persisted.dateAdded
            )
        }

        Task {
            let asset = AVURLAsset(url: url)
            var result = SongMetadata()

            if let items = try? await asset.load(.commonMetadata) {
                for item in items {
                    guard let key = item.commonKey else { continue }
                    switch key {
                    case .commonKeyTitle:
                        result.title = try? await item.load(.stringValue)
                    case .commonKeyArtist:
                        result.artist = try? await item.load(.stringValue)
                    case .commonKeyAlbumName:
                        result.album = try? await item.load(.stringValue)
                    case .commonKeyArtwork:
                        if let data = try? await item.load(.dataValue) {
                            result.artwork = NSImage(data: data)
                            result.artworkData = data
                        }
                    default:
                        break
                    }
                }
            }

            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite, seconds >= 0 {
                    result.duration = seconds
                }
            }

            if let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first {
                if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                    result.bitrateKbps = Int(rate / 1000)
                }
            }

            // "Date added" = when the alias/file for this playlist entry was
            // created, not the original file's creation date — so it reflects
            // when the song joined this playlist.
            if let values = try? song.url.resourceValues(forKeys: [.creationDateKey]) {
                result.dateAdded = values.creationDate
            }

            self.cache[song.id] = result
            self.diskCache[path] = PersistedSongMetadata(
                title: result.title,
                artist: result.artist,
                album: result.album,
                duration: result.duration,
                bitrateKbps: result.bitrateKbps,
                dateAdded: result.dateAdded
            )
            self.scheduleSave()
        }
    }

    /// Coalesces writes: if many songs finish scanning close together (a
    /// fresh library scan), this waits for a short lull before writing once,
    /// instead of hitting disk after every single song.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self.writeToDisk()
        }
    }

    private func writeToDisk() {
        guard let data = try? JSONEncoder().encode(diskCache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
