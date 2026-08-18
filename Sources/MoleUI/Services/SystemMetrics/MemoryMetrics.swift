import Darwin
import Foundation

/// 内存指标采集（原生 API：host_statistics64 / vm_statistics64）。
enum MemoryMetrics {
    struct Snapshot {
        var total: UInt64
        var free: UInt64
        var active: UInt64
        var inactive: UInt64
        var wired: UInt64
        var compressed: UInt64

        /// 已用内存 ≈ 总量 - 空闲 - 可回收（inactive）
        var used: UInt64 { max(total - free - inactive, 0) }
        var usedPercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    }

    static func snapshot() -> Snapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        return Snapshot(
            total: ProcessInfo.processInfo.physicalMemory,
            free: UInt64(stats.free_count) * pageSize,
            active: UInt64(stats.active_count) * pageSize,
            inactive: UInt64(stats.inactive_count) * pageSize,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize
        )
    }
}
