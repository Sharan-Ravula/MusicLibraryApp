import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var metadataStore: SongMetadataStore
    @EnvironmentObject private var edits: MetadataEditsStore
    @EnvironmentObject private var uiState: UIState
    @EnvironmentObject private var settings: AppSettings

    @State private var selectedPlaylist: Playlist?
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var renamingPlaylist: Playlist?
    @State private var renameText = ""
    @State private var queueWidth: CGFloat = 280
    @State private var showThemePicker = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if library.breadcrumbs.count > 1 {
                    breadcrumbBar
                    Divider()
                }

                List(selection: $selectedPlaylist) {
                    Section("Playlists (\(library.playlists.count))") {
                        ForEach(library.playlists) { playlist in
                            HStack {
                                Label(playlist.name, systemImage: "music.note.list")
                                    .foregroundStyle(settings.theme.color)
                                Spacer()
                                if library.hasSubfolders(playlist) {
                                    Button {
                                        library.navigateInto(playlist)
                                        selectedPlaylist = nil
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open \"\(playlist.name)\" Folder")
                                }
                            }
                            .tag(playlist)
                            .contextMenu {
                                Button("Add Songs…") { library.chooseAndAddSongs(to: playlist) }
                                Button("Rename…") {
                                    renamingPlaylist = playlist
                                    renameText = playlist.name
                                }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([playlist.url])
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    if selectedPlaylist == playlist { selectedPlaylist = nil }
                                    library.delete(playlist)
                                }
                            }
                            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                handleDrop(providers: providers, into: playlist)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            .navigationTitle("MusicLibrary")
        } detail: {
            // The player bar's safeAreaInset is attached HERE, inside the
            // detail column, wrapping song list + queue together — not on
            // the whole window. That's what keeps it from ever visually
            // covering the sidebar: the sidebar isn't part of this subtree.
            HStack(spacing: 0) {
                if let selectedPlaylist {
                    SongListView(playlist: selectedPlaylist)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a playlist from the sidebar")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if uiState.showQueue {
                    ColumnResizeHandle(
                        width: $queueWidth,
                        minWidth: 220,
                        maxWidth: 420,
                        fullHeight: true,
                        invertDrag: true
                    )
                    QueueView()
                        .frame(width: queueWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: uiState.showQueue)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    PlayerBar()
                    if !statusBarText.isEmpty {
                        Divider()
                        Text(statusBarText)
                            .appCaption2Font()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(.bar)
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        library.chooseLibraryFolder()
                    } label: {
                        Label("Choose Folder", systemImage: "folder.badge.plus")
                    }
                    .help("Choose Music Folder")
                }
                ToolbarItem {
                    Button {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Label {
                            Text("New Playlist")
                        } icon: {
                            BadgedIcon(systemImage: "music.note.list")
                        }
                    }
                    .disabled(library.libraryURL == nil)
                    .help("New Playlist")
                }
                ToolbarItem {
                    Button {
                        showThemePicker.toggle()
                    } label: {
                        Label("Theme", systemImage: "paintpalette")
                    }
                    .help("Choose Color Theme")
                    .popover(isPresented: $showThemePicker) {
                        PreferencesView()
                    }
                }
            }
        }
        .onAppear {
            NotificationManager.shared.requestAuthorization()
            player.titleResolver = { song in
                if let t = edits.edit(for: song)?.title, !t.isEmpty { return t }
                let tagTitle = metadataStore.metadata(for: song)?.title
                return (tagTitle?.isEmpty == false) ? tagTitle! : song.title
            }
            player.artistResolver = { song in
                if let a = edits.edit(for: song)?.artist, !a.isEmpty { return a }
                return metadataStore.metadata(for: song)?.artist
            }
            player.artworkResolver = { song in
                if let data = edits.edit(for: song)?.artworkData, let image = NSImage(data: data) {
                    return image
                }
                return metadataStore.metadata(for: song)?.artwork
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") { library.createPlaylist(named: newPlaylistName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: Binding(
            get: { renamingPlaylist != nil },
            set: { if !$0 { renamingPlaylist = nil } }
        )) {
            TextField("Playlist name", text: $renameText)
            Button("Rename") {
                if let playlist = renamingPlaylist {
                    library.rename(playlist, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Text like "17 songs • 57 min" for the currently selected playlist,
    /// shown in the status bar at the bottom of the window.
    /// Row of tappable folder names — Root › Subfolder › Deeper — showing
    /// where you are and letting you jump back to any ancestor folder.
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if library.breadcrumbs.count > 1 {
                    Button {
                        library.navigateToParent()
                        selectedPlaylist = nil
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .appCaption2Font()
                    .help("Back")
                }

                ForEach(Array(library.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                    Button(crumb.name) {
                        library.navigate(to: crumb.url)
                        selectedPlaylist = nil
                    }
                    .buttonStyle(.plain)
                    .appCaption2Font()
                    .foregroundStyle(index == library.breadcrumbs.count - 1 ? Color.primary : settings.theme.color)

                    if index < library.breadcrumbs.count - 1 {
                        Image(systemName: "chevron.right")
                            .appCaption2Font()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var statusBarText: String {
        guard let selectedPlaylist else { return "" }
        let songs = library.songs(in: selectedPlaylist)
        let count = songs.count
        let totalSeconds = songs.compactMap { metadataStore.metadata(for: $0)?.duration }.reduce(0, +)
        let totalMinutes = Int(totalSeconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let songWord = count == 1 ? "song" : "songs"
        let durationText = hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
        return "\(count) \(songWord) • \(durationText)"
    }

    /// Drag-and-drop files onto a playlist row in the sidebar → adds them as aliases.
    private func handleDrop(providers: [NSItemProvider], into playlist: Playlist) -> Bool {
        var didAccept = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didAccept = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let directURL = item as? URL {
                    url = directURL
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    library.addSongs(urls: [url], to: playlist)
                }
            }
        }
        return didAccept
    }
}
