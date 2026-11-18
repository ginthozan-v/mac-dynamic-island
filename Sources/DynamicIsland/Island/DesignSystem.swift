import SwiftUI

/// Visual language for the expanded island: solid black base, raised grey cards,
/// recessed dark "wells" for controls, and a glossy slate-blue pill for the active tab.
enum DS {
    static let cardRadius: CGFloat = 26
    /// Even margin between the island's visible edge and the cards (sides and bottom).
    static let gutter: CGFloat = 14
    /// Outward top fillet of the expanded island; the visible edge starts this far in.
    static let expandedFlare: CGFloat = 14
    /// Island bottom corners concentric with the cards inside them.
    static var islandBottomRadius: CGFloat { cardRadius + gutter }
    /// Height of one page (the native calendar is drawn at 0.86× to fit).
    static let pageHeight: CGFloat = 128
    static let headerGap: CGFloat = 8
    static let bottomMargin: CGFloat = 14
    /// Horizontal inset from the island frame to page content.
    static var pageInset: CGFloat { expandedFlare + gutter + 6 }
    static let selectedTint = Color(red: 1, green: 0.27, blue: 0.36)
    static let wellRadius: CGFloat = 20

    static let chip = Color(white: 0.15)
    static let chipHover = Color(white: 0.21)
    static let secondaryText = Color.white.opacity(0.55)


    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Buttons

/// Plain icon button (transport controls, timer and shelf actions).
struct GlyphButton: View {
    let icon: String
    var size: CGFloat = 15
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
