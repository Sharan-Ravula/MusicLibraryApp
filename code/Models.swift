import Foundation

struct Song: Identifiable, Hashable {
    let id: URL
    let url: URL
    var title: String { url.deletingPathExtension().lastPathComponent }

    /// Resolves symlinks/aliases so playback reads the real file, even when
    /// this song is an alias inside a playlist folder pointing elsewhere.
    var playbackURL: URL { url.resolvingSymlinksInPath() }
}

struct Playlist: Identifiable, Hashable {
    let id: URL
    let url: URL
    var name: String { url.lastPathComponent }
}
