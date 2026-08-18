import Foundation

/// 系统采样器：持有上次采样状态，计算各指标的使用率/速率。
final class SystemMonitor {
    private var prevCPU: CPUMetrics.Snapshot?
    private var prevPerCore: [CPUMetrics.Snapshot]?
    private var prevNetwork: NetworkMetrics.Counter?
    private var prevProcessTimes: [Int32: UInt64] = [:]
    private var lastSampleDate = Date()
    let info = SystemInfo()

    func sample() -> SystemSample {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleDate)
        lastSampleDate = now

        // MARK: CPU
        let cpuSnap = CPUMetrics.totalSnapshot()
        let perCoreSnap = CPUMetrics.perCoreSnapshots()
        let cpuUsage: Double
        if let prev = prevCPU, let curr = cpuSnap {
            cpuUsage = CPUMetrics.usage(prev: prev, curr: curr)
        } else {
            cpuUsage = 0
        }
        prevCPU = cpuSnap

        let perCoreUsage: [Double]
        if let prev = prevPerCore, let curr = perCoreSnap, prev.count == curr.count {
            perCoreUsage = zip(prev, curr).map { CPUMetrics.usage(prev: $0, curr: $1) }
        } else {
            perCoreUsage = perCoreSnap?.map { _ in 0 } ?? []
        }
        prevPerCore = perCoreSnap

        let load = CPUMetrics.loadAverage()

        // MARK: Memory
        let memory = MemoryMetrics.snapshot()

        // MARK: Disk
        let disk = DiskMetrics.rootSnapshot()

        // MARK: Network
        let network = NetworkMetrics.counter()
        let rate: (down: Double, up: Double)
        if let prev = prevNetwork {
            rate = NetworkMetrics.rate(prev: prev, curr: network, elapsed: elapsed)
        } else {
            rate = (0, 0)
        }
        prevNetwork = network

        // MARK: Battery
        let battery = BatteryMetrics.status()

        // MARK: Processes
        let processSamples = ProcessMetrics.sample()
        let processUsages = processSamples.map { sample in
            ProcessMetrics.Usage(
                pid: sample.pid,
                name: sample.name,
                cpuPercent: ProcessMetrics.cpuPercent(
                    prevTime: prevProcessTimes[sample.pid],
                    currTime: sample.cpuTime,
                    elapsed: elapsed
                ),
                memoryBytes: sample.residentSize
            )
        }
        prevProcessTimes = Dictionary(
            uniqueKeysWithValues: processSamples.map { ($0.pid, $0.cpuTime) }
        )

        let memoryUsedPercent = memory?.usedPercent ?? 0
        let diskUsedPercent = disk?.usedPercent ?? 0
        let score = HealthScore.compute(cpu: cpuUsage, memory: memoryUsedPercent, disk: diskUsedPercent)

        return SystemSample(
            timestamp: now,
            cpuUsage: cpuUsage,
            cpuPerCore: perCoreUsage,
            loadAverage: load,
            memoryUsed: memory?.used ?? 0,
            memoryTotal: memory?.total ?? 0,
            memoryUsedPercent: memoryUsedPercent,
            diskUsed: disk?.used ?? 0,
            diskTotal: disk?.total ?? 0,
            diskAvailable: disk?.available ?? 0,
            diskUsedPercent: diskUsedPercent,
            networkDownBytesPerSec: rate.down,
            networkUpBytesPerSec: rate.up,
            battery: battery,
            processes: processUsages.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(30).map { $0 },
            healthScore: score,
            info: info
        )
    }
}
