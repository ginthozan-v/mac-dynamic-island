import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @Bindable var vm: IslandViewModel

    private var spring: Animation { .spring(response: 0.42, dampingFraction: 0.8) }

    var body: some View {
        let size = vm.islandSize
        let shape = NotchShape(
            topRadius: vm.isExpanded ? DS.expandedFlare : NotchGeometry.flare,
            bottomRadius: vm.isExpanded ? DS.islandBottomRadius : 11
        )

        // Solid black in every state: matches (and hides) the hardware notch, and gives content
        // an opaque surface. Liquid Glass lives only on the controls floating above it.
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(vm.isExpanded ? 0.5 : 0), radius: 18, y: 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
        }
        // The spring overshoots when shrinking; never let the island dip below the hardware notch.
        .modifier(ClampedFrame(
            width: size.width, height: size.height,
            minWidth: vm.notchSize.width + 2 * NotchGeometry.flare, minHeight: vm.notchSize.height
        ))
        .opacity(vm.isInvisible ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in vm.shelf.add([url]) }
                }
            }
            return true
        }
        .animation(spring, value: vm.isExpanded)
        .animation(spring, value: vm.compact)
        .animation(spring, value: vm.tab)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isExpanded {
            ExpandedIslandView(vm: vm)
                .transition(.asymmetric(
                    // Reveal content once the shape has made room for it.
                    insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.14))
                        .combined(with: .scale(scale: 0.9, anchor: .top).animation(spring.delay(0.08))),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        } else {
            CompactIslandView(vm: vm)
                .transition(.opacity)
        }
    }
}

// MARK: - Compact

struct CompactIslandView: View {
    let vm: IslandViewModel

