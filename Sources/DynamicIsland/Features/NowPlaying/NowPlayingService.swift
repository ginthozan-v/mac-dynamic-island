import AppKit
import CoreImage
import ImageIO
import SwiftUI

/// Tracks Music and Spotify playback via their distributed notifications + AppleScript.
/// (MediaRemote is entitlement-locked for third-party apps since macOS 15.4.)
@MainActor
@Observable
final class NowPlayingService {
    enum Player: String, Sendable {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    }

    struct TrackInfo: Sendable {
        var isPlaying: Bool
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var position: Double
        var artworkURL: String?
        var volume: Double?
    }

    private(set) var player: Player?
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var position: TimeInterval = 0
    private(set) var positionDate = Date()
    private(set) var artwork: NSImage?
    /// Blurred, saturated artwork for the card backdrop (computed once per track).
    private(set) var backdrop: NSImage?
    private(set) var accent: Color = .white
    private(set) var appIcon: NSImage?
    /// Bumps each time the cover image changes, so the view can animate the swap.
    private(set) var artworkVersion = 0
    /// +1 for next, -1 for previous: which way the cover swap should travel.
    private(set) var skipDirection = 1
    /// True from a skip click until the new cover arrives (or a short timeout).
    private(set) var isSkipping = false
    /// The player's own volume (0–100), not the system volume.
    private(set) var volume: Double = 50

    @ObservationIgnored private var trackKey = ""
    @ObservationIgnored private var volumeSetAt = Date.distantPast
    @ObservationIgnored private var skipTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var lastNotified: Player?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?

    var hasTrack: Bool { player != nil && !title.isEmpty }

    func position(at date: Date) -> TimeInterval {
        let p = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return duration > 0 ? min(max(0, p), duration) : max(0, p)
    }

