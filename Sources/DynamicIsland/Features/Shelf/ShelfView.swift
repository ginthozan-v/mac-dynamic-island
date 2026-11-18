import AppKit
import SwiftUI

/// Shelf page laid out like the music and timer pages: tile + title/subtitle on top,
/// then a single row of files where the progress row and controls would be.
struct ShelfView: View {
    let shelf: ShelfStore
    let isTargeted: Bool

    /// Fits the page width without a nested scroll view (which would fight page swipes).
    private let maxVisible = 7

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ShelfTile(items: shelf.items, isTargeted: isTargeted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.rounded(16, .bold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(DS.rounded(12, .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(height: 66)
                Spacer(minLength: 0)
                if !shelf.items.isEmpty {
                    GlyphButton(icon: "trash", size: 13) {
                        withAnimation(.smooth(duration: 0.3)) { shelf.clear() }
                    }
                    .frame(width: 30, height: 30)
                    .opacity(0.8)
                    .help("Clear shelf")
                }
            }

            fileRow
                .frame(height: 52)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.3), value: shelf.items.count)
        .animation(.smooth(duration: 0.2), value: isTargeted)
    }

    private var title: String {
        if isTargeted { return "Release to add" }
        let n = shelf.items.count
        return n == 0 ? "Shelf" : "\(n) item\(n == 1 ? "" : "s")"
    }

    private var subtitle: String {
        shelf.items.isEmpty
            ? "Drop files on the notch to keep them here"
            : "Drag out to use · double-click to open"
    }

    @ViewBuilder
    private var fileRow: some View {
        let items = shelf.items
        if items.isEmpty {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.white.opacity(isTargeted ? 0.55 : 0.15))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(isTargeted ? 0.08 : 0))
                )
                .overlay(
                    Label("Drop here", systemImage: "arrow.down.doc")
                        .font(DS.rounded(12, .medium))
                        .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.4))
                )
        } else {
            let overflow = items.count > maxVisible
            let shown = overflow ? Array(items.suffix(maxVisible - 1)) : items
            HStack(spacing: 6) {
                ForEach(shown) { item in
                    ShelfItemView(item: item) {
                        withAnimation(.smooth(duration: 0.3)) { shelf.remove(item) }
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if overflow {
                    let hidden = items.prefix(items.count - shown.count)
                    Text("+\(hidden.count)")
                        .font(DS.rounded(13, .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 52, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
                        .help(hidden.map(\.url.lastPathComponent).joined(separator: "\n"))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Stand-in for the album cover: the newest files fanned out, or a tray when empty.
struct ShelfTile: View {
    let items: [ShelfStore.Item]
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(.white.opacity(isTargeted ? 0.14 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
            .overlay {
                if items.isEmpty || isTargeted {
                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.7))
                        .symbolEffect(.bounce, value: isTargeted)
                } else {
                    let recent = Array(items.suffix(3))
                    ZStack {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                            let spread = Double(index - (recent.count - 1))
                            FileThumbnail(url: item.url, size: 38, cornerRadius: 4)
                                .rotationEffect(.degrees(spread * -9))
                                .offset(x: spread * -5)
                                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        }
                    }
                }
            }
            .frame(width: 66, height: 66)
    }
}

struct ShelfItemView: View {
    let item: ShelfStore.Item
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            FileThumbnail(url: item.url, size: 30, cornerRadius: 4)
            Text(item.url.lastPathComponent)
                .font(DS.rounded(9, .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 52, height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white, Color(white: 0.35))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
                .help("Remove from shelf")
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.url.path)
    }
}