    var body: some View {
        let size = vm.islandSize
        let ear = max(0, (size.width - vm.notchSize.width) / 2 - NotchGeometry.flare)

        HStack(spacing: 0) {
            leading
                .frame(width: max(0, ear - 10), alignment: .leading)
                .padding(.leading, 10)
            Spacer(minLength: 0)
            trailing
                .frame(width: max(0, ear - 10), alignment: .trailing)
                .padding(.trailing, 10)
        }
        .padding(.horizontal, NotchGeometry.flare)
        .frame(height: vm.notchSize.height)
        .foregroundStyle(.white)
        .id(vm.compact)
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .overlay(alignment: .bottomTrailing) {
            if showsPendingDot {
                Circle()
                    .fill(Color(red: 0.3, green: 0.6, blue: 1))
                    .frame(width: 5, height: 5)
                    .padding(.trailing, NotchGeometry.flare + 5)
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// A screenshot is waiting on the shelf but something else is using the compact island.
    private var showsPendingDot: Bool {
        guard vm.pendingScreenshot != nil else { return false }
        switch vm.compact {
        case .none, .screenshot, .shelfPending: return false
        default: return true
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch vm.compact {
        case .none:
            EmptyView()
        case .hud(let kind):
            HUDLeading(kind: kind)
        case .shelfPending(let url, _):
            FileThumbnail(url: url, size: 18, cornerRadius: 2)
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .help("Screenshot on the shelf — drag it anywhere")
        case .screenshot(let url):
            // Grab the thumbnail and drop it anywhere.
            FileThumbnail(url: url, size: 26, cornerRadius: 3)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .help("Drag the screenshot anywhere")
        case .timerDone:
            Image(systemName: "bell.fill").foregroundStyle(.orange).symbolEffect(.pulse)
        case .timer:
            TimerRing(timer: vm.timer, lineWidth: 2.5).frame(width: 16, height: 16)
        case .nowPlaying:
            ArtworkView(image: vm.nowPlaying.artwork, size: 22, radius: 6)
        case .event:
            Image(systemName: "calendar")
                .foregroundStyle(vm.calendar.nextEvent?.color ?? .red)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch vm.compact {
        case .none:
            EmptyView()
        case .hud(let kind):
            HUDTrailing(kind: kind)
        case .shelfPending(_, let count):
            HStack(spacing: 2) {
                Image(systemName: "tray.full.fill").font(.system(size: 8, weight: .bold))
                Text("\(count)").font(.system(size: 10, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.7))
        case .screenshot:
            Text("Screenshot")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        case .timerDone:
            Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        case .timer:
            TimerCountdownText(timer: vm.timer)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .opacity(vm.timer.isPaused ? 0.5 : 1)
        case .nowPlaying:
            WaveformView(isPlaying: vm.nowPlaying.isPlaying, color: vm.nowPlaying.accent)
        case .event:
            EventCountdownText(calendar: vm.calendar)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }
}

// MARK: - Expanded

/// Top row: page tabs left of the notch, settings right of it. Below: one swipeable page.
struct ExpandedIslandView: View {
    @Bindable var vm: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                IslandTabBar(vm: vm)
                Spacer(minLength: vm.notchSize.width + 8)
                SettingsButton(vm: vm)
            }
            .padding(.horizontal, DS.expandedFlare + 10)
            .frame(height: vm.notchSize.height)

            IslandPager(vm: vm)
                .frame(height: DS.pageHeight)
                .padding(.top, DS.headerGap)
        }
        .foregroundStyle(.white)
        // Fixed final size: the growing notch shape just reveals it (clipped), no per-frame relayout.
        .frame(width: vm.expandedSize.width, height: vm.expandedSize.height, alignment: .top)
        .glassContainer()
    }
}

/// All pages side by side; two-finger swipe pages between them. Pages span the full
/// island width, so neighbours hide past the island edge and slide in under its clip.
struct IslandPager: View {
    @Bindable var vm: IslandViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(vm.pages, id: \.self) { page in
                        pageView(page)
                            .padding(.horizontal, DS.pageInset)
                            .containerRelativeFrame(.horizontal)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $vm.tab)
            .scrollClipDisabled()
            .onAppear {
                if vm.tab == nil || !vm.pages.contains(vm.tab!) { vm.tab = vm.pages.first }
                // The scroll view is created fresh on every expand and always starts on the first
                // page; it doesn't honour the bound position initially. Jump to the selected page
                // (e.g. Shelf after a screenshot) without animation, now and after first layout.
                let target = vm.currentTab
                jump(proxy, to: target)
                DispatchQueue.main.async { jump(proxy, to: target) }
            }
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to page: IslandTab) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { proxy.scrollTo(page, anchor: .leading) }
    }

    @ViewBuilder
    private func pageView(_ page: IslandTab) -> some View {
        switch page {
        case .music: MusicPage(np: vm.nowPlaying)
        case .calendar: CalendarCard(calendar: vm.calendar)
        case .timer: TimerTabView(timer: vm.timer)
        case .shelf: ShelfView(shelf: vm.shelf, isTargeted: vm.isDropTargeted)
        }
    }
}

/// Page tabs in a single glass capsule, sitting left of the notch.
struct IslandTabBar: View {
    let vm: IslandViewModel
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(vm.pages, id: \.self) { page in
                let selected = vm.currentTab == page
                TabBarItem(icon: page.icon, selected: selected, dot: dot(for: page)) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { vm.tab = page }
                }
                .background {
                    // A plain highlight that slides between icons. Not a second glass layer:
                    // Apple's guidance is to avoid stacking glass on glass.
                    if selected {
                        Capsule()
                            .fill(.white.opacity(0.14))
                            .frame(width: 28, height: 20)
                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                    }
                }
                .help(page.title)
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 26)
        .glassCapsule()
    }

    private func dot(for page: IslandTab) -> Color? {
        switch page {
        case .timer: vm.timer.isActive ? .orange : nil
        case .shelf: vm.shelf.items.isEmpty ? nil : .blue
        default: nil
        }
    }
}

/// Glass settings button, right of the notch.
struct SettingsButton: View {
    let vm: IslandViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var hovering = false

    var body: some View {
        Button {
            vm.collapse()
            NSApp.activate()
            openSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.7))
                .frame(width: 26, height: 26)
                .glassCapsule(interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .help("Settings")
    }
}

struct TabBarItem: View {
    let icon: String
    let selected: Bool
    var dot: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? DS.selectedTint : .white.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 29, height: 24)
                .overlay(alignment: .topTrailing) {
                    if let dot {
                        Circle().fill(dot).frame(width: 5, height: 5).offset(x: -3, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