    init() {
        let dnc = DistributedNotificationCenter.default()
        let names: [(String, Player)] = [
            ("com.apple.Music.playerInfo", .music),
            ("com.spotify.client.PlaybackStateChanged", .spotify),
        ]
        for (name, source) in names {
            observers.append(dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.lastNotified = source
                    self?.refresh()
                }
            })
        }
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    // MARK: Controls

    func playPause() {
        isPlaying.toggle()
        positionDate = Date()
        send("playpause")
    }

    func nextTrack() {
        beginSkip(direction: 1)
        send("next track")
    }

    func openPlayerApp() {
        guard let player else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).first?.activate()
    }

    /// Snapshot/dev only: show a fake track without a running player.
    func injectPreview(title: String, artist: String, artwork: NSImage?, playing: Bool) {
        player = .music
        self.title = title
        self.artist = artist
        isPlaying = playing
        duration = 214
        position = 83
        positionDate = Date()
        setArtwork(artwork)
        appIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Player.music.bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    func previousTrack() {
        beginSkip(direction: -1)
        send("previous track")
    }

    private func beginSkip(direction: Int) {
        skipDirection = direction
        isSkipping = true
        skipTask?.cancel()
        skipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.isSkipping = false
        }
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        backdrop = image?.blurredBackdrop()
        accent = image?.vibrantAverageColor ?? .white
        artworkVersion += 1
        isSkipping = false
        skipTask?.cancel()
    }

    /// Updates the slider immediately; only sends to the player when `commit` is true (drag end).
    func setVolume(_ value: Double, commit: Bool) {
        volume = min(100, max(0, value))
        volumeSetAt = Date()
        if commit { send("set sound volume to \(Int(volume.rounded()))") }
    }

    func seek(to seconds: TimeInterval) {
        position = seconds
        positionDate = Date()
        send("set player position to \(String(format: "%.2f", seconds))")
    }

    private func send(_ command: String) {
        guard let player else { return }
        Task {
            _ = await ScriptRunner.shared.run("tell application \"\(player.rawValue)\" to \(command)")
            try? await Task.sleep(for: .milliseconds(250))
            refresh()
        }
    }

    // MARK: Refresh

    func refresh() {
        if isRefreshing { needsRefresh = true; return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = [Player.music, .spotify].filter { running.contains($0.bundleID) }
        guard !candidates.isEmpty else { clear(); return }

        isRefreshing = true
        Task {
            var results: [(Player, TrackInfo)] = []
            for candidate in candidates {
                if let info = await Self.fetch(candidate) { results.append((candidate, info)) }
            }
            apply(results)
            isRefreshing = false
            if needsRefresh { needsRefresh = false; refresh() }
        }
    }

    private func apply(_ results: [(Player, TrackInfo)]) {
        let chosen = results.first { $0.1.isPlaying }
            ?? results.first { $0.0 == lastNotified }
            ?? results.first { $0.0 == player }
            ?? results.first
        guard let (source, info) = chosen else { clear(); return }

        // Only write what changed: every @Observable write re-renders the views reading it,
        // and the periodic poll would otherwise invalidate the island every few seconds.
        let key = "\(source.rawValue)|\(info.title)|\(info.artist)|\(info.album)"
        if player != source {
            player = source
            appIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        if title != info.title { title = info.title }
        if artist != info.artist { artist = info.artist }
        if album != info.album { album = info.album }
        if duration != info.duration { duration = info.duration }
        let stateChanged = isPlaying != info.isPlaying || key != trackKey
        if isPlaying != info.isPlaying { isPlaying = info.isPlaying }
        // Don't fight the slider right after the user moved it.
        if let v = info.volume, abs(v - volume) > 0.5, Date().timeIntervalSince(volumeSetAt) > 2 { volume = v }
        // Re-sync the interpolated position only on state change or noticeable drift (e.g. a seek).
        if stateChanged || abs(position(at: Date()) - info.position) > 1.5 {
            position = info.position
            positionDate = Date()
        }

        if key != trackKey {
            // A track change we didn't trigger (song ended, changed in the app) swaps forward.
            if !isSkipping { skipDirection = 1 }
            trackKey = key
            loadArtwork(for: source, info: info, key: key)
        }
    }

    private func clear() {
        player = nil
        title = ""; artist = ""; album = ""
        isPlaying = false
        duration = 0; position = 0
        if artwork != nil { setArtwork(nil) }
        appIcon = nil
        accent = .white
        trackKey = ""
    }

    private func loadArtwork(for source: Player, info: TrackInfo, key: String) {
        Task {
            var data: Data?
            switch source {
            case .music:
                data = await ScriptRunner.shared.run("""
                tell application "Music"
                    try
                        return data of artwork 1 of current track
                    end try
                end tell
                """)?.data
            case .spotify:
                if let s = info.artworkURL, let url = URL(string: s) {
                    data = try? await URLSession.shared.data(from: url).0
                }
            }
            guard key == trackKey else { return }
            // Music hands back artwork up to ~3000px; shrink once so animations stay cheap.
            let image = data.flatMap { NSImage.thumbnail(from: $0, maxPixelSize: 256) }
            setArtwork(image)
        }
    }

    // MARK: AppleScript

    private nonisolated static let musicScript = """
    tell application "Music"
        try
            if player state is stopped then return "STOPPED"
            set t to current track
            return (player state as text) & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & ((duration of t) as text) & "||" & ((player position) as text) & "||" & "" & "||" & ((sound volume) as text)
        on error
            return "STOPPED"
        end try
    end tell
    """

    private nonisolated static let spotifyScript = """
    tell application "Spotify"
        try
            if player state is stopped then return "STOPPED"
            set t to current track
            return (player state as text) & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & (((duration of t) / 1000) as text) & "||" & ((player position) as text) & "||" & (artwork url of t) & "||" & ((sound volume) as text)
        on error
            return "STOPPED"
        end try
    end tell
    """

    private nonisolated static func fetch(_ player: Player) async -> TrackInfo? {
        let script = player == .music ? musicScript : spotifyScript
        guard let output = await ScriptRunner.shared.run(script)?.string, output != "STOPPED" else { return nil }
        let parts = output.components(separatedBy: "||")
        guard parts.count >= 6, !parts[1].isEmpty else { return nil }
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return TrackInfo(
            isPlaying: parts[0] == "playing",
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: number(parts[4]),
            position: number(parts[5]),
            artworkURL: parts.count > 6 && !parts[6].isEmpty ? parts[6] : nil,
            volume: parts.count > 7 ? Double(parts[7].replacingOccurrences(of: ",", with: ".")) : nil
        )
    }
}

private let sharedCIContext = CIContext()

extension NSImage {
    /// Heavily blurred, slightly saturated copy for use as a backdrop.
    func blurredBackdrop() -> NSImage? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let extent = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let output = CIImage(cgImage: cg)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 22)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: -0.05])
            .cropped(to: extent)
        guard let result = sharedCIContext.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: result, size: size)
    }

    static func thumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return NSImage(data: data) }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
    }

    /// Average color of the image, pushed toward a bright, saturated tint for accents.
    var vibrantAverageColor: Color? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let ok = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(1, s * 1.3)), brightness: Double(max(0.75, b)))
    }
}
