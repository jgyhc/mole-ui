import SwiftUI

/// 内存占用条状图中的一个色段。
struct MemorySegment: Identifiable {
    let id = UUID()
    let name: String
    let pid: Int32
    let memoryBytes: UInt64
    /// 占物理总内存的百分比（0-100）
    let percentOfTotal: Double
    let color: Color
}

// MARK: - 调色板

private let segmentColors: [Color] = [
    .blue, .green, .orange, .purple, .red,
    .teal, .pink, .indigo, .yellow, .mint,
]

/// 内存监控子模块视图模型：基于进程列表与系统内存快照，生成 Top 10 + Other 聚合数据。
@MainActor
final class MemoryMonitorViewModel: ObservableObject {
    @Published var segments: [MemorySegment] = []
    @Published var sortedProcesses: [ProcessMetrics.Usage] = []
    @Published var totalMemory: UInt64 = 0
    @Published var usedMemory: UInt64 = 0
    @Published var freeMemory: UInt64 = 0
    @Published var inactiveMemory: UInt64 = 0

    /// 进程占用的常驻内存总和
    var totalProcessMemory: UInt64 {
        sortedProcesses.reduce(0) { $0 + $1.memoryBytes }
    }

    /// 系统占用 / 内核占用（总量 - 空闲 - 可回收 - 进程常驻）
    var systemMemory: UInt64 {
        let sys = Int64(totalMemory) - Int64(freeMemory) - Int64(inactiveMemory) - Int64(totalProcessMemory)
        return UInt64(max(sys, 0))
    }

    // MARK: - 刷新

    /// 传入最新的进程列表与系统内存快照，重新计算所有分段的占比。
    func refresh(processes: [ProcessMetrics.Usage], snapshot: MemoryMetrics.Snapshot?) {
        totalMemory = snapshot?.total ?? ProcessInfo.processInfo.physicalMemory
        usedMemory = snapshot?.used ?? 0
        freeMemory = snapshot?.free ?? 0
        inactiveMemory = snapshot?.inactive ?? 0

        // 按常驻内存降序，取 Top 10
        let sorted = processes.sorted { $0.memoryBytes > $1.memoryBytes }
        sortedProcesses = sorted
        let top10 = Array(sorted.prefix(10))
        let otherSum = sorted.dropFirst(10).reduce(UInt64(0)) { $0 + $1.memoryBytes }

        var segs: [MemorySegment] = []

        for (i, proc) in top10.enumerated() where proc.memoryBytes > 0 {
            segs.append(MemorySegment(
                name: proc.name,
                pid: proc.pid,
                memoryBytes: proc.memoryBytes,
                percentOfTotal: totalMemory > 0 ? Double(proc.memoryBytes) / Double(totalMemory) * 100 : 0,
                color: segmentColors[i % segmentColors.count]
            ))
        }

        if otherSum > 0 {
            segs.append(MemorySegment(
                name: "其他进程",
                pid: -1,
                memoryBytes: otherSum,
                percentOfTotal: totalMemory > 0 ? Double(otherSum) / Double(totalMemory) * 100 : 0,
                color: .gray.opacity(0.5)
            ))
        }

        segments = segs
    }
}