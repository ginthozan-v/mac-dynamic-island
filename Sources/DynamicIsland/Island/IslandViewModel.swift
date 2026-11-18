import SwiftUI

/// Pages of the expanded island, in swipe order. Chosen from the bottom tab bar,
/// the side arrows, or a two-finger swipe.
enum IslandTab: Hashable {
    case music, calendar, timer, shelf

    var icon: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        case .timer: "timer"
        case .shelf: "tray"
        }
    }

    var title: String {
        switch self {
        case .music: "Now Playing"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .shelf: "Shelf"
        }
    }
}

enum HUDKind: Hashable {
    case battery(level: Int, charging: Bool, pluggedIn: Bool)
}

enum CompactContent: Hashable {
    case none
    case hud(HUDKind)
    case screenshot(URL)
    /// Screenshots waiting on the shelf that haven't been looked at yet.
    case shelfPending(URL, Int)
    case timerDone
    case timer
    case nowPlaying
    case event
}

@MainActor
@Observable
final class IslandViewModel {
    var notchSize: CGSize
    var hasNotch: Bool
    var isExpanded = false
    /// Optional so it can drive the pager's scroll position directly.
    var tab: IslandTab? = .music {
        didSet { if isExpanded && tab == .shelf { pendingScreenshots.removeAll() } }
    }
    var hud: HUDKind?
    /// A screenshot just taken; shown in the compact island for a few seconds.
    var screenshot: URL?
    /// Screenshots added to the shelf since it was last opened.
    var pendingScreenshots: [URL] = []
    var isDropTargeted = false {
        didSet { if isDropTargeted { expand(tab: .shelf) } }
    }

    let settings = AppSettings.shared
    let nowPlaying = NowPlayingService()
    let battery = BatteryMonitor()
    let calendar = CalendarService()
    let timer = TimerService()
    let shelf = ShelfStore()
    @ObservationIgnored let screenshots = ScreenshotWatcher()
    @ObservationIgnored private let flyer = ScreenshotFlyer()

    @ObservationIgnored private var hudTask: Task<Void, Never>?
    @ObservationIgnored private var screenshotTask: Task<Void, Never>?
    /// After a screenshot, the next hover opens straight to the Shelf.
    @ObservationIgnored private var focusShelfUntil = Date.distantPast

    init(notchSize: CGSize, hasNotch: Bool) {
        self.notchSize = notchSize
        self.hasNotch = hasNotch

        battery.onEvent = { [weak self] level, charging, plugged in
            guard let self, self.settings.hudBattery else { return }
            self.showHUD(.battery(level: level, charging: charging, pluggedIn: plugged), duration: 2.5)
        }
        if settings.showCalendar { calendar.start() }

        screenshots.onScreenshot = { [weak self] url in self?.handleScreenshot(url) }
        screenshots.start()
    }

    // MARK: State

    var compact: CompactContent {
        if let hud { return .hud(hud) }
        if let screenshot { return .screenshot(screenshot) }
        if timer.justFinished { return .timerDone }
        if timer.isActive { return .timer }
        if settings.showNowPlaying, nowPlaying.hasTrack, nowPlaying.isPlaying { return .nowPlaying }
        if settings.showCalendar, calendar.isImminent { return .event }
        if let pending = pendingScreenshot { return .shelfPending(pending.url, pending.count) }
        return .none
    }

    /// Newest unseen screenshot still on the shelf, and how many there are.
    var pendingScreenshot: (url: URL, count: Int)? {
        let onShelf = pendingScreenshots.filter { url in shelf.items.contains { $0.url == url } }
        guard let last = onShelf.last else { return nil }
        return (last, onShelf.count)
    }

    /// Hide the simulated island on screens without a notch when there is nothing to show.
    var isInvisible: Bool { !hasNotch && !isExpanded && compact == .none }

    /// Constant while expanded, so the expanded content never re-lays out mid-animation.
    var expandedSize: CGSize {
        // notch row (tabs + settings) + gap + page + bottom margin
        CGSize(
            width: max(476, notchSize.width + 292),
            height: notchSize.height + DS.headerGap + DS.pageHeight + DS.bottomMargin
        )
    }

    var islandSize: CGSize {
        let flare = NotchGeometry.flare
        if isExpanded { return expandedSize }
        let ear: CGFloat
        switch compact {
        case .none: ear = 0
        case .hud, .screenshot: ear = 86
        case .shelfPending: ear = 36
        default: ear = 46
        }
        return CGSize(width: notchSize.width + 2 * (ear + flare), height: notchSize.height)
    }

    var pages: [IslandTab] {
        var pages: [IslandTab] = []
        if settings.showNowPlaying { pages.append(.music) }
        if settings.showCalendar { pages.append(.calendar) }
        pages.append(.timer)
        if settings.showShelf { pages.append(.shelf) }
        return pages
    }

    var currentTab: IslandTab { tab.flatMap { pages.contains($0) ? $0 : nil } ?? pages[0] }

    // MARK: Actions

    func expand(tab: IslandTab? = nil) {
        if let tab {
            self.tab = tab
        } else if Date() < focusShelfUntil, pages.contains(.shelf) {
            self.tab = .shelf
        }
        focusShelfUntil = .distantPast
        isExpanded = true
        if currentTab == .shelf { pendingScreenshots.removeAll() }
    }

    func collapse() {
        isExpanded = false
        tab = pages.first
    }

    private func handleScreenshot(_ url: URL) {
        guard settings.catchScreenshots else { return }
        if settings.showShelf {
            shelf.add([url])
            focusShelfUntil = Date().addingTimeInterval(20)
        }
        let screen = NotchGeometry.targetScreen()
        Task { [weak self] in
            if let image = await ScreenshotFlyer.loadImage(url), let self {
                let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
                self.flyer.fly(
                    image: image,
                    from: ScreenshotWatcher.captureRect(of: url),
                    to: self.screenshotLandingRect(aspect: aspect, screenWidth: screen.frame.width),
                    on: screen
                )
                // Open the island a little before touchdown so it's there to catch the screenshot.
                try? await Task.sleep(for: .seconds(ScreenshotFlyer.duration * 0.45))
            }
            self?.showScreenshotFlash(url)
        }
    }

    private func showScreenshotFlash(_ url: URL) {
        screenshot = url
        // Mark it unseen only once it has landed, so the indicator doesn't open early.
        if settings.showShelf, !(isExpanded && currentTab == .shelf) { pendingScreenshots.append(url) }
        screenshotTask?.cancel()
        screenshotTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.screenshot = nil
        }
    }

    /// Where the compact island's screenshot thumbnail sits (screen-local, top-left origin):
    /// the 26pt box in the left ear of the `.screenshot` layout.
    private func screenshotLandingRect(aspect: CGFloat, screenWidth: CGFloat) -> CGRect {
        let ear: CGFloat = 86
        let box: CGFloat = 26
        let size = aspect >= 1 ? CGSize(width: box, height: box / aspect) : CGSize(width: box * aspect, height: box)
        let centerX = screenWidth / 2 - notchSize.width / 2 - ear + 10 + box / 2
        let centerY = notchSize.height / 2
        return CGRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
    }

    func showHUD(_ kind: HUDKind, duration: Double = 1.6) {
        hud = kind
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hud = nil
        }
    }
}
