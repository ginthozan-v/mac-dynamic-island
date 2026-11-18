import Foundation
import IOKit.ps

/// Watches power source changes; reports plug/unplug and low-battery thresholds.
@MainActor
@Observable
final class BatteryMonitor {
    private(set) var hasBattery = false
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = true

    /// (level, charging, pluggedIn)
    @ObservationIgnored var onEvent: ((Int, Bool, Bool) -> Void)?
    @ObservationIgnored private var source: CFRunLoopSource?

    init() {
        update(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update(notify: true) }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func update(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false

            let pluggedChanged = hasBattery && plugged != isPluggedIn
            let crossedLow = hasBattery && !plugged && [20, 10, 5].contains { newLevel <= $0 && level > $0 }

            hasBattery = true
            level = newLevel
            isPluggedIn = plugged
            isCharging = charging

            if notify && (pluggedChanged || crossedLow) {
                onEvent?(newLevel, charging || plugged, plugged)
            }
            return
        }
    }
}
