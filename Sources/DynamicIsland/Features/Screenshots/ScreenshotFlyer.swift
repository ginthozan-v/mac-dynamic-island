import AppKit
import ImageIO
import SwiftUI

/// Plays the "screenshot flies into the notch" animation in a transparent, click-through
/// overlay covering the notched screen, then removes itself.
@MainActor
final class ScreenshotFlyer {
    private var panel: NSPanel?

    static let duration: Double = 0.8

    /// - Parameters:
    ///   - from: start rect in global top-left-origin points (the captured region).
    ///   - to: landing rect, local to `screen` (top-left origin).
    func fly(image: CGImage, from globalRect: CGRect?, to target: CGRect, on screen: NSScreen) {
        panel?.orderOut(nil)

        let start = Self.localStartRect(globalRect, on: screen, imageAspect: CGFloat(image.width) / CGFloat(image.height))
        let overlay = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4) // just above the island
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: FlightView(image: image, from: start, to: target))
        host.sizingOptions = []
        overlay.contentView = host
        overlay.setFrame(screen.frame, display: true)
        overlay.orderFrontRegardless()
        panel = overlay

        Task { [weak self, weak overlay] in
            try? await Task.sleep(for: .seconds(Self.duration + 0.05))
            overlay?.orderOut(nil)
            if self?.panel === overlay { self?.panel = nil }
        }
    }

    /// Converts the captured region to screen-local coordinates; if it's missing or on another
    /// display, starts from a centred card instead.
    private static func localStartRect(_ global: CGRect?, on screen: NSScreen, imageAspect: CGFloat) -> CGRect {
        let size = screen.frame.size
        if let global,
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value)) // global, top-left origin
            if bounds.intersects(global) {
                return global.intersection(bounds).offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            }
        }
        let width = size.width * 0.32
        let height = width / max(imageAspect, 0.1)
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// A downscaled copy of the screenshot for the flight (decoded off the main thread).
    nonisolated static func loadImage(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1400,
            ] as CFDictionary)
        }.value
    }
}

/// The flight itself: a quick lift, then a curved, shrinking glide into the notch that
/// fades out just as it lands on the island's thumbnail.
private struct FlightView: View {
    let image: CGImage
    let from: CGRect
    let to: CGRect
    @State private var started = false

    private struct Values {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var scale: CGFloat = 1
        var radius: CGFloat = 10
        var shadow: CGFloat = 18
        var opacity: Double = 1
    }

    var body: some View {
        let initial = Values(x: from.midX, y: from.midY, width: from.width, height: from.height)
        KeyframeAnimator(initialValue: initial, trigger: started) { v in
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: v.width, height: v.height)
                .clipShape(RoundedRectangle(cornerRadius: v.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: v.radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: v.shadow, y: v.shadow / 3)
                .scaleEffect(v.scale)
                .opacity(v.opacity)
                .position(x: v.x, y: v.y)
        } keyframes: { _ in
            let lift = 0.14
            let glide = ScreenshotFlyer.duration - lift
            // Horizontal settles early and vertical accelerates late: together they trace an arc
            // that swoops up into the notch.
            KeyframeTrack(\.x) {
                LinearKeyframe(from.midX, duration: lift)
                SpringKeyframe(to.midX, duration: glide, spring: .smooth(duration: glide * 0.8))
            }
            KeyframeTrack(\.y) {
                LinearKeyframe(from.midY, duration: lift)
                CubicKeyframe(to.midY, duration: glide)
            }
            KeyframeTrack(\.width) {
                LinearKeyframe(from.width, duration: lift)
                SpringKeyframe(to.width, duration: glide, spring: .smooth(duration: glide * 0.75))
            }
            KeyframeTrack(\.height) {
                LinearKeyframe(from.height, duration: lift)
                SpringKeyframe(to.height, duration: glide, spring: .smooth(duration: glide * 0.75))
            }
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.04, duration: lift, spring: .snappy)
                SpringKeyframe(1, duration: glide)
            }
            KeyframeTrack(\.radius) {
                LinearKeyframe(12, duration: lift)
                LinearKeyframe(3, duration: glide)
            }
            KeyframeTrack(\.shadow) {
                LinearKeyframe(26, duration: lift)
                LinearKeyframe(2, duration: glide)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: lift + glide * 0.8)
                LinearKeyframe(0, duration: glide * 0.2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { started = true }
    }
}
