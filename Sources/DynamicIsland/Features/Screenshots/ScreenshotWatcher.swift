import Foundation

/// Watches the screenshot save folder and reports new screenshots.
///
/// A file counts as a screenshot when it carries the `kMDItemIsScreenCapture` extended
/// attribute that macOS writes on every capture, so detection doesn't depend on file names
/// (which are localized) or on Spotlight indexing.
@MainActor
final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?

    private let folder: URL
    private var source: DispatchSourceFileSystemObject?
    private var seen: Set<String> = []
    private var rescanTask: Task<Void, Never>?

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf"]

    init() {
        folder = Self.screenshotFolder()
    }

    func start() {
        guard source == nil else { return }
        seen = Set(currentFiles().map(\.path))
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Screenshot watcher: cannot open \(folder.path)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scan() {
        let now = Date()
        var waitingForTag = false
        for url in currentFiles() where !seen.contains(url.path) {
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else {
                seen.insert(url.path)
                continue
            }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            if Self.isScreenCapture(url) {
                seen.insert(url.path)
                // Only fresh captures (the floating thumbnail can delay the save by a few seconds).
                if now.timeIntervalSince(created) < 60 { onScreenshot?(url) }
            } else if now.timeIntervalSince(created) < 5 {
                // The tag can land a moment after the file appears; look again shortly.
                waitingForTag = true
            } else {
                seen.insert(url.path)
            }
        }
        if waitingForTag {
            rescanTask?.cancel()
            rescanTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.scan()
            }
        }
    }

    private func currentFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private nonisolated static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    /// The region that was captured, in global top-left-origin points, from the
    /// `kMDItemScreenCaptureGlobalRect` attribute macOS writes as `[x, y, width, height]`.
    nonisolated static func captureRect(of url: URL) -> CGRect? {
        let name = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, 0) }
        guard read == size,
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [NSNumber],
              values.count == 4 else { return nil }
        let r = values.map { CGFloat($0.doubleValue) }
        return CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
    }

    /// The folder set in Screenshot › Options › Save to, defaulting to the Desktop.
    static func screenshotFolder() -> URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}
