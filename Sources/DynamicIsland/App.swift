import SwiftUI

@main
struct DynamicIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Dynamic Island", systemImage: "capsule.inset.filled") {
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Dynamic Island") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings {
            SettingsView(settings: AppSettings.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Snapshot.runIfRequested()
        controller = IslandWindowController()
        controller?.show()
    }
}
