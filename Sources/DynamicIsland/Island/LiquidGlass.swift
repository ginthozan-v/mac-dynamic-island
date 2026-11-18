import SwiftUI

/// Liquid Glass, used the way Apple's guidance describes: as a functional layer for
/// controls and navigation (tab bar, page arrows) floating above content, never as the
/// background behind content and never glass-on-glass. The island itself stays solid black,
/// which also hides the hardware notch completely.
enum LiquidGlass {
    static var isSupported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    @MainActor static var isEnabled: Bool { isSupported && AppSettings.shared.glassStyle }
}

/// Glass capsule for a control, falling back to a flat capsule when glass is off,
/// unavailable, or the user has Reduce Transparency on (custom glass isn't adapted automatically).
struct GlassCapsule: ViewModifier {
    var interactive = false
    var tint: Color? = nil
    var fallbackOpacity: Double = 0.07
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26, *), LiquidGlass.isEnabled, !reduceTransparency {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: .capsule)
        } else {
            content.background(
                Capsule()
                    .fill(.white.opacity(reduceTransparency ? max(fallbackOpacity, 0.14) : fallbackOpacity))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
            )
        }
    }
}

extension View {
    func glassCapsule(interactive: Bool = false, tint: Color? = nil, fallbackOpacity: Double = 0.07) -> some View {
        modifier(GlassCapsule(interactive: interactive, tint: tint, fallbackOpacity: fallbackOpacity))
    }

    /// Renders the glass controls inside it together, as Apple recommends for several glass views on screen.
    @ViewBuilder
    func glassContainer(spacing: CGFloat? = nil) -> some View {
        if #available(macOS 26, *), LiquidGlass.isEnabled {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}
