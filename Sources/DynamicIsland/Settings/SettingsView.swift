import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    var showNowPlaying: Bool { didSet { defaults.set(showNowPlaying, forKey: "showNowPlaying") } }
    var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: "showCalendar") } }
    var showShelf: Bool { didSet { defaults.set(showShelf, forKey: "showShelf") } }
    var glassStyle: Bool { didSet { defaults.set(glassStyle, forKey: "glassStyle") } }
    var catchScreenshots: Bool { didSet { defaults.set(catchScreenshots, forKey: "catchScreenshots") } }
    var hudBattery: Bool { didSet { defaults.set(hudBattery, forKey: "hudBattery") } }
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login failed: \(error)")
            }
        }
    }

    private init() {
        defaults.register(defaults: [
            "showNowPlaying": true, "showCalendar": true, "showShelf": true, "glassStyle": false, "catchScreenshots": true,
            "hudBattery": true,
        ])
        showNowPlaying = defaults.bool(forKey: "showNowPlaying")
        showCalendar = defaults.bool(forKey: "showCalendar")
        showShelf = defaults.bool(forKey: "showShelf")
        glassStyle = defaults.bool(forKey: "glassStyle")
        catchScreenshots = defaults.bool(forKey: "catchScreenshots")
        hudBattery = defaults.bool(forKey: "hudBattery")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Island") {
                Toggle("Now Playing (Music & Spotify)", isOn: $settings.showNowPlaying)
                Toggle("Calendar", isOn: $settings.showCalendar)
                Toggle("File shelf", isOn: $settings.showShelf)
                Toggle("Catch screenshots", isOn: $settings.catchScreenshots)
                    .help("New screenshots appear in the island and are added to the shelf.")
            }
            Section("Appearance") {
                Toggle("Liquid Glass controls", isOn: $settings.glassStyle)
                    .disabled(!LiquidGlass.isSupported)
                    .help("Tab bar and page arrows use Liquid Glass. The island itself stays black.")
            }
            Section("Alerts") {
                Toggle("Battery & charging", isOn: $settings.hudBattery)
            }
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
        .onAppear { NSApp.activate() }
    }
}
