import Darwin
import Foundation

/// 进程指标采集（原生 API：sysctl KERN_PROC + proc_pidinfo）。
enum ProcessMetrics {
    /// 某时刻的进程原始状态。
    struct Sample {
        var pid: Int32
        var name: String
        /// 累计 CPU 时间（纳秒）
        var cpuTime: UInt64
        var residentSize: UInt64
    }

    struct Usage: Identifiable {
        var id: Int32 { pid }
        var pid: Int32
        var name: String
        var cpuPercent: Double
        var memoryBytes: UInt64
    }

    /// 采集所有进程。
    static func sample() -> [Sample] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var len: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0 else { return [] }
        let count = len / MemoryLayout<kinfo_proc>.size
        guard count > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, u_int(mib.count), &procs, &len, nil, 0) == 0 else { return [] }

        var result: [Sample] = []
        result.reserveCapacity(count)
        for proc in procs {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            var info = proc_taskallinfo()
            let size = MemoryLayout<proc_taskallinfo>.size
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, Int32(size)) == size else { continue }
            let name = withUnsafeBytes(of: info.pbsd.pbi_name) { raw -> String in
                let cString = raw.bindMemory(to: CChar.self).baseAddress!
                return String(cString: cString)
            }
            result.append(Sample(
                pid: pid,
                name: name,
                cpuTime: info.ptinfo.pti_total_user + info.ptinfo.pti_total_system,
                residentSize: info.ptinfo.pti_resident_size
            ))
        }
        return result
    }

    /// 两次采样之间某进程的 CPU 使用率（0-100%，可超过 100，多线程）。
    static func cpuPercent(prevTime: UInt64?, currTime: UInt64, elapsed: TimeInterval) -> Double {
        guard let prevTime, elapsed > 0, currTime > prevTime else { return 0 }
        let delta = Double(currTime - prevTime)
        return min(max(delta / (elapsed * 1_000_000_000) * 100, 0), 8_000)
    }

    /// 终止指定进程（SIGTERM 正常退出，force 为 true 时使用 SIGKILL 强制结束）。
    @discardableResult
    static func terminate(pid: Int32, force: Bool = false) -> Bool {
        guard pid > 1 else { return false }
        let sig = force ? SIGKILL : SIGTERM
        return Darwin.kill(pid, sig) == 0
    }
}
