import AppKit
import Foundation
import Combine
import AmbientCore

enum MusicSource: String, CaseIterable, Hashable, Sendable {
    case spotify = "Spotify"
    var bundleID: String { "com.spotify.client" }
}

@MainActor final class MusicWatcher: ObservableObject {
    @Published private(set) var title = "Nothing playing"
    @Published private(set) var artist = "Play a song in Spotify"
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var playing = false
    @Published private(set) var duration = 0.0
    @Published private(set) var catalogDuration = 0.0
    @Published private(set) var crossfadeCorrection = 0.0
    @Published private(set) var position = 0.0
    @Published private(set) var identity = ""
    @Published private(set) var source: MusicSource?
    @Published private(set) var status = "Waiting to connect"
    @Published private(set) var connected = false
    @Published private(set) var monitoring = false
    @Published private(set) var shuffle = false
    @Published private(set) var volume = 100.0
    @Published private(set) var diagnostics: [String] = []
    private let bridge = AppleEventBridge()
    private let queue = DispatchQueue(label: "local.songambient.playback")
    private var timer: Timer?
    private var anchor = Date(), anchorPosition = 0.0
    private var polling = false
    private var denied = Set<MusicSource>()
    private var artworkTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func connect() {
        monitoring = true; denied = []; status = "Checking Spotify…"
        poll()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.position = self.currentTime(at: Date()); self.poll()
                }
            }
            for name in ["com.spotify.client.PlaybackStateChanged"] {
                observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.poll() } })
            }
        }
    }

    func currentTime(at date: Date) -> Double {
        let value = anchorPosition + (playing ? max(0,date.timeIntervalSince(anchor)) : 0)
        return max(0,duration > 0 ? min(duration,value) : value)
    }

    private func poll() {
        guard monitoring, !polling else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = MusicSource.allCases.filter { running.contains($0.bundleID) && !denied.contains($0) }
        guard !candidates.isEmpty else {
            if denied.isEmpty {
                connected = false; playing = false
                status = "Open Spotify desktop. Other apps never drive the lights."
                diagnostics = MusicSource.allCases.map { "\($0.rawValue): \(running.contains($0.bundleID) ? "running" : "not running")" }
            }
            return
        }
        polling = true
        queue.async { [weak self, bridge] in
            let results = candidates.map { ($0, bridge.read($0)) }
            Task { @MainActor in
                guard let self else { return }
                self.polling = false
                var snapshots: [TrackSnapshot] = [], details: [String] = []
                for (source,result) in results {
                    switch result {
                    case .track(let track): snapshots.append(track); details.append("\(source.rawValue): reading playback")
                    case .empty: details.append("\(source.rawValue): no accessible current track")
                    case .failure(let code, let message):
                        if code == -1743 { self.denied.insert(source) }
                        details.append("\(source.rawValue): \(code == -1743 ? "Automation permission denied. Allow it in Privacy & Security → Automation, then Retry." : "\(message) (\(code))")")
                    }
                }
                self.diagnostics = details
                if let track = snapshots.first(where: \.playing) ?? snapshots.first(where: { $0.source == self.source }) ?? snapshots.first {
                    self.apply(track)
                } else {
                    self.connected = false; self.playing = false
                    self.status = details.first ?? "Waiting for a track"
                }
            }
        }
    }

    private func apply(_ track: TrackSnapshot) {
        title = track.title; artist = track.artist; album = track.album; playing = track.playing
        duration = track.duration; position = track.position; anchorPosition = track.position; anchor = Date()
        crossfadeCorrection=track.crossfade
        catalogDuration=track.duration+track.crossfade
        source = track.source; connected = true; shuffle = track.shuffle; volume = track.volume
        status = "\(track.source.rawValue) · \(track.playing ? "Playing" : "Paused")"
        let nextID = "\(track.source.rawValue)|\(track.id)|\(track.title)|\(track.artist)|\(track.album)"
        guard identity != nextID else { return }
        identity = nextID; artwork = nil; artworkTask?.cancel()
        if let url = URL(string: track.artworkURL), url.scheme == "https" {
            artworkTask = Task {
                if let (data,_) = try? await URLSession.shared.data(from: url), !Task.isCancelled, identity == nextID { artwork = NSImage(data: data) }
            }
        }
    }

    func command(_ command: String) {
        guard let source else { return }
        queue.async { [weak self, bridge] in
            let error = bridge.command(command, source: source)
            Task { @MainActor in if let error { self?.status = error }; self?.poll() }
        }
    }
    func seek(_ seconds: Double) {
        let value = max(0,min(duration,seconds)); anchorPosition = value; anchor = Date(); position = value
        command("set player position to \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value))")
    }
    func toggleShuffle() { command("set shuffling to \(shuffle ? "false" : "true")") }
    func setVolume(_ value: Double) { volume = value; command("set sound volume to \(Int(value))") }
    func open(_ source: MusicSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { status = "\(source.rawValue) is not installed"; return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _,_ in Task { @MainActor in self?.connect() } }
    }
}

