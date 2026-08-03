import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SongViewMode {
    case list, tile
}

enum SongSortColumn: Hashable {
    case title, artist, album, duration, bitrate, dateAdded, channels, sampleRate, bitsPerSample, fileSize, format

    var label: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .duration: return "Duration"
        case .bitrate: return "Bitrate"
        case .dateAdded: return "Date Added"
        case .channels: return "Channels"
        case .sampleRate: return "Sample Rate"
        case .bitsPerSample: return "Bit Depth"
        case .fileSize: return "File Size"
        case .format: return "Format"
        }
    }
}

/// Which optional columns are shown in list view, and in what order.
/// Title always shows first and isn't part of this reordering — it's the
/// anchor column, similar to a frozen "Name" column in Finder/Excel.
enum OptionalColumn: String, CaseIterable, Identifiable {
    case artist = "Artist"
    case album = "Album"
    case duration = "Duration"
    case bitrate = "Bitrate"
    case format = "Format"
    case sampleRate = "Sample Rate"
    case bitsPerSample = "Bit Depth"
    case channels = "Channels"
    case fileSize = "File Size"
    case dateAdded = "Date Added"

    var id: String { rawValue }

    var sortColumn: SongSortColumn {
        switch self {
        case .artist: return .artist
        case .album: return .album
        case .duration: return .duration
        case .bitrate: return .bitrate
        case .format: return .format
        case .sampleRate: return .sampleRate
        case .bitsPerSample: return .bitsPerSample
        case .channels: return .channels
        case .fileSize: return .fileSize
        case .dateAdded: return .dateAdded
        }
    }

    var widthRange: (min: CGFloat, max: CGFloat) {
        switch self {
        case .artist: return (60, 260)
        case .album: return (60, 260)
        case .duration: return (50, 90)
        case .bitrate: return (60, 100)
        case .format: return (50, 100)
        case .sampleRate: return (60, 110)
        case .bitsPerSample: return (60, 100)
        case .channels: return (60, 100)
        case .fileSize: return (60, 110)
        case .dateAdded: return (70, 140)
        }
    }
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
    @State private var draggedSong: Song?
    @State private var draggedColumn: OptionalColumn?
    @State private var visibleColumns: Set<OptionalColumn> = Set(OptionalColumn.allCases)
    /// The display order of optional columns — drag a header to reorder.
    @State private var columnOrder: [OptionalColumn] = OptionalColumn.allCases

    @State private var titleColumnWidth: CGFloat = 220
    @State private var artistColumnWidth: CGFloat = 130
    @State private var albumColumnWidth: CGFloat = 130
    @State private var durationColumnWidth: CGFloat = 80
    @State private var bitrateColumnWidth: CGFloat = 90
    @State private var formatColumnWidth: CGFloat = 80
    @State private var sampleRateColumnWidth: CGFloat = 90
    @State private var bitsPerSampleColumnWidth: CGFloat = 80
    @State private var channelsColumnWidth: CGFloat = 80
    @State private var fileSizeColumnWidth: CGFloat = 90
    @State private var dateAddedColumnWidth: CGFloat = 110

    private var orderedVisibleColumns: [OptionalColumn] {
        columnOrder.filter { visibleColumns.contains($0) }
    }

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
                        ForEach(columnOrder) { column in
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
                    .help("Show or Hide Columns — drag a column header to reorder them")
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
                                    // List's native drag-to-reorder (.onMove)
                                    // doesn't reliably work here because this
                                    // List is nested inside a horizontal
                                    // ScrollView (needed so wide columns
                                    // scroll instead of distorting the
                                    // window) — the outer scroll view's own
                                    // gesture handling interferes with the
                                    // List's internal drag-session. Handling
                                    // it manually via onDrag/onDrop sidesteps
                                    // that entirely.
                                    .onDrag {
                                        draggedSong = song
                                        return NSItemProvider(object: song.id.absoluteString as NSString)
                                    }
                                    .onDrop(of: [.text], isTargeted: nil) { _ in
                                        guard sortColumn == nil, let draggedSong, draggedSong != song else { return false }
                                        reorder(dragged: draggedSong, onto: song, in: songs)
                                        self.draggedSong = nil
                                        return true
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .frame(width: max(totalTableWidth, geo.size.width))

                        sortStatusBar
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
            titleColumnWidth = idealWidth(for: songs.map { displayTitle(for: $0) } + ["Title"], min: 100, max: 700)
            for column in OptionalColumn.allCases {
                let values = songs.map { cellText(for: column, song: $0) } + [column.rawValue]
                let range = column.widthRange
                widthBinding(for: column).wrappedValue = idealWidth(for: values, min: range.min, max: range.max)
            }
        }
    }

