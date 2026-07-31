# MusicLibrary

A native macOS music player built with SwiftUI. Your music library is just folders on disk — every subfolder in your chosen library folder is a playlist, and songs are added as **aliases (symlinks)**, never copies, so nothing is duplicated on disk and one song can live in multiple playlists at once.

## Features

**Library & Playlists**
- Point the app at any folder — each subfolder becomes a playlist automatically
- Navigate nested folders: drill into subfolders with a `›` chevron, browse back up with breadcrumbs (Root › Rock › 90s) or a back button
- Create, rename, delete, and drag-and-drop songs into playlists directly from the sidebar
- Add songs via file picker or by dragging audio files onto a playlist
- Songs are added as aliases/symlinks — your real files never move or get duplicated

**Playback**
- Play/pause, next/previous, shuffle, repeat (off / all / one)
- Smooth animated scrubber with live elapsed/remaining time
- Volume control
- Real macOS media key support (keyboard media keys, Touch Bar, Bluetooth headphones) via `MPRemoteCommandCenter`
- Now Playing shows up in Control Center via `MPNowPlayingInfoCenter`
- In-app keyboard shortcuts: Space to play/pause, Cmd+←/→ for previous/next
- System notifications when a new song starts, with the song's artwork attached (falls back to the app icon if there's none)

**Song List**
- Sortable, resizable-column table view: Title, Artist, Album, Duration, Bitrate, Date Added
- Toggle which columns are visible
- Drag-and-drop manual reordering (when not sorted by a column)
- Tile/grid view as an alternative to the list
- Search/filter within a playlist
- Scrolling "marquee" title for text too long to fit — hover to scroll in the table, auto-scrolls continuously in the player bar

**Metadata**
- Reads real ID3/metadata tags, embedded artwork, duration, and bitrate directly from your files via `AVFoundation`
- Edit title/artist/album and set custom artwork per song from within the app — stored as an app-side overlay (not written into the original files)
- Metadata is cached to disk so relaunching the app doesn't require re-scanning your whole library

**Queue**
- Toggleable "Continue Playing" panel showing what's queued next
- "Play Next" from any song's context menu
- Resizable panel width

**Menu Bar**
- Mini player accessible from the menu bar with full playback controls and live progress

**Customization**
- 11 color themes, accessible via a toolbar button (palette icon) or Cmd+, for the full Preferences window
- App-wide font size scaling (Cmd+= / Cmd+-)
- Hover tooltips on every icon button

## Requirements

- macOS 13.0 or later
- Xcode 15 or later

## Building

1. Clone the repo
2. Open `MusicLibrary.xcodeproj` (or create a new Xcode project and add these files — see below)
3. In the target's **Signing & Capabilities**, ensure **App Sandbox → File Access → User Selected File** is set to **Read/Write**
4. Build and run (Cmd+R)

### If setting up from source files rather than a `.xcodeproj`

1. Create a new **macOS App** project in Xcode (SwiftUI interface)
2. Delete the default `ContentView.swift`
3. Add all `.swift` files from this repo to the project
4. Set minimum deployment target to macOS 13.0
5. Enable **App Sandbox** with **User Selected File: Read/Write** under Signing & Capabilities

## Usage

1. Launch the app and click **Choose Folder** in the sidebar toolbar
2. Select a parent folder containing one subfolder per playlist:
   ```
   MyMusic/
   ├── Road Trip/
   │   ├── song1.mp3
   │   └── song2.m4a
   ├── Chill/
   │   └── song3.flac
   └── Workout/
       └── song4.mp3
   ```
3. Double-click any song to play it

## Files to Upload

```
MusicLibrary/
├── README.md
├── MusicLibrary.xcodeproj/
└── Code/
    ├── MusicLibraryApp.swift
    ├── ContentView.swift
    ├── Models.swift
    ├── LibraryManager.swift
    ├── AudioPlayerManager.swift
    ├── PlaybackClock.swift
    ├── SongMetadataStore.swift
    ├── MetadataEditsStore.swift
    ├── SongListView.swift
    ├── SongEditSheet.swift
    ├── PlayerBar.swift
    ├── QueueView.swift
    ├── MenuBarPlayerView.swift
    ├── MarqueeText.swift
    ├── ColumnResizeHandle.swift
    ├── PlayerControlButton.swift
    ├── BadgedIcon.swift
    ├── NotificationManager.swift
    ├── AppSettings.swift
    ├── AppFontScale.swift
    ├── PreferencesView.swift
    └── UIState.swift
```

That's every `.swift` file in the project (22 total) plus this README. If you have an actual `.xcodeproj` folder from Xcode, upload that too — GitHub will show it as a folder alongside these files.

## Project Structure

| File | Responsibility |
|---|---|
| `MusicLibraryApp.swift` | App entry point, scene setup, keyboard shortcuts, menu commands |
| `ContentView.swift` | Main window layout: sidebar, breadcrumbs, song list, queue panel, player bar |
| `Models.swift` | `Song` and `Playlist` data models |
| `LibraryManager.swift` | Folder scanning and navigation, playlist CRUD, alias creation, security-scoped bookmarks |
| `AudioPlayerManager.swift` | Playback engine, queue management, media key integration |
| `PlaybackClock.swift` | Isolated fast-ticking playback position (keeps the rest of the UI from re-rendering on every tick) |
| `SongMetadataStore.swift` | Reads and caches ID3/metadata tags, artwork, duration, bitrate |
| `MetadataEditsStore.swift` | In-app metadata/artwork overrides |
| `SongListView.swift` | Sortable/resizable song table + tile grid view |
| `SongEditSheet.swift` | Edit title/artist/album/artwork sheet |
| `PlayerBar.swift` | Bottom transport bar |
| `QueueView.swift` | "Continue Playing" panel |
| `MenuBarPlayerView.swift` | Menu bar mini player |
| `MarqueeText.swift` | Scrolling text for overflowing titles |
| `ColumnResizeHandle.swift` | Draggable resize handle (table columns, queue panel) |
| `PlayerControlButton.swift` | Reusable hover-highlighted icon button with tooltip |
| `BadgedIcon.swift` | Base icon + small "+" badge, for actions with no matching built-in SF Symbol |
| `NotificationManager.swift` | Now-playing system notifications with artwork |
| `AppSettings.swift` | Font scale and theme settings |
| `AppFontScale.swift` | App-wide font scaling system |
| `PreferencesView.swift` | Theme picker (toolbar button or Cmd+,) |
| `UIState.swift` | Shared UI toggle state (queue panel visibility) |

## Known Limitations

- **Metadata edits are app-only.** Editing a song's title/artist/album/artwork in the app does *not* rewrite the tags inside the actual audio file — it's stored as an overlay in the app's own data (`~/Library/Application Support/MusicLibrary/metadata_edits.json`). If you move the file elsewhere or open it in another app, your edits won't follow it. Real in-file tag writing (starting with mp3/ID3v2) is a natural next step if needed.
- **Bitrate/duration require a first scan.** The first time you open a playlist, songs show placeholder values until `AVFoundation` finishes reading each file. After that, results are cached to disk and load instantly.
- **Large libraries:** metadata caching is designed to scale (in-memory lookups, debounced disk writes) but hasn't been stress-tested beyond a few thousand songs.

## License

MIT License

Copyright (c) 2026 Sharan Ravula

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