private struct TrackSnapshot: Sendable {
    let source: MusicSource
    let title: String, artist: String, album: String, artworkURL: String, id: String
    let duration: Double, position: Double, volume: Double
    let crossfade:Double
    let playing: Bool, shuffle: Bool
}
private enum PlaybackRead { case track(TrackSnapshot), empty, failure(Int,String) }

// Accessed exclusively by the playback queue. No existence event is sent to
// Spotify: its shipping scripting dictionary doesn't implement that command.
private final class AppleEventBridge: @unchecked Sendable {
    private var scripts: [MusicSource:NSAppleScript] = [:]
    private var crossfade=0.0,lastTimingRead=Date.distantPast
    func read(_ source: MusicSource) -> PlaybackRead {
        var error: NSDictionary?
        let script: NSAppleScript
        if let cached = scripts[source] { script = cached }
        else {
            guard let new = NSAppleScript(source: Self.script(source)), new.compileAndReturnError(&error) else { return failure(error) }
            scripts[source] = new; script = new
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1728 || code == -1719 { return .empty }
            return failure(error)
        }
        guard result.numberOfItems >= 10, let name = result.atIndex(1)?.stringValue, !name.isEmpty, name != "missing value" else { return .empty }
        let rawDuration = result.atIndex(4)?.doubleValue ?? 0
        let duration = rawDuration / 1000
        if Date().timeIntervalSince(lastTimingRead)>30{crossfade=SpotifyTimingSettings.crossfadeSeconds();lastTimingRead=Date()}
        return .track(TrackSnapshot(source: source, title: name, artist: result.atIndex(2)?.stringValue ?? "", album: result.atIndex(3)?.stringValue ?? "", artworkURL: result.atIndex(7)?.stringValue ?? "", id: result.atIndex(8)?.stringValue ?? name, duration: duration, position: result.atIndex(5)?.doubleValue ?? 0, volume: result.atIndex(10)?.doubleValue ?? 100, crossfade:crossfade, playing: result.atIndex(6)?.booleanValue ?? false, shuffle: result.atIndex(9)?.booleanValue ?? false))
    }
    func command(_ command: String, source: MusicSource) -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "with timeout of 5 seconds\ntell application id \"\(source.bundleID)\" to \(command)\nend timeout")?.executeAndReturnError(&error)
        return error.map { "\(source.rawValue): \($0[NSAppleScript.errorMessage] as? String ?? "Playback command failed")" }
    }
    private func failure(_ error: NSDictionary?) -> PlaybackRead {
        .failure(error?[NSAppleScript.errorNumber] as? Int ?? 0,String((error?[NSAppleScript.errorMessage] as? String ?? "Cannot read playback").prefix(200)))
    }
    private static func script(_ source: MusicSource) -> String {
        let art = "artwork url of t", id = "id of t"
        let shuffle = "shuffling"
        return """
        with timeout of 8 seconds
          tell application id "\(source.bundleID)"
            set t to current track
            set trackTitle to name of t as text
            set trackArtist to ""
            set trackAlbum to ""
            set trackArt to ""
            set trackID to ""
            set shuffleState to false
            try
              set trackArtist to artist of t as text
            end try
            try
              set trackAlbum to album of t as text
            end try
            try
              set trackArt to \(art)
            end try
            try
              set trackID to \(id) as text
            end try
            try
              set shuffleState to \(shuffle)
            end try
            return {trackTitle, trackArtist, trackAlbum, duration of t, player position, (player state is playing), trackArt, trackID, shuffleState, sound volume}
          end tell
        end timeout
        """
    }
}
