import Foundation
import AVFoundation
import CoreMedia
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
    var channels: Int?
    var sampleRateHz: Double?
    /// Bit depth — only meaningful for uncompressed/lossless formats
    /// (wav, aiff, flac). Compressed formats like mp3/aac don't have a
    /// fixed bit depth, so this stays nil for those.
    var bitsPerSample: Int?
    var fileSizeBytes: Int64?
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
    var channels: Int?
    var sampleRateHz: Double?
    var bitsPerSample: Int?
    var fileSizeBytes: Int64?
}

/// Loads ID3/metadata tags, duration, bitrate, and technical audio details
/// for songs on demand and caches the results — in memory for this session,
/// and (minus artwork) in a JSON file on disk so relaunching doesn't require
/// re-scanning every file again. Built for large libraries: the on-disk
/// cache is kept in memory for O(1) lookups, and writes are debounced so
/// scanning hundreds or thousands of songs at once doesn't rewrite the
/// whole file after each one.
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
        //
        // "Date added" is deliberately NOT read from diskCache here: that
        // cache is keyed by the real file's resolved path, which is shared
        // by every playlist alias pointing at the same underlying file.
        // Date added is specific to this alias (when it joined THIS
        // playlist), so it's recomputed directly per-song instead — it's a
        // cheap, synchronous resourceValues() lookup, not worth waiting for
        // the full async rescan below.
        if let persisted = diskCache[path] {
            cache[song.id] = SongMetadata(
                title: persisted.title,
                artist: persisted.artist,
                album: persisted.album,
                artwork: nil,
                artworkData: nil,
                duration: persisted.duration,
                bitrateKbps: persisted.bitrateKbps,
                dateAdded: dateAdded(for: song),
                channels: persisted.channels,
                sampleRateHz: persisted.sampleRateHz,
                bitsPerSample: persisted.bitsPerSample,
                fileSizeBytes: persisted.fileSizeBytes
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

                // Channels, sample rate, and bit depth come from the track's
                // raw format description — estimatedDataRate alone doesn't
                // expose these.
                if let formatDescriptions = try? await track.load(.formatDescriptions),
                   let formatDesc = formatDescriptions.first,
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                    result.channels = Int(asbd.mChannelsPerFrame)
                    result.sampleRateHz = asbd.mSampleRate
                    let bits = Int(asbd.mBitsPerChannel)
                    result.bitsPerSample = bits > 0 ? bits : nil
                }
            }

            // File size, in bytes, of the real underlying file.
            if let sizeValues = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = sizeValues.fileSize {
                result.fileSizeBytes = Int64(size)
            }

            // Fallback bitrate: AVFoundation's estimatedDataRate can come
            // back empty for some wav/flac files. When that happens, derive
            // an approximate bitrate directly from file size ÷ duration —
            // works for literally any format since it doesn't depend on
            // AVFoundation understanding the codec's internals.
            if (result.bitrateKbps == nil || result.bitrateKbps == 0),
               let duration = result.duration, duration > 0,
               let fileSize = result.fileSizeBytes {
                let bitsPerSecond = Double(fileSize) * 8 / duration
                result.bitrateKbps = Int(bitsPerSecond / 1000)
            }

            // "Date added" = when the alias/file for this playlist entry was
            // created, not the original file's creation date — so it reflects
            // when the song joined this playlist. Computed per-alias, not
            // persisted in the path-keyed disk cache (see fast path above).
            result.dateAdded = self.dateAdded(for: song)

            self.cache[song.id] = result
            self.diskCache[path] = PersistedSongMetadata(
                title: result.title,
                artist: result.artist,
                album: result.album,
                duration: result.duration,
                bitrateKbps: result.bitrateKbps,
                channels: result.channels,
                sampleRateHz: result.sampleRateHz,
                bitsPerSample: result.bitsPerSample,
                fileSizeBytes: result.fileSizeBytes
            )
            self.scheduleSave()
        }
    }

    private func dateAdded(for song: Song) -> Date? {
        (try? song.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
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
