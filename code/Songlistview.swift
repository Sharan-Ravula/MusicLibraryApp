import SwiftUI
import AppKit

enum SongViewMode {
    case list, tile
}

enum SongSortColumn: Hashable {
    case title, artist, album, duration, bitrate, dateAdded
}

/// Which optional columns are shown in list view. Title always shows.
enum OptionalColumn: String, CaseIterable, Identifiable {
    case artist = "Artist"
    case album = "Album"
    case duration = "Duration"
    case bitrate = "Bitrate"
    case dateAdded = "Date Added"

    var id: String { rawValue }
}

struct SongListView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var metadataStore: SongMetadataStore
    @EnvironmentObject private var edits: MetadataEditsStore
    let playlist: Playlist

    @State private var searchText = ""
    @State private var viewMode: SongViewMode = .list
    @State private var sortColumn: SongSortColumn?
    @State private var sortAscending = true
    @State private var editingSong: Song?
    @State private var visibleColumns: Set<OptionalColumn> = Set(OptionalColumn.allCases)

    @State private var titleColumnWidth: CGFloat = 220
    @State private var artistColumnWidth: CGFloat = 130
    @State private var albumColumnWidth: CGFloat = 130
    @State private var durationColumnWidth: CGFloat = 80
    @State private var bitrateColumnWidth: CGFloat = 90
    @State private var dateAddedColumnWidth: CGFloat = 110

    var body: some View {
        let songs = displayedSongs

        Group {
            if viewMode == .list {
                listView(songs: songs)
            } else {
                tileView(songs: songs)
            }
        }
        .searchable(text: $searchText, prompt: "Search songs")
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(SongViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(SongViewMode.tile)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .help("List or Tile View")
            }
            if viewMode == .list {
                ToolbarItem {
                    Menu {
                        ForEach(OptionalColumn.allCases) { column in
                            Button {
                                if visibleColumns.contains(column) {
                                    visibleColumns.remove(column)
                                } else {
                                    visibleColumns.insert(column)
                                }
                            } label: {
                                HStack {
                                    if visibleColumns.contains(column) {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(column.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label("Columns", systemImage: "slider.horizontal.3")
                    }
                    .help("Show or Hide Columns")
                }
            }
            ToolbarItem {
                Button {
                    for song in library.songs(in: playlist) {
                        metadataStore.refresh(for: song)
                    }
                } label: {
                    Label("Refresh Metadata", systemImage: "arrow.clockwise")
                }
                .help("Refresh Metadata")
            }
            ToolbarItem {
                Button {
                    library.chooseAndAddSongs(to: playlist)
                } label: {
                    Label {
                        Text("Add Songs")
                    } icon: {
                        BadgedIcon(systemImage: "music.note")
                    }
                }
                .help("Add Songs")
            }
        }
        .sheet(item: $editingSong) { song in
            SongEditSheet(song: song)
        }
        .onAppear {
            // Kick off metadata loading for the whole playlist right away so
            // duration/bitrate are available promptly for sorting/display.
            for song in library.songs(in: playlist) {
                metadataStore.load(for: song)
            }
        }
    }

    // MARK: - List view (sortable, editable, drag-reorderable table)

    private func listView(songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        headerRow

                        Divider()

                        List {
                            ForEach(songs) { song in
                                songRow(song, in: songs)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                            }
                            .onMove { indices, newOffset in
                                guard sortColumn == nil else { return }
                                var order = songs.map { $0.url.lastPathComponent }
                                order.move(fromOffsets: indices, toOffset: newOffset)
                                library.saveCustomOrder(order, for: playlist)
                            }
                        }
                        .listStyle(.plain)
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 110)
                        }
                        .frame(width: max(totalTableWidth, geo.size.width))

                        if sortColumn != nil {
                            Text("Sorted by column — click the header again to clear sorting and drag songs manually.")
                                .appCaptionFont()
                                .foregroundStyle(.secondary)
                                .padding(6)
                        }
                    }
                    // Never narrower than the viewport (fills nicely when columns
                    // are compact), but can grow wider and scroll instead of
                    // pushing on anything outside this view — this is what stops
                    // column resizing from ever affecting the sidebar.
                    .frame(width: max(totalTableWidth, geo.size.width), height: geo.size.height)
                }
            }
        }
        .task(id: playlist.id) {
            // Give metadata a moment to load (titles/artists may switch from
            // filename-based fallbacks to real tags), then size every column
            // to fit its widest visible content — including the header label
            // itself — so nothing truncates, but nothing grows bigger than
            // it needs to either.
            try? await Task.sleep(nanoseconds: 400_000_000)
            titleColumnWidth = idealWidth(for: songs.map { displayTitle(for: $0) } + ["Title"], min: 100, max: 400)
            artistColumnWidth = idealWidth(for: songs.map { displayArtist(for: $0) } + ["Artist"], min: 60, max: 260)
            albumColumnWidth = idealWidth(for: songs.map { displayAlbum(for: $0) } + ["Album"], min: 60, max: 260)
            durationColumnWidth = idealWidth(
                for: songs.map { formatDuration(metadataStore.metadata(for: $0)?.duration) } + ["Duration"],
                min: 50, max: 90
            )
            bitrateColumnWidth = idealWidth(
                for: songs.map { formatBitrate(metadataStore.metadata(for: $0)?.bitrateKbps) } + ["Bitrate"],
                min: 60, max: 100
            )
            dateAddedColumnWidth = idealWidth(
                for: songs.map { formatDate(metadataStore.metadata(for: $0)?.dateAdded) } + ["Date Added"],
                min: 70, max: 140
            )
        }
    }

    /// Sum of every visible column's width plus its handle/gap and the
    /// leading icon gutter — the table's true content width.
    private var totalTableWidth: CGFloat {
        var width: CGFloat = 20 + titleColumnWidth + 9
        if visibleColumns.contains(.artist) { width += artistColumnWidth + 9 }
        if visibleColumns.contains(.album) { width += albumColumnWidth + 9 }
        if visibleColumns.contains(.duration) { width += durationColumnWidth + 9 }
        if visibleColumns.contains(.bitrate) { width += bitrateColumnWidth + 9 }
        if visibleColumns.contains(.dateAdded) { width += dateAddedColumnWidth + 9 }
        return width + 20 // horizontal padding
    }

    /// Measures the widest string in the given list and returns a width just
    /// big enough to show it without truncating, clamped to a sane range.
    private func idealWidth(for strings: [String], min: CGFloat, max: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = strings
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? min
        return Swift.min(Swift.max(widest + 24, min), max)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 20)

            columnHeader("Title", .title)
                .frame(width: titleColumnWidth, alignment: .leading)
            ColumnResizeHandle(width: $titleColumnWidth, minWidth: 100, maxWidth: 400)

            if visibleColumns.contains(.artist) {
                columnHeader("Artist", .artist)
                    .frame(width: artistColumnWidth, alignment: .center)
                ColumnResizeHandle(width: $artistColumnWidth, minWidth: 60, maxWidth: 260)
            }
            if visibleColumns.contains(.album) {
                columnHeader("Album", .album)
                    .frame(width: albumColumnWidth, alignment: .center)
                ColumnResizeHandle(width: $albumColumnWidth, minWidth: 60, maxWidth: 260)
            }
            if visibleColumns.contains(.duration) {
                columnHeader("Duration", .duration)
                    .frame(width: durationColumnWidth, alignment: .center)
                ColumnResizeHandle(width: $durationColumnWidth, minWidth: 50, maxWidth: 90)
            }
            if visibleColumns.contains(.bitrate) {
                columnHeader("Bitrate", .bitrate)
                    .frame(width: bitrateColumnWidth, alignment: .center)
                ColumnResizeHandle(width: $bitrateColumnWidth, minWidth: 60, maxWidth: 100)
            }
            if visibleColumns.contains(.dateAdded) {
                columnHeader("Date Added", .dateAdded)
                    .frame(width: dateAddedColumnWidth, alignment: .center)
                ColumnResizeHandle(width: $dateAddedColumnWidth, minWidth: 70, maxWidth: 140)
            }

            Spacer(minLength: 0)
        }
        .appCaptionBoldFont()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func columnHeader(_ title: String, _ column: SongSortColumn) -> some View {
        HStack(spacing: 3) {
            Text(title)
            if sortColumn == column {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .appCaption2Font()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if sortColumn == column {
                if sortAscending {
                    sortAscending = false
                } else {
                    sortColumn = nil
                    sortAscending = true
                }
            } else {
                sortColumn = column
                sortAscending = true
            }
        }
    }

    private func songRow(_ song: Song, in songs: [Song]) -> some View {
        let meta = metadataStore.metadata(for: song)
        return HStack(spacing: 0) {
            Image(systemName: player.currentSong == song ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(player.currentSong == song ? Color.accentColor : .secondary)
                .frame(width: 20)

            MarqueeText(text: displayTitle(for: song), size: 13, alignment: .leading)
                .frame(width: titleColumnWidth, alignment: .leading)
            Color.clear.frame(width: 9)

            if visibleColumns.contains(.artist) {
                Text(displayArtist(for: song))
                    .appCaptionFont()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: artistColumnWidth, alignment: .center)
                Color.clear.frame(width: 9)
            }

            if visibleColumns.contains(.album) {
                Text(displayAlbum(for: song))
                    .appCaptionFont()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: albumColumnWidth, alignment: .center)
                Color.clear.frame(width: 9)
            }

            if visibleColumns.contains(.duration) {
                Text(formatDuration(meta?.duration))
                    .appCaptionFont()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: durationColumnWidth, alignment: .center)
                Color.clear.frame(width: 9)
            }

            if visibleColumns.contains(.bitrate) {
                Text(formatBitrate(meta?.bitrateKbps))
                    .appCaptionFont()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: bitrateColumnWidth, alignment: .center)
                Color.clear.frame(width: 9)
            }

            if visibleColumns.contains(.dateAdded) {
                Text(formatDate(meta?.dateAdded))
                    .appCaptionFont()
                    .foregroundStyle(.secondary)
                    .frame(width: dateAddedColumnWidth, alignment: .center)
                Color.clear.frame(width: 9)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
        }
        .onTapGesture(count: 2) {
            library.prepareAccess(for: song)
            player.play(song: song, in: songs)
        }
        .contextMenu {
            songContextMenu(for: song, in: songs)
        }
    }

    // MARK: - Tile view

    private func tileView(songs: [Song]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)], spacing: 20) {
                ForEach(songs) { song in
                    tile(for: song, in: songs)
                }
            }
            .padding(16)
        }
    }

    private func tile(for song: Song, in songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            artworkView(for: song)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if player.currentSong == song {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }

            Text(displayTitle(for: song))
                .appCaptionFont()
                .lineLimit(1)
            Text(displayArtist(for: song))
                .appCaption2Font()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            library.prepareAccess(for: song)
            player.play(song: song, in: songs)
        }
        .contextMenu {
            songContextMenu(for: song, in: songs)
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
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Shared context menu

    @ViewBuilder
    private func songContextMenu(for song: Song, in songs: [Song]) -> some View {
        Button("Play") {
            library.prepareAccess(for: song)
            player.play(song: song, in: songs)
        }
        Button("Play Next") {
            library.prepareAccess(for: song)
            player.queueNext(song)
        }
        Divider()
        Menu("Add to Playlist") {
            ForEach(library.playlists.filter { $0 != playlist }) { target in
                Button(target.name) {
                    library.addSongs(urls: [song.playbackURL], to: target)
                }
            }
        }
        Button("Edit Info…") { editingSong = song }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([song.url])
        }
        Button("Remove from Playlist", role: .destructive) {
            library.removeSong(song)
        }
    }

    // MARK: - Ordering, filtering, formatting

    private var displayedSongs: [Song] {
        let base = library.songs(in: playlist)
        let searched = searchText.isEmpty
            ? base
            : base.filter { displayTitle(for: $0).localizedCaseInsensitiveContains(searchText) }

        if let sortColumn {
            return sorted(searched, by: sortColumn, ascending: sortAscending)
        }

        if let order = library.customOrder(for: playlist) {
            let indexMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return searched.sorted {
                (indexMap[$0.url.lastPathComponent] ?? Int.max) < (indexMap[$1.url.lastPathComponent] ?? Int.max)
            }
        }
        return searched
    }

    private func sorted(_ songs: [Song], by column: SongSortColumn, ascending: Bool) -> [Song] {
        let result = songs.sorted { a, b in
            switch column {
            case .title:
                return displayTitle(for: a).localizedCaseInsensitiveCompare(displayTitle(for: b)) == .orderedAscending
            case .artist:
                return displayArtist(for: a).localizedCaseInsensitiveCompare(displayArtist(for: b)) == .orderedAscending
            case .album:
                return displayAlbum(for: a).localizedCaseInsensitiveCompare(displayAlbum(for: b)) == .orderedAscending
            case .duration:
                return (metadataStore.metadata(for: a)?.duration ?? 0) < (metadataStore.metadata(for: b)?.duration ?? 0)
            case .bitrate:
                return (metadataStore.metadata(for: a)?.bitrateKbps ?? 0) < (metadataStore.metadata(for: b)?.bitrateKbps ?? 0)
            case .dateAdded:
                let dateA = metadataStore.metadata(for: a)?.dateAdded ?? .distantPast
                let dateB = metadataStore.metadata(for: b)?.dateAdded ?? .distantPast
                return dateA < dateB
            }
        }
        return ascending ? result : result.reversed()
    }

    private func displayTitle(for song: Song) -> String {
        if let t = edits.edit(for: song)?.title, !t.isEmpty { return t }
        if let t = metadataStore.metadata(for: song)?.title, !t.isEmpty { return t }
        return song.title
    }

    private func displayArtist(for song: Song) -> String {
        if let a = edits.edit(for: song)?.artist, !a.isEmpty { return a }
        return metadataStore.metadata(for: song)?.artist ?? ""
    }

    private func displayAlbum(for song: Song) -> String {
        if let a = edits.edit(for: song)?.album, !a.isEmpty { return a }
        return metadataStore.metadata(for: song)?.album ?? ""
    }

    private func effectiveArtwork(for song: Song) -> NSImage? {
        if let data = edits.edit(for: song)?.artworkData, let image = NSImage(data: data) {
            return image
        }
        return metadataStore.metadata(for: song)?.artwork
    }

    private func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatBitrate(_ kbps: Int?) -> String {
        guard let kbps else { return "—" }
        return "\(kbps) kbps"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
