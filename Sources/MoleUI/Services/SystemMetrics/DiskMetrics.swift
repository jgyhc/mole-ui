import Foundation

/// 磁盘指标采集（原生 API：FileManager 卷资源属性）。
enum DiskMetrics {
    struct Snapshot {
        var total: Int64
        var used: Int64
        var available: Int64
        var usedPercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    }

    /// 启动卷（根目录）使用情况。
    static func rootSnapshot() -> Snapshot? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        ), let total = values.volumeTotalCapacity else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return Snapshot(
            total: Int64(total),
            used: Int64(total) - available,
            available: available
        )
    }
}
