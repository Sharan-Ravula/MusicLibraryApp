import AppKit

/// The title/artist/album/artwork shown for a song always prefer a
/// user-entered edit, then the file's own tags, then finally the filename —
/// shared in one place so every view (player bar, menu bar, song list,
/// queue) resolves it identically.
@MainActor
extension Song {
    func displayTitle(edits: MetadataEditsStore, metadataStore: SongMetadataStore) -> String {
        if let t = edits.edit(for: self)?.title, !t.isEmpty { return t.normalizedForDisplay }
        if let t = metadataStore.metadata(for: self)?.title, !t.isEmpty { return t.normalizedForDisplay }
        return title.normalizedForDisplay
    }

    func displayArtist(edits: MetadataEditsStore, metadataStore: SongMetadataStore) -> String {
        if let a = edits.edit(for: self)?.artist, !a.isEmpty { return a.normalizedForDisplay }
        return (metadataStore.metadata(for: self)?.artist ?? "").normalizedForDisplay
    }

    func displayAlbum(edits: MetadataEditsStore, metadataStore: SongMetadataStore) -> String {
        if let a = edits.edit(for: self)?.album, !a.isEmpty { return a.normalizedForDisplay }
        return (metadataStore.metadata(for: self)?.album ?? "").normalizedForDisplay
    }

    func effectiveArtwork(edits: MetadataEditsStore, metadataStore: SongMetadataStore) -> NSImage? {
        if let image = edits.artwork(for: self) {
            return image
        }
        return metadataStore.metadata(for: self)?.artwork
    }
}
