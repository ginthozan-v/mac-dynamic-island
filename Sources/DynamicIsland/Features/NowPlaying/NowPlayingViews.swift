import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    let color: Color
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 15

    private let speeds: [Double] = [5.1, 7.3, 4.2, 6.4]
    private let phases: [Double] = [0, 1.3, 2.1, 0.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.7) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = abs(sin(t * speeds[i] + phases[i])) * 0.7 + abs(sin(t * speeds[i] * 0.37)) * 0.3
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: isPlaying ? 4 + (maxHeight - 4) * wave : 3)
                }
            }
            .frame(height: maxHeight + 1)
        }
    }
}

// MARK: - Music page

/// Flat, full-width player: cover + date/time + title on top, a wide progress row,
/// and centred transport controls with "open player" and volume at the ends.
struct MusicPage: View {
    let np: NowPlayingService
    @State private var showingVolume = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.hasTrack ? np.title : "Not Playing")
                        .font(DS.rounded(16, .bold))
                        .lineLimit(1)
                    Text(np.hasTrack ? subtitle : "Open Music or Spotify")
                        .font(DS.rounded(12, .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                // Title and artist blur-swap together when the track changes.
                .id(np.hasTrack ? "\(np.title)|\(np.artist)" : "none")
                .transition(.blurReplace)
                .animation(.smooth(duration: 0.45), value: np.title)
                .frame(height: 66)
                Spacer(minLength: 0)
            }

            ProgressRow(np: np)
                .padding(.top, 8)
                .opacity(np.hasTrack ? 1 : 0.3)
                .disabled(!np.hasTrack)

            ZStack {
                if showingVolume {
                    VolumeRow(np: np) { showingVolume = false }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    controls
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(height: 30)
            .padding(.top, 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showingVolume)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var subtitle: String {
        np.album.isEmpty ? np.artist : "\(np.artist) – \(np.album)"
    }

    private var cover: some View {
        let dir = CGFloat(np.skipDirection)
        return ZStack {
            // Directional "card swap": the old cover leaves the way you skipped,
            // the new one slides in from the other side and sharpens into place.
            ArtworkView(image: np.artwork, size: 66, radius: 13)
                .id(np.artworkVersion)
                .transition(.asymmetric(
                    insertion: .modifier(active: CoverSwap(x: 34 * dir, scale: 0.78, blur: 6, opacity: 0),
                                         identity: .identity),
                    removal: .modifier(active: CoverSwap(x: -34 * dir, scale: 0.78, blur: 6, opacity: 0),
                                       identity: .identity)
                ))
        }
        .frame(width: 66, height: 66)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: np.artworkVersion)
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        // Instant feedback on click: nudge toward the skip and settle back once the new cover lands.
        .offset(x: np.isSkipping ? -5 * dir : 0)
        .scaleEffect(np.isSkipping ? 0.9 : (np.isPlaying || !np.hasTrack ? 1 : 0.94))
        .opacity(np.hasTrack ? 1 : 0.5)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: np.isSkipping)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: np.isPlaying)
            .onTapGesture { np.openPlayerApp() }
            .help(np.player.map { "Open \($0.rawValue)" } ?? "")
            .accessibilityElement()
            .accessibilityLabel(np.hasTrack ? "Album art for \(np.title)" : "No track playing")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { np.openPlayerApp() }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            // Opens the source app (Music / Spotify).
            Button { np.openPlayerApp() } label: {
                Group {
                    if let icon = np.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "music.note.list").font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .help(np.player.map { "Open \($0.rawValue)" } ?? "")

            Spacer(minLength: 0)
            HStack(spacing: 30) {
                GlyphButton(icon: "backward.fill", size: 17) { np.previousTrack() }
                    .frame(width: 30, height: 30)
                GlyphButton(icon: np.isPlaying ? "pause.fill" : "play.fill", size: 21) { np.playPause() }
                    .frame(width: 34, height: 32)
                    .contentTransition(.symbolEffect(.replace))
                GlyphButton(icon: "forward.fill", size: 17) { np.nextTrack() }
                    .frame(width: 30, height: 30)
            }
            .disabled(!np.hasTrack)
            .opacity(np.hasTrack ? 1 : 0.35)
            Spacer(minLength: 0)

            GlyphButton(icon: volumeIcon, size: 13) { showingVolume = true }
                .frame(width: 30, height: 30)
                .disabled(!np.hasTrack)
                .opacity(np.hasTrack ? 0.85 : 0.3)
                .help("Player volume")
        }
    }

    private var volumeIcon: String {
        switch np.volume {
        case ..<1: "speaker.slash.fill"
        case ..<34: "speaker.wave.1.fill"
        case ..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Offset + scale + blur + fade, used for the cover swap transition.
struct CoverSwap: ViewModifier {
    var x: CGFloat
    var scale: CGFloat
    var blur: CGFloat
    var opacity: Double

    static let identity = CoverSwap(x: 0, scale: 1, blur: 0, opacity: 1)

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(x: x)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// "01:00 ━━━━━━━──────── -02:55", draggable to seek.
struct ProgressRow: View {
    let np: NowPlayingService
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let current = np.position(at: context.date)
            let fraction = dragFraction ?? (np.duration > 0 ? current / np.duration : 0)
            let shown = dragFraction.map { $0 * np.duration } ?? current
            let active = hovering || dragFraction != nil
            HStack(spacing: 10) {
                Text(format(shown))
                    .frame(width: 42, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                    .frame(height: active ? 6 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragFraction = min(1, max(0, v.location.x / geo.size.width)) }
                            .onEnded { _ in
                                if let f = dragFraction { np.seek(to: f * np.duration) }
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                Text("-" + format(max(0, np.duration - shown)))
                    .frame(width: 48, alignment: .trailing)
            }
            .font(DS.rounded(13, .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .onHover { hovering = $0 }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Inline player-volume slider that temporarily replaces the transport controls.
struct VolumeRow: View {
    let np: NowPlayingService
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: max(6, geo.size.width * np.volume / 100))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in np.setVolume(v.location.x / geo.size.width * 100, commit: false) }
                        .onEnded { v in np.setVolume(v.location.x / geo.size.width * 100, commit: true) }
                )
            }
            .frame(height: 20)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            GlyphButton(icon: "xmark", size: 10, action: onDone)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .padding(.horizontal, 4)
    }
}
