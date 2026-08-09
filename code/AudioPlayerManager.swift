import Foundation
import AVFoundation
import MediaPlayer
import AppKit
import Combine

enum RepeatMode {
    case off, all, one

    var tooltip: String {
        switch self {
        case .off: return "Repeat"
        case .all: return "Repeat All"
        case .one: return "Repeat One"
        }
    }
}

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0
    @Published var isShuffling = false {
        didSet {
            guard isShuffling != oldValue else { return }
            applyShuffleState()
        }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var currentPlaylistSongs: [Song] = []
    /// The playlist's on-disk order, as originally passed to play(song:in:) —
    /// kept around so turning shuffle back off can restore this order for
    /// whatever hasn't played yet, instead of leaving it shuffled forever.
    private var originalPlaylistSongs: [Song] = []
    @Published var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
            UserDefaults.standard.set(volume, forKey: "playerVolume")
        }
    }

    /// The fast-ticking playback position lives in a separate object so the
    /// whole app doesn't re-render every time it updates. Only PlayerBar
    /// should observe this.
    let clock = PlaybackClock()

    /// The index of currentSong within currentPlaylistSongs. Tracked
    /// explicitly rather than searched-for by value, because a song can
    /// legitimately appear more than once in the queue (e.g. after "Play
    /// Next") — searching by value in that case can find the wrong
    /// occurrence and send playback to the wrong place.
    private var currentIndex: Int?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var titleResolver: ((Song) -> String)?
    var artistResolver: ((Song) -> String?)?
    var artworkResolver: ((Song) -> NSImage?)?
    var accessPreparer: ((Song) -> Void)?

    /// Songs that will play after the current one, in order.
    var upcomingSongs: [Song] {
        guard let currentIndex, currentPlaylistSongs.indices.contains(currentIndex + 1) else { return [] }
        return Array(currentPlaylistSongs[(currentIndex + 1)...])
    }

    override init() {
        super.init()
        if let saved = UserDefaults.standard.object(forKey: "playerVolume") as? Float {
            volume = saved
        }
        configureRemoteCommands()
    }

    /// Starts a fresh queue and plays the given song from it — used when the
    /// person double-clicks a song in the library.
    func play(song: Song, in songs: [Song]) {
        originalPlaylistSongs = songs
        if isShuffling {
            let rest = songs.filter { $0 != song }.shuffled()
            currentPlaylistSongs = [song] + rest
        } else {
            currentPlaylistSongs = songs
        }
        currentIndex = currentPlaylistSongs.firstIndex(of: song)
        startPlayback(song)
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func stop() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        clock.currentTime = time
        updateNowPlayingInfo()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// userInitiated: true when the person pressed the forward button,
    /// false when a song finished playing on its own (so "repeat one" applies).
    func playNext(userInitiated: Bool = true) {
        guard let index = currentIndex, currentPlaylistSongs.indices.contains(index) else { return }

        if repeatMode == .one && !userInitiated {
            startPlayback(currentPlaylistSongs[index])
            return
        }

        // When shuffling, the play order was already decided in advance
        // (see applyShuffleState()/play(song:in:)) — currentPlaylistSongs
        // itself IS the shuffled order, so advancing is just "the next
        // index," same as unshuffled playback. This is what makes the
        // Queue panel (upcomingSongs) show the songs that will actually
        // play next, instead of picking a fresh random song each time
        // playNext() runs.
        var nextIndex = index + 1
        if nextIndex >= currentPlaylistSongs.count {
            guard repeatMode == .all else {
                stop()
                return
            }
            nextIndex = 0
            if isShuffling {
                // Fresh shuffle for the next lap, so repeat-all doesn't
                // replay the exact same sequence over and over.
                currentPlaylistSongs = currentPlaylistSongs.shuffled()
            }
        }
        playAtIndex(nextIndex)
    }

    func playPrevious() {
        guard let index = currentIndex else { return }

        // If you're a few seconds into the song, "previous" restarts the
        // current song rather than skipping back — matches how most music
        // apps behave, and this is also what makes it do something sensible
        // (instead of nothing) when there's no earlier track to jump to.
        if clock.currentTime > 3 {
            seek(to: 0)
            return
        }

        let prevIndex = index - 1
        if currentPlaylistSongs.indices.contains(prevIndex) {
            playAtIndex(prevIndex)
        } else {
            seek(to: 0)
        }
    }

    /// Inserts a song to play right after the current one, without
    /// interrupting what's playing now. If the song is already elsewhere in
    /// the queue, it's moved rather than duplicated (duplicates are exactly
    /// what caused next/previous to jump to the wrong track before).
    func queueNext(_ song: Song) {
        guard let index = currentIndex else {
            originalPlaylistSongs = [song]
            currentPlaylistSongs = [song]
            currentIndex = 0
            startPlayback(song)
            return
        }

        var insertionIndex = index
        if let existing = currentPlaylistSongs.firstIndex(of: song), existing != index {
            currentPlaylistSongs.remove(at: existing)
            if existing < index {
                insertionIndex -= 1
                currentIndex = insertionIndex
            }
        }

        let insertAt = min(insertionIndex + 1, currentPlaylistSongs.count)
        currentPlaylistSongs.insert(song, at: insertAt)
    }

    /// Immediately plays a specific song from the upcoming queue. Moves it to
    /// play next (same placement as queueNext) and starts it directly by
    /// index — unlike playNext(), this ignores shuffle, since the whole
    /// point of picking a specific song from the queue is to hear that song,
    /// not a random one.
    func playNow(_ song: Song) {
        queueNext(song)
        guard let index = currentIndex else { return }
        playAtIndex(index + 1)
    }

    /// Removes everything after the current song from the queue.
    func clearQueue() {
        guard let currentIndex else {
            currentPlaylistSongs = []
            return
        }
        currentPlaylistSongs = Array(currentPlaylistSongs.prefix(currentIndex + 1))
    }

    /// Removes a single upcoming song from the queue (not the one currently playing).
    func removeFromQueue(_ song: Song) {
        guard let currentIndex,
              let index = currentPlaylistSongs.firstIndex(of: song),
              index > currentIndex else { return }
        currentPlaylistSongs.remove(at: index)
    }

    /// Re-derives the upcoming (not-yet-played) portion of the queue when
    /// shuffle is toggled mid-playback, so both the Queue panel and actual
    /// playback immediately reflect the new mode instead of only applying
    /// it the next time a "next" happens.
    private func applyShuffleState() {
        guard let currentIndex, currentPlaylistSongs.indices.contains(currentIndex) else { return }
        let playedAndCurrent = Array(currentPlaylistSongs[...currentIndex])
        let upcoming = Array(currentPlaylistSongs[(currentIndex + 1)...])
        guard !upcoming.isEmpty else { return }

        let newUpcoming: [Song]
        if isShuffling {
            newUpcoming = upcoming.shuffled()
        } else {
            // Restore the playlist's original relative order for whatever
            // hasn't played yet. Any song in the queue that isn't part of
            // the original playlist (e.g. interjected via "Play Next" from
            // a different playlist) keeps its current relative position,
            // appended after the restored songs, rather than disappearing.
            newUpcoming = originalPlaylistSongs.filter { upcoming.contains($0) }
                + upcoming.filter { !originalPlaylistSongs.contains($0) }
        }
        currentPlaylistSongs = playedAndCurrent + newUpcoming
    }

    private func playAtIndex(_ index: Int) {
        guard currentPlaylistSongs.indices.contains(index) else { return }
        currentIndex = index
        startPlayback(currentPlaylistSongs[index])
    }

    private func startPlayback(_ song: Song) {
        accessPreparer?(song)
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: song.playbackURL)
            newPlayer.delegate = self
            newPlayer.volume = volume
            player = newPlayer
            currentSong = song
            duration = newPlayer.duration
            clock.currentTime = 0
            newPlayer.play()
            isPlaying = true
            startTimer()

            let displayTitle = titleResolver?(song) ?? song.title
            NotificationManager.shared.notifyNowPlaying(
                title: displayTitle,
                artist: artistResolver?(song),
                artwork: artworkResolver?(song)
            )
            updateNowPlayingInfo()
        } catch {
            print("Playback failed: \(error)")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        // 50 updates/sec, paired with a matching short linear animation on
        // the slider itself, for genuinely smooth motion instead of visible steps.
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.clock.currentTime = player.currentTime
            }
        }
    }

    // MARK: - Hardware media keys / Control Center "Now Playing"

    /// Registers with the system so physical media keys (keyboard, Touch
    /// Bar, Bluetooth headphones/AirPods, Control Center's Now Playing
    /// widget) control this app. Without this, macOS has nothing to route
    /// those key presses to and they silently do nothing.
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
    }

    /// Tells Control Center / the media key system what's currently playing.
    /// Called on notable state changes rather than every timer tick — the
    /// system interpolates elapsed time on its own from rate + timestamp.
    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = titleResolver?(song) ?? song.title
        if let artist = artistResolver?(song) {
            info[MPMediaItemPropertyArtist] = artist
        }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clock.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.playNext(userInitiated: false)
        }
    }
}
