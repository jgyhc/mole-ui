import Foundation

/// 图表历史数据点（单序列）。
struct HistoryPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

/// 图表历史数据点（网络上下行双序列）。
struct NetworkPoint: Identifiable {
    let id = UUID()
    let time: Date
    let down: Double
    let up: Double
}

/// 静态系统信息（启动时采集一次）。
struct SystemInfo {
    let chip: String
    let memory: UInt64
    let osVersion: String
    let uptime: TimeInterval
    let hostName: String

    init() {
        chip = CPUMetrics.chipName() ?? "未知芯片"
        memory = ProcessInfo.processInfo.physicalMemory
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        uptime = ProcessInfo.processInfo.systemUptime
        hostName = Host.current().localizedName ?? "未知主机"
    }
}

/// 一次采样的完整快照。
struct SystemSample {
    let timestamp: Date
    let cpuUsage: Double
    let cpuPerCore: [Double]
    let loadAverage: (Double, Double, Double)
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let memoryUsedPercent: Double
    let diskUsed: Int64
    let diskTotal: Int64
    let diskAvailable: Int64
    let diskUsedPercent: Double
    let networkDownBytesPerSec: Double
    let networkUpBytesPerSec: Double
    let battery: BatteryMetrics.Status
    let processes: [ProcessMetrics.Usage]
    let healthScore: Int
    let info: SystemInfo
}

/// 健康分：0-100。各指标超过健康阈值后按归一化压力加权扣分（启发式）：
/// CPU 权重 50%（>20% 起扣）、内存 30%（>40% 起扣）、磁盘 20%（>70% 起扣）。
enum HealthScore {
    static func compute(cpu: Double, memory: Double, disk: Double) -> Int {
        let cpuPenalty = normalizedPressure(cpu, low: 20, high: 100)   // 0...100
        let memoryPenalty = normalizedPressure(memory, low: 40, high: 100)
        let diskPenalty = normalizedPressure(disk, low: 70, high: 100)
        let score = 100 - cpuPenalty * 0.5 - memoryPenalty * 0.3 - diskPenalty * 0.2
        return Int(min(max(score, 0), 100).rounded())
    }

    /// 将 [low, high] 区间的占用率映射为 0...100 的压力值。
    private static func normalizedPressure(_ value: Double, low: Double, high: Double) -> Double {
        guard value > low else { return 0 }
        guard high > low else { return 100 }
        return min(max((value - low) / (high - low) * 100, 0), 100)
    }
}
