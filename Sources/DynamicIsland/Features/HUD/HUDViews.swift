import SwiftUI

struct HUDLeading: View {
    let kind: HUDKind

    var body: some View {
        switch kind {
        case .battery(let level, let charging, _):
            Image(systemName: charging ? "bolt.fill" : batteryIcon(level))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(charging ? .green : (level <= 20 ? .red : .white))
                .symbolEffect(.bounce, value: charging)
        }
    }
}

func batteryIcon(_ level: Int) -> String {
    switch level {
    case ..<13: "battery.0percent"
    case ..<38: "battery.25percent"
    case ..<63: "battery.50percent"
    case ..<88: "battery.75percent"
    default: "battery.100percent"
    }
}

struct HUDTrailing: View {
    let kind: HUDKind

    var body: some View {
        switch kind {
        case .battery(let level, let charging, let plugged):
            HStack(spacing: 4) {
                if plugged { Text(charging ? "Charging" : "Plugged in").foregroundStyle(.white.opacity(0.6)) }
                Text("\(level)%").foregroundStyle(charging ? .green : (level <= 20 ? .red : .white))
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .lineLimit(1)
        }
    }
}
