import Foundation
import IOKit.ps

/// 电池指标采集（原生 API：IOKit Power Sources）。
enum BatteryMetrics {
    struct Status {
        /// 电量 0...1
        var level: Double
        var isCharging: Bool
        var isPresent: Bool
        /// 是否插着电源
        var isPlugged: Bool
    }

    static func status() -> Status {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, first)?
                .takeUnretainedValue() as? [String: Any]
        else {
            return Status(level: 0, isCharging: false, isPresent: false, isPlugged: true)
        }
        let current = (description[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let max = (description[kIOPSMaxCapacityKey] as? Int) ?? 1
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let state = description[kIOPSPowerSourceStateKey] as? String
        let isPlugged = state == kIOPSACPowerValue || isCharging
        return Status(
            level: max > 0 ? Double(current) / Double(max) : 0,
            isCharging: isCharging,
            isPresent: true,
            isPlugged: isPlugged
        )
    }
}
