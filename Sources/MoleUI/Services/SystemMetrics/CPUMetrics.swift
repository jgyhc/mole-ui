import Darwin

/// CPU 指标采集（原生 API：host_statistics / host_processor_info / sysctl / getloadavg）。
enum CPUMetrics {
    /// 某时刻的 CPU 状态（ticks 累计值）。
    struct Snapshot {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64
        var total: UInt64 { user + system + idle + nice }
    }

    /// 全核合计状态。
    static func totalSnapshot() -> Snapshot? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Snapshot(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// 每核状态。
    static func perCoreSnapshots() -> [Snapshot]? {
        var processorInfo: processor_info_array_t?
        var numProcessors: natural_t = 0
        var numInfo: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numProcessors,
            &processorInfo,
            &numInfo
        )
        guard result == KERN_SUCCESS, let info = processorInfo else { return nil }
        defer {
            let size = vm_size_t(MemoryLayout<integer_t>.size) * vm_size_t(numInfo)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: UnsafeRawPointer(info))), size)
        }
        let stride = MemoryLayout<processor_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        return (0..<Int(numProcessors)).map { i in
            let p = info.advanced(by: i * stride)
            let loadInfo = UnsafeRawPointer(p).assumingMemoryBound(to: processor_cpu_load_info.self).pointee
            return Snapshot(
                user: UInt64(loadInfo.cpu_ticks.0),
                system: UInt64(loadInfo.cpu_ticks.1),
                idle: UInt64(loadInfo.cpu_ticks.2),
                nice: UInt64(loadInfo.cpu_ticks.3)
            )
        }
    }

    /// 两个时刻快照之间的使用率（0-100%）。
    static func usage(prev: Snapshot, curr: Snapshot) -> Double {
        let deltaTotal = Double(curr.total - prev.total)
        guard deltaTotal > 0 else { return 0 }
        let deltaIdle = Double(curr.idle - prev.idle)
        return min(max((deltaTotal - deltaIdle) / deltaTotal * 100, 0), 100)
    }

    /// 1/5/15 分钟负载均值。
    static func loadAverage() -> (Double, Double, Double) {
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        return (load[0], load[1], load[2])
    }

    /// 芯片名称，如 "Apple M4 Pro"。
    static func chipName() -> String? {
        var name = [CChar](repeating: 0, count: 256)
        var size = name.count
        guard sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0) == 0 else { return nil }
        let string = String(cString: name)
        return string.isEmpty ? nil : string
    }

    /// 逻辑核心数。
    static func logicalCoreCount() -> Int {
        var count: Int = 0
        var size = MemoryLayout<Int>.size
        sysctlbyname("hw.logicalcpu", &count, &size, nil, 0)
        return count
    }
}
