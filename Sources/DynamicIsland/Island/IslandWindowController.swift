import AppKit
import SwiftUI

/// Owns the panel, keeps it pinned over the notch, and turns pointer movement
/// into hover-expand / collapse while letting clicks pass through elsewhere.
@MainActor
final class IslandWindowController {
    static let panelSize = CGSize(width: 760, height: 300)

    let viewModel: IslandViewModel
    private let panel = IslandPanel()
    private var pollTimer: Timer?
    private var monitors: [Any] = []
    private var expandTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    private var wasPressed = false
    private var dragChangeCountAtPress = 0
    private var pressBeganInside = false

    init() {
        let screen = NotchGeometry.targetScreen()
        viewModel = IslandViewModel(
            notchSize: NotchGeometry.notchSize(for: screen),
            hasNotch: NotchGeometry.hasNotch(screen)
        )
        let host = IslandHostingView(rootView: IslandView(vm: viewModel))
        host.sizingOptions = []
        panel.contentView = host

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()

        // Poll for responsiveness during drags (no mouseMoved events then), plus monitors for snappy hover.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) { monitors.append(l) }
    }

    private func reposition() {
        let screen = NotchGeometry.targetScreen()
        viewModel.notchSize = NotchGeometry.notchSize(for: screen)
        viewModel.hasNotch = NotchGeometry.hasNotch(screen)
        let size = Self.panelSize
        let frame = NSRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height,
            width: size.width, height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    /// The area (in screen coordinates) where the pointer counts as "on the island".
    private func hotRect() -> NSRect {
        let size = viewModel.islandSize
        var rect = NSRect(
            x: panel.frame.midX - size.width / 2,
            y: panel.frame.maxY - size.height,
            width: size.width, height: size.height
        )
        if viewModel.isExpanded {
            rect = rect.insetBy(dx: -12, dy: -12)
        } else {
            rect = rect.insetBy(dx: -6, dy: 0)
            rect.size.height += 4 // pointer pinned to the very top edge
        }
        return rect
    }

    private func updatePointer() {
        let point = NSEvent.mouseLocation
        let inside = hotRect().contains(point)
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let dragPasteboard = NSPasteboard(name: .drag)

        if pressed && !wasPressed {
            dragChangeCountAtPress = dragPasteboard.changeCount
            pressBeganInside = inside
        }
        wasPressed = pressed

        panel.ignoresMouseEvents = !inside

        if inside {
            collapseTask?.cancel(); collapseTask = nil
            guard !viewModel.isExpanded else { return }
            if pressed {
                // Only react to a fresh file drag coming in from elsewhere.
                let isFileDrag = dragPasteboard.changeCount != dragChangeCountAtPress
                    && (dragPasteboard.types?.contains(.fileURL) ?? false)
                if isFileDrag && !pressBeganInside && viewModel.settings.showShelf {
                    viewModel.expand(tab: .shelf)
                }
            } else if expandTask == nil {
                expandTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(110))
                    guard let self, !Task.isCancelled else { return }
                    self.expandTask = nil
                    if self.hotRect().contains(NSEvent.mouseLocation) { self.viewModel.expand() }
                }
            }
        } else {
            expandTask?.cancel(); expandTask = nil
            // Never collapse mid-gesture (e.g. while dragging a file out of the shelf).
            guard viewModel.isExpanded, !pressed, collapseTask == nil else { return }
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(320))
                guard let self, !Task.isCancelled else { return }
                self.collapseTask = nil
                if !self.hotRect().contains(NSEvent.mouseLocation) && NSEvent.pressedMouseButtons & 1 == 0 {
                    self.viewModel.collapse()
                }
            }
        }
    }
}
