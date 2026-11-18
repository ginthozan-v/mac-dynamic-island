import SwiftUI

/// Dev aid: `DynamicIsland --snapshot <dir>` renders each island state to PNG and exits.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let vm = IslandViewModel(notchSize: CGSize(width: 185, height: 32), hasNotch: true)

        func render(_ name: String, _ configure: () -> Void) {
            configure()
            let view = IslandView(vm: vm)
                .frame(width: IslandWindowController.panelSize.width, height: IslandWindowController.panelSize.height)
                .background(Color(white: 0.85))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }

        func renderCard(_ name: String, _ make: () -> AnyView) {
            let width = vm.expandedSize.width - 2 * DS.pageInset
            let view = make()
                .frame(width: width, height: DS.pageHeight)
                .padding(20)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
                .foregroundStyle(.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }

        render("1-idle") {}
        render("3-hud-battery") { vm.hud = .battery(level: 84, charging: true, pluggedIn: true) }
        render("4-timer") { vm.hud = nil; vm.timer.start(minutes: 5) }
        render("5-expanded-home") { vm.expand(tab: .music) }
        render("6-expanded-shelf") { vm.tab = .shelf }
        render("6b-timer-tab-running") { vm.tab = .timer }
        render("6c-timer-tab-setup") { vm.timer.cancel() }
        render("7-music-playing") {
            vm.timer.cancel()
            vm.nowPlaying.injectPreview(title: "Midnight Drive", artist: "Neon Coast", artwork: sampleArtwork(), playing: true)
            vm.tab = .music
        }
        render("8-music-paused") {
            vm.nowPlaying.injectPreview(title: "Midnight Drive", artist: "Neon Coast", artwork: sampleArtwork(), playing: false)
        }
        renderCard("10-card-music-playing") {
            vm.nowPlaying.injectPreview(title: "Midnight Drive", artist: "Neon Coast", artwork: sampleArtwork(), playing: true)
            return AnyView(MusicPage(np: vm.nowPlaying))
        }
        renderCard("11-card-timer") {
            vm.timer.cancel()
            return AnyView(TimerTabView(timer: vm.timer))
        }
        renderCard("13-card-shelf-empty") {
            AnyView(ShelfView(shelf: ShelfStore(persistent: false), isTargeted: false))
        }
        renderCard("14-card-shelf-files") {
            let preview = ShelfStore(persistent: false)
            preview.add([
                "/System/Applications/Calendar.app", "/System/Applications/Notes.app",
                "/System/Library/CoreServices/Finder.app", "/etc/hosts", "/usr/share/dict",
            ].map { URL(fileURLWithPath: $0) })
            return AnyView(ShelfView(shelf: preview, isTargeted: false))
        }
        renderCard("12-card-timer-running") {
            vm.timer.start(minutes: 5)
            return AnyView(TimerTabView(timer: vm.timer))
        }
        render("9-music-compact") {
            vm.nowPlaying.injectPreview(title: "Midnight Drive", artist: "Neon Coast", artwork: sampleArtwork(), playing: true)
            vm.collapse()
        }
        exit(0)
    }

    private static func sampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            let gradient = NSGradient(colors: [.systemPink, .systemOrange, .systemPurple])
            gradient?.draw(in: rect, angle: 45)
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 70)).fill()
            return true
        }
    }
}
