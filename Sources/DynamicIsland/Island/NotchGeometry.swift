import AppKit

enum NotchGeometry {
    /// Width of the outward "fillet" drawn at each top corner of the island.
    static let flare: CGFloat = 6

    /// The built-in (notched) display if present, otherwise the main display.
    static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil
    }

    /// Size of the hardware notch, or a simulated one on screens without a notch.
    static func notchSize(for screen: NSScreen) -> CGSize {
        if hasNotch(screen),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return CGSize(width: width, height: screen.safeAreaInsets.top)
        }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return CGSize(width: 190, height: menuBar)
    }
}
