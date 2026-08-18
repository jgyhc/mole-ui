import XCTest
@testable import MoleUI

final class SystemMetricsTests: XCTestCase {
    // MARK: CPU

    func testCPUUsageDelta() {
        let prev = CPUMetrics.Snapshot(user: 100, system: 50, idle: 1000, nice: 0)
        let curr = CPUMetrics.Snapshot(user: 300, system: 150, idle: 1100, nice: 0)
        // delta total = 400, delta idle = 100 → (400-100)/400 = 75%
        XCTAssertEqual(CPUMetrics.usage(prev: prev, curr: curr), 75, accuracy: 0.001)
    }

    func testCPUUsageNoProgress() {
        let prev = CPUMetrics.Snapshot(user: 100, system: 50, idle: 1000, nice: 0)
        XCTAssertEqual(CPUMetrics.usage(prev: prev, curr: prev), 0)
    }

    // MARK: 网络

    func testNetworkRate() {
        let prev = NetworkMetrics.Counter(bytesIn: 1000, bytesOut: 500)
        let curr = NetworkMetrics.Counter(bytesIn: 5000, bytesOut: 1500)
        let rate = NetworkMetrics.rate(prev: prev, curr: curr, elapsed: 2)
        XCTAssertEqual(rate.down, 2000, accuracy: 0.001)
        XCTAssertEqual(rate.up, 500, accuracy: 0.001)
    }

    func testNetworkCounterResetProducesNoNegativeRate() {
        let prev = NetworkMetrics.Counter(bytesIn: 5000, bytesOut: 100)
        let curr = NetworkMetrics.Counter(bytesIn: 100, bytesOut: 50)
        let rate = NetworkMetrics.rate(prev: prev, curr: curr, elapsed: 1)
        XCTAssertEqual(rate.down, 0, accuracy: 0.001)
        XCTAssertEqual(rate.up, 0, accuracy: 0.001)
    }

    // MARK: 进程

    func testProcessCPUPercent() {
        XCTAssertEqual(
            ProcessMetrics.cpuPercent(prevTime: 1_000_000_000, currTime: 2_000_000_000, elapsed: 1),
            100, accuracy: 0.001
        )
        XCTAssertEqual(ProcessMetrics.cpuPercent(prevTime: nil, currTime: 5_000_000_000, elapsed: 1), 0)
        XCTAssertEqual(ProcessMetrics.cpuPercent(prevTime: 100, currTime: 50, elapsed: 1), 0)
    }

    // MARK: 内存

    func testMemorySnapshotMath() {
        let snapshot = MemoryMetrics.Snapshot(
            total: 100, free: 20, active: 40, inactive: 10, wired: 20, compressed: 10
        )
        XCTAssertEqual(snapshot.used, 70)
        XCTAssertEqual(snapshot.usedPercent, 70, accuracy: 0.001)
    }

    // MARK: 健康分

    func testHealthScore() {
        XCTAssertEqual(HealthScore.compute(cpu: 10, memory: 20, disk: 30), 100)
        XCTAssertEqual(HealthScore.compute(cpu: 100, memory: 100, disk: 100), 0)
        // cpuPenalty=(50-20)/80*100=37.5, mem=(60-40)/60*100=33.3, disk=(80-70)/30*100=33.3
        // 100 - 37.5*0.5 - 33.3*0.3 - 33.3*0.2 = 100 - 18.75 - 10 - 6.67 = 64.58 → 65
        XCTAssertEqual(HealthScore.compute(cpu: 50, memory: 60, disk: 80), 65)
    }

    // MARK: 真实硬件采样（冒烟测试：验证原生 API 调用链与数据合理性）

    func testHardwareSamplingSmoke() {
        XCTAssertNotNil(CPUMetrics.totalSnapshot())
        XCTAssertGreaterThan(CPUMetrics.logicalCoreCount(), 0)

        let memory = MemoryMetrics.snapshot()
        XCTAssertNotNil(memory)
        XCTAssertGreaterThan(memory?.total ?? 0, 0)

        let disk = DiskMetrics.rootSnapshot()
        XCTAssertNotNil(disk)
        XCTAssertGreaterThan(disk?.total ?? 0, 0)

        let network = NetworkMetrics.counter()
        XCTAssertGreaterThanOrEqual(network.bytesIn, 0)

        XCTAssertFalse(ProcessMetrics.sample().isEmpty)

        let monitor = SystemMonitor()
        let sample = monitor.sample()
        XCTAssertTrue(sample.cpuUsage >= 0 && sample.cpuUsage <= 100)
        XCTAssertGreaterThan(sample.memoryTotal, 0)
        XCTAssertGreaterThan(sample.diskTotal, 0)
        XCTAssertGreaterThanOrEqual(sample.healthScore, 0)
        XCTAssertLessThanOrEqual(sample.healthScore, 100)
        XCTAssertGreaterThanOrEqual(sample.networkDownBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(sample.networkUpBytesPerSec, 0)
    }

    // MARK: 格式化

    func testUptimeFormatting() {
        XCTAssertEqual(DurationFormatter.uptime(from: 90), "1m")
        XCTAssertEqual(DurationFormatter.uptime(from: 3_600 + 60), "1h 1m")
        XCTAssertEqual(DurationFormatter.uptime(from: 86_400 + 7_200 + 180), "1d 2h 3m")
    }

    func testPercentAndSpeedFormatting() {
        XCTAssertEqual(42.5.percentString, "42.5%")
        // ByteCountFormatter 输出随 locale/取整规则变化，断言结构而非精确字符串
        let speed = 1_250_000.0.speedString
        XCTAssertTrue(speed.hasSuffix("/s"))
        XCTAssertTrue(speed.contains("MB"))
    }
}
