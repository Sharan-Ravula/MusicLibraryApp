import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class LibraryManager: ObservableObject {
    @Published var libraryURL: URL?
    @Published var playlists: [Playlist] = []
    /// The folder currently being browsed in the sidebar. Starts out equal
    /// to libraryURL, but can be a subfolder if the person has navigated
    /// into a nested folder.
    @Published var currentFolder: URL?
    /// Set when a user-initiated file operation (e.g. renaming a playlist)
    /// fails, so the UI can surface it instead of failing silently.
    @Published var errorMessage: String?

    private let bookmarkKey = "libraryBookmarkData"
    private let externalBookmarksKey = "externalSongBookmarks"
    private let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "flac", "aac"]

    /// songs(in:) is called from SwiftUI view bodies (every render, every
    /// search keystroke, every sort). Without caching that means a full,
    /// synchronous directory scan on the main actor per render — this
    /// caches per playlist and is invalidated wherever song files are added
    /// or removed.
    private var songsCache: [URL: [Song]] = [:]
    /// Same idea as songsCache, but for hasSubfolders(_:) — also called from
    /// a view body (once per playlist row, every sidebar render). Cleared
    /// whenever loadPlaylists() runs, which is exactly when callers already
    /// expect the sidebar to resync with disk.
    private var hasSubfoldersCache: [URL: Bool] = [:]

    init() {
        restoreBookmark()
    }

    /// Opens a folder picker. The chosen folder should contain one subfolder per playlist.
    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the parent folder that contains one subfolder per playlist"

        if panel.runModal() == .OK, let url = panel.url {
            setLibrary(url: url)
            saveBookmark(for: url)
        }
    }

    private func setLibrary(url: URL) {
        libraryURL = url
        currentFolder = url
        loadPlaylists()
    }

    /// Drills into a folder — its subfolders become the new sidebar list.
    func navigateInto(_ playlist: Playlist) {
        currentFolder = playlist.url
        loadPlaylists()
    }

    /// Goes up exactly one level from the current folder, toward the library root.
    func navigateToParent() {
        guard let currentFolder, let libraryURL, currentFolder != libraryURL else { return }
        self.currentFolder = currentFolder.deletingLastPathComponent()
        loadPlaylists()
    }

    /// Jumps straight to any folder — used when tapping a breadcrumb segment.
    func navigate(to url: URL) {
        currentFolder = url
        loadPlaylists()
    }

    /// The chain of folders from the library root down to the current
    /// folder, for breadcrumb display. Always at least one entry once a
    /// library is chosen.
    var breadcrumbs: [(name: String, url: URL)] {
        guard let libraryURL, let currentFolder else { return [] }
        var trail: [(String, URL)] = []
        var url = currentFolder
        while true {
            trail.insert((url.lastPathComponent, url), at: 0)
            if url.path == libraryURL.path { break }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break } // safety against infinite loop at "/"
            url = parent
        }
        return trail
    }

    /// True if this folder itself contains subfolders — used to show a
    /// "navigate in" affordance only where it's actually useful.
    func hasSubfolders(_ playlist: Playlist) -> Bool {
        if let cached = hasSubfoldersCache[playlist.url] {
            return cached
        }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: playlist.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            hasSubfoldersCache[playlist.url] = false
            return false
        }
        let result = entries.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        hasSubfoldersCache[playlist.url] = result
        return result
    }

    /// True if a playlist's folder is still actually there on disk — used
    /// to grey out playlists whose folder was deleted or moved outside the
    /// app (e.g. in Finder) since it was last scanned.
    func folderExists(for playlist: Playlist) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: playlist.url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func loadPlaylists() {
        hasSubfoldersCache.removeAll()
        guard let currentFolder else { playlists = []; return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: currentFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            playlists = []
            return
        }

        let folders = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }

        playlists = folders
            .map { Playlist(id: $0, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func songs(in playlist: Playlist) -> [Song] {
        if let cached = songsCache[playlist.url] {
            return cached
        }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: playlist.url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let result = entries
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .map { Song(id: $0, url: $0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        songsCache[playlist.url] = result
        return result
    }

    private func invalidateSongsCache(for url: URL) {
        songsCache[url] = nil
    }

    // MARK: - Playlist management

    func createPlaylist(named name: String) {
        guard let currentFolder else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newURL = currentFolder.appendingPathComponent(trimmed)
        try? FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        loadPlaylists()
    }

    /// Returns the renamed playlist's new identity on success, or nil if the
    /// rename failed — callers that track a "currently selected" playlist by
    /// value need this to re-point their selection at the new URL, since the
    /// old Playlist's URL no longer exists on disk after a successful rename.
    @discardableResult
    func rename(_ playlist: Playlist, to newName: String) -> Playlist? {
        guard let currentFolder else { return nil }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let newURL = currentFolder.appendingPathComponent(trimmed)
        var renamed: Playlist?
        do {
            try FileManager.default.moveItem(at: playlist.url, to: newURL)
            invalidateSongsCache(for: playlist.url)
            renamed = Playlist(id: newURL, url: newURL)
        } catch {
            errorMessage = "Couldn't rename \"\(playlist.name)\" to \"\(trimmed)\" — a folder with that name may already exist."
        }
        loadPlaylists()
        return renamed
    }

    func delete(_ playlist: Playlist) {
        // Moves to Trash rather than permanently deleting — safer, and it's
        // just the folder of aliases/files being removed, not your real music.
        try? FileManager.default.trashItem(at: playlist.url, resultingItemURL: nil)
        invalidateSongsCache(for: playlist.url)
        loadPlaylists()
    }

    // MARK: - Adding songs (as aliases, never copies)

    /// Lets the user pick any audio files anywhere on disk and adds them to
    /// the playlist as aliases (symlinks) — the real file never moves or duplicates.
    func chooseAndAddSongs(to playlist: Playlist) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mp3, .wav, .aiff, .mpeg4Audio, .audio]
        if panel.runModal() == .OK {
            addSongs(urls: panel.urls, to: playlist)
        }
    }

    /// Adds the given files to a playlist as aliases. Used by both the file
    /// picker above and drag-and-drop.
    func addSongs(urls: [URL], to playlist: Playlist) {
        for url in urls {
            addAlias(for: url, in: playlist)
        }
        invalidateSongsCache(for: playlist.url)
        objectWillChange.send()
    }

    /// Removes a song's alias from a playlist (moves the alias to Trash —
    /// the original file it points to is completely untouched).
    func removeSong(_ song: Song) {
        try? FileManager.default.trashItem(at: song.url, resultingItemURL: nil)
        invalidateSongsCache(for: song.url.deletingLastPathComponent())
        objectWillChange.send()
    }

    /// Accepts file URLs dragged in from Finder and adds them to a playlist
    /// as aliases. Shared by both the sidebar's playlist row and the open
    /// song list, so dropping files works the same way in either place.
    func handleFileDrop(providers: [NSItemProvider], into playlist: Playlist) -> Bool {
        var didAccept = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didAccept = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let directURL = item as? URL {
                    url = directURL
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    self?.addSongs(urls: [url], to: playlist)
                }
            }
        }
        return didAccept
    }

    private func addAlias(for sourceURL: URL, in playlist: Playlist) {
        saveExternalBookmark(for: sourceURL)

        let ext = sourceURL.pathExtension
        let base = sourceURL.deletingPathExtension().lastPathComponent
        var destination = playlist.url.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = playlist.url.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }

        do {
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: sourceURL)
        } catch {
            print("Failed to alias \(sourceURL.lastPathComponent): \(error)")
        }
    }

    // MARK: - Manual song order (drag-to-reorder in list view)

    private func orderFileURL(for playlist: Playlist) -> URL {
        playlist.url.appendingPathComponent(".playlist_order.plist")
    }

    func customOrder(for playlist: Playlist) -> [String]? {
        let url = orderFileURL(for: playlist)
        guard let data = try? Data(contentsOf: url),
              let order = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String]
        else { return nil }
        return order
    }

    func saveCustomOrder(_ order: [String], for playlist: Playlist) {
        let url = orderFileURL(for: playlist)
        if let data = try? PropertyListSerialization.data(fromPropertyList: order, format: .binary, options: 0) {
            try? data.write(to: url)
        }
        objectWillChange.send()
    }

    // MARK: - Security-scoped bookmark persistence

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if url.startAccessingSecurityScopedResource() {
                setLibrary(url: url)
            }
        } catch {
            print("Failed to restore bookmark: \(error)")
        }
    }

    /// Aliased songs can point outside the library folder, which needs its
    /// own permission grant. Call this right before playing a song.
    func prepareAccess(for song: Song) {
        let target = song.url.resolvingSymlinksInPath()
        guard target != song.url else { return } // not an alias — already covered by library access
        guard let data = loadExternalBookmarks()[target.path] else { return }
        var isStale = false
        if let bookmarkURL = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            _ = bookmarkURL.startAccessingSecurityScopedResource()
        }
    }

    private func saveExternalBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        var dict = loadExternalBookmarks()
        dict[url.path] = data
        if let encoded = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
            UserDefaults.standard.set(encoded, forKey: externalBookmarksKey)
        }
    }

    private func loadExternalBookmarks() -> [String: Data] {
        guard let raw = UserDefaults.standard.data(forKey: externalBookmarksKey),
              let dict = try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil) as? [String: Data]
        else { return [:] }
        return dict
    }
}
