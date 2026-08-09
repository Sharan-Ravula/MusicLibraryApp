import SwiftUI

@main
struct MusicLibraryApp: App {
    @StateObject private var library = LibraryManager()
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var metadataStore = SongMetadataStore()
    @StateObject private var edits = MetadataEditsStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var uiState = UIState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(metadataStore)
                .environmentObject(edits)
                .environmentObject(settings)
                .environmentObject(uiState)
                .environment(\.appFontScale, settings.fontScale)
                .tint(settings.theme.color)
                .frame(minWidth: 950, minHeight: 550)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Increase Font Size") {
                    settings.increaseFontSize()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Font Size") {
                    settings.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)
            }

            CommandMenu("Controls") {
                // Disabled while a text field (e.g. song search) has focus —
                // Space and ⌘←/⌘→ are also standard text-editing keys
                // (insert space, move cursor to line start/end), and a
                // disabled menu item's key equivalent doesn't fire, so this
                // stops these shortcuts from hijacking normal typing.
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(uiState.isTextInputActive)

                Button("Next Track") {
                    player.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(uiState.isTextInputActive)

                Button("Previous Track") {
                    player.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(uiState.isTextInputActive)
            }
        }

        MenuBarExtra("MusicLibrary", systemImage: "music.note") {
            MenuBarPlayerView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(player.clock)
                .environmentObject(metadataStore)
                .environmentObject(edits)
                .environment(\.appFontScale, settings.fontScale)
                .tint(settings.theme.color)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(settings)
        }
    }
}
