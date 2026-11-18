# Dynamic Island for Mac

A native macOS app that turns the MacBook notch into an iPhone-style **Dynamic Island**: live activities in the compact notch, and a swipeable panel with music controls, a calendar, a timer and a file shelf when you hover over it.

Built with Swift 6, SwiftUI and AppKit. No Xcode project, no third-party dependencies.

---

## Features

### Compact island
The notch quietly widens to show what's happening, then shrinks back:

| Activity | What you see |
| --- | --- |
| **Now Playing** | Album art on the left, a live waveform on the right |
| **Timer** | Progress ring and countdown (dimmed while paused) |
| **Screenshot** | The screenshot flies into the notch, then a draggable thumbnail |
| **Screenshots waiting** | Small thumbnail and count until you open the Shelf |
| **Upcoming event** | Calendar icon and "in 8m" just before a meeting |
| **Battery** | Pop-up on plug / unplug and at 20%, 10% and 5% |

### Expanded panel
Hover over the notch to expand it. Switch pages with the tabs beside the notch or a **two-finger swipe**.

- **Now Playing:** cover art, title, artist and album, a draggable progress bar, back / play-pause / forward, the player's own volume, and a smooth directional cover swap when you skip tracks. Works with **Apple Music** and **Spotify**.
- **Calendar:** the native macOS calendar control, today's date and up to three of today's events (all-day events included).
- **Timer:** presets from 1 minute to 1 hour, a custom duration, pause / resume and +1 minute, with a chime when it's done.
- **Shelf:** drop files on the notch to park them. Drag them out anywhere, double-click to open. Real Quick Look previews, and items persist across launches.

### Screenshot catching
Take a screenshot as usual (⌘⇧3 / ⌘⇧4 / ⌘⇧5). It lifts off from where you captured it, flies into the notch, and lands on the Shelf, ready to drag into Mail, Slack, Finder or anywhere else. Detection uses the screen-capture tag macOS writes on every screenshot, so it's independent of file names and language.

### Design
- A solid black island that blends into the hardware notch, with even margins and corners that match the cards inside.
- **Liquid Glass** (macOS 26+) on the controls (tab bar, settings), following [Apple's guidance](https://developer.apple.com/documentation/technologyoverviews/liquid-glass): glass for controls, not behind content. Respects *Reduce Transparency*.
- Spring animations throughout. The panel never dips below the notch while animating.

---

## Requirements

- A Mac running **macOS 14 Sonoma or later** (Liquid Glass controls need macOS 26)
- A **MacBook with a notch** for the full effect (it falls back to a simulated island on other displays)
- **Xcode** or the Xcode command-line tools with **Swift 6**

## Build and run

```bash
git clone https://github.com/ginthozan-v/mac-dynamic-island.git
cd mac-dynamic-island
make run
```

| Command | What it does |
| --- | --- |
| `make build` | Compiles a release build and assembles `build/DynamicIsland.app` (ad-hoc signed) |
| `make run` | Builds, quits any running copy, and launches the app |
| `make install` | Builds and copies the app to `~/Applications` |
| `make test` | Runs the unit tests (Swift Testing) |
| `make clean` | Removes build output |

The app runs as a menu bar agent (no Dock icon). Use the capsule icon in the menu bar for **About**, **Settings** and **Quit**.

## Permissions

macOS asks for each of these the first time it's needed:

| Permission | Why |
| --- | --- |
| **Automation → Music / Spotify** | Read the current track and control playback (AppleScript) |
| **Calendars** | Show today's events |
| **Desktop folder** (or your screenshot folder) | Notice new screenshots |

> **Tip:** with macOS's floating screenshot thumbnail turned on, the file is only saved once that preview disappears (about 5 seconds). For instant fly-ins, press ⌘⇧5 → **Options** → untick **Show Floating Thumbnail**.

## Settings

Open **Settings…** from the menu bar icon:

- Turn Now Playing, Calendar and the Shelf on or off
- Catch screenshots
- Liquid Glass controls
- Battery alerts
- Launch at login

---

## Performance

Built to sit quietly in the background:

| | Idle | Notes |
| --- | --- | --- |
| **CPU** | ~0% | No periodic work while idle: pointer tracking is event-driven and only polls while the pointer is near the island |
| **Wakeups** | 0 / s | Measured with `top` with the pointer away from the notch |
| **Memory** | ~16–40 MB | Physical footprint, measured with `footprint`: ~16 MB at launch, up to ~40 MB once artwork and shelf thumbnails are loaded (artwork is downscaled to 256 px; the fly-in image is released after the flight) |
| **Leaks** | 0 | Checked with `leaks` |

Now Playing doesn't poll while music is paused; Music and Spotify announce changes themselves. The waveform animates only while a track is playing.

## Accessibility

- Every icon-only control has a VoiceOver label (playback, timer, tabs, shelf items with Open / Remove actions).
- Glass controls fall back to solid ones when **Reduce Transparency** is on.

---

## How it works

| Area | Approach |
| --- | --- |
| Window | A borderless, non-activating `NSPanel` above the menu bar on every Space. It passes clicks through everywhere except the island itself. |
| Notch geometry | Read from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` |
| Hover | Pointer polling plus event monitors, with short intent delays for expand and collapse |
| Now Playing | Music / Spotify distributed notifications plus AppleScript (MediaRemote is entitlement-locked for third-party apps since macOS 15.4) |
| Calendar | EventKit |
| Battery | IOKit power-source notifications |
| Screenshots | A folder watcher plus the `kMDItemIsScreenCapture` / `kMDItemScreenCaptureGlobalRect` extended attributes |
| Thumbnails | QuickLookThumbnailing |

### Project layout

```
Sources/DynamicIsland/
├── App.swift                  # Entry point, menu bar extra, settings scene
├── Island/                    # Panel, notch geometry, view model, views, design system, Liquid Glass
├── Features/
│   ├── NowPlaying/            # Music & Spotify service, player UI
│   ├── Calendar/              # EventKit service, calendar + timer UI
│   ├── HUD/                   # Battery monitor
│   ├── Shelf/                 # File shelf store, UI, Quick Look thumbnails
│   └── Screenshots/           # Screenshot watcher and fly-in animation
├── Settings/                  # Preferences and settings window
└── Debug/Snapshot.swift       # Offscreen renders for development
```

### Development snapshots

Render the island's states to PNGs without a display or screen-recording permission:

```bash
make build
build/DynamicIsland.app/Contents/MacOS/DynamicIsland --snapshot /tmp/island -glassStyle NO
```

`-glassStyle NO` overrides the glass setting for that run only. The offscreen renderer can't draw Liquid Glass, scroll views or native controls.

## Distribution

`make build` produces an **ad-hoc signed** app. That's fine for building and running it yourself, but:

- macOS may ask for permissions again after each rebuild, because the ad-hoc signature changes.
- To share a build with others, sign it with a **Developer ID Application** certificate and **notarize** it with `xcrun notarytool`. Otherwise Gatekeeper will block it on other Macs.

## Known limitations

- Only **Apple Music** and **Spotify** are supported for Now Playing (browser and other players aren't).
- Screenshots copied to the clipboard (⌘⌃⇧4) don't create a file, so they aren't caught.
- macOS's own volume and brightness overlays are left alone.

## License

[MIT](LICENSE)