    /// Sum of every visible column's width plus its handle/gap and the
    /// leading icon gutter — the table's true content width.
    private var totalTableWidth: CGFloat {
        var width: CGFloat = 38 + titleColumnWidth + 9
        for column in orderedVisibleColumns {
            width += widthBinding(for: column).wrappedValue + 9
        }
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

    /// Maps each optional column to its own @State width binding.
    private func widthBinding(for column: OptionalColumn) -> Binding<CGFloat> {
        switch column {
        case .artist: return $artistColumnWidth
        case .album: return $albumColumnWidth
        case .duration: return $durationColumnWidth
        case .bitrate: return $bitrateColumnWidth
        case .format: return $formatColumnWidth
        case .sampleRate: return $sampleRateColumnWidth
        case .bitsPerSample: return $bitsPerSampleColumnWidth
        case .channels: return $channelsColumnWidth
        case .fileSize: return $fileSizeColumnWidth
        case .dateAdded: return $dateAddedColumnWidth
        }
    }

    private func cellText(for column: OptionalColumn, song: Song) -> String {
        let meta = metadataStore.metadata(for: song)
        switch column {
        case .artist: return displayArtist(for: song)
        case .album: return displayAlbum(for: song)
        case .duration: return formatDuration(meta?.duration)
        case .bitrate: return formatBitrate(meta?.bitrateKbps)
        case .format: return song.url.pathExtension.uppercased()
        case .sampleRate: return formatSampleRate(meta?.sampleRateHz)
        case .bitsPerSample: return formatBitsPerSample(meta?.bitsPerSample)
        case .channels: return formatChannels(meta?.channels)
        case .fileSize: return formatFileSize(meta?.fileSizeBytes)
        case .dateAdded: return formatDate(meta?.dateAdded)
        }
    }

    /// Moves a dropped column to sit where it was dropped.
    private func reorderColumns(dragged: OptionalColumn, onto target: OptionalColumn) {
        guard let fromIndex = columnOrder.firstIndex(of: dragged),
              let toIndex = columnOrder.firstIndex(of: target) else { return }
        let moved = columnOrder.remove(at: fromIndex)
        columnOrder.insert(moved, at: toIndex)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 38)

            columnHeader("Title", .title)
                .frame(width: titleColumnWidth, alignment: .leading)
            ColumnResizeHandle(width: $titleColumnWidth, minWidth: 100, maxWidth: 700)

            ForEach(orderedVisibleColumns) { column in
                let range = column.widthRange
                columnHeader(column.rawValue, column.sortColumn)
                    .frame(width: widthBinding(for: column).wrappedValue, alignment: .center)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggedColumn = column
                        return NSItemProvider(object: column.rawValue as NSString)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { _ in
                        guard let draggedColumn, draggedColumn != column else { return false }
                        reorderColumns(dragged: draggedColumn, onto: column)
                        self.draggedColumn = nil
                        return true
                    }
                    .help("Click to sort by \(column.rawValue) • Drag to reorder columns")
                ColumnResizeHandle(width: widthBinding(for: column), minWidth: range.min, maxWidth: range.max)
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

    /// Explains what's currently happening with sorting, and gives a direct
    /// way to reset it — a plain caption alone wasn't a clear or actionable
    /// way to communicate "sorting is on, and it's why drag-reorder is off."
    @ViewBuilder
    private var sortStatusBar: some View {
        if let sortColumn {
            HStack(spacing: 8) {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .appCaption2Font()
                    .foregroundStyle(Color.accentColor)
                Text("Sorted by \(sortColumn.label) — manual drag reordering is off while a sort is active.")
                    .appCaptionFont()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    self.sortColumn = nil
                    self.sortAscending = true
                } label: {
                    Label("Clear Sort", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .appCaptionFont()
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.bar)
        }
    }

    private func songRow(_ song: Song, in songs: [Song]) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                // A visual cue that this row can be dragged to reorder —
                // only shown when that's actually possible (unsorted). Click
                // and drag anywhere on the row itself to reorder — this icon
                // is just a hint, not the only draggable spot.
                if sortColumn == nil {
                    Image(systemName: "line.3.horizontal")
                        .appCaption2Font()
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                Image(systemName: player.currentSong == song ? "speaker.wave.2.fill" : "music.note")
                    .foregroundStyle(player.currentSong == song ? Color.accentColor : .secondary)
            }
            .frame(width: 38)

            MarqueeText(text: displayTitle(for: song), size: 13, alignment: .leading)
                .frame(width: titleColumnWidth, alignment: .leading)
            Color.clear.frame(width: 9)

            ForEach(orderedVisibleColumns) { column in
                Text(cellText(for: column, song: song))
                    .appCaptionFont()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: widthBinding(for: column).wrappedValue, alignment: .center)
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

    /// Moves the dragged song to sit right where it was dropped, and
    /// persists the new order.
    private func reorder(dragged: Song, onto target: Song, in songs: [Song]) {
        guard let fromIndex = songs.firstIndex(of: dragged),
              let toIndex = songs.firstIndex(of: target) else { return }
        var order = songs.map { $0.url.lastPathComponent }
        let moved = order.remove(at: fromIndex)
        order.insert(moved, at: toIndex)
        library.saveCustomOrder(order, for: playlist)
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
            case .format:
                return a.url.pathExtension.localizedCaseInsensitiveCompare(b.url.pathExtension) == .orderedAscending
            case .dateAdded:
                let dateA = metadataStore.metadata(for: a)?.dateAdded ?? .distantPast
                let dateB = metadataStore.metadata(for: b)?.dateAdded ?? .distantPast
                return dateA < dateB
            case .channels:
                return (metadataStore.metadata(for: a)?.channels ?? 0) < (metadataStore.metadata(for: b)?.channels ?? 0)
            case .sampleRate:
                return (metadataStore.metadata(for: a)?.sampleRateHz ?? 0) < (metadataStore.metadata(for: b)?.sampleRateHz ?? 0)
            case .bitsPerSample:
                return (metadataStore.metadata(for: a)?.bitsPerSample ?? 0) < (metadataStore.metadata(for: b)?.bitsPerSample ?? 0)
            case .fileSize:
                return (metadataStore.metadata(for: a)?.fileSizeBytes ?? 0) < (metadataStore.metadata(for: b)?.fileSizeBytes ?? 0)
            }
        }
        return ascending ? result : result.reversed()
    }

    private func displayTitle(for song: Song) -> String {
        if let t = edits.edit(for: song)?.title, !t.isEmpty { return t.normalizedForDisplay }
        if let t = metadataStore.metadata(for: song)?.title, !t.isEmpty { return t.normalizedForDisplay }
        return song.title.normalizedForDisplay
    }

    private func displayArtist(for song: Song) -> String {
        if let a = edits.edit(for: song)?.artist, !a.isEmpty { return a.normalizedForDisplay }
        return (metadataStore.metadata(for: song)?.artist ?? "").normalizedForDisplay
    }

    private func displayAlbum(for song: Song) -> String {
        if let a = edits.edit(for: song)?.album, !a.isEmpty { return a.normalizedForDisplay }
        return (metadataStore.metadata(for: song)?.album ?? "").normalizedForDisplay
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

    private func formatChannels(_ channels: Int?) -> String {
        guard let channels else { return "—" }
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(channels) ch"
        }
    }

    private func formatSampleRate(_ rate: Double?) -> String {
        guard let rate, rate > 0 else { return "—" }
        return String(format: "%.1f kHz", rate / 1000)
    }

    private func formatBitsPerSample(_ bits: Int?) -> String {
        guard let bits, bits > 0 else { return "—" }
        return "\(bits)-bit"
    }

    private func formatFileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
