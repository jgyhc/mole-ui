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
        var parentPID: Int32
        var startDate: Date?
    }

    struct Usage: Identifiable {
        var id: Int32 { pid }
        var pid: Int32
        var name: String
        var cpuPercent: Double
        var memoryBytes: UInt64
        var parentPID: Int32 = 0
        var startDate: Date?

        var isJava: Bool {
            ProcessMetrics.looksLikeJavaProcess(name: name)
        }
    }

    /// 可解释的 Java 进程来源与活跃状态。
    struct JavaProcessDetails: Identifiable {
        var id: Int32 { pid }
        var pid: Int32
        var name: String
        var cpuPercent: Double
        var memoryBytes: UInt64
        var parentPID: Int32
        var parentAlive: Bool
        var startDate: Date?
        var executablePath: String?
        var commandLine: String
        var workingDirectory: String?
        var parentChain: [String]
        var listeningPorts: [Int]
        var portInspectionSucceeded: Bool

        var isOrphaned: Bool { parentPID == 1 }

        /// 清理策略故意保守：只有被 launchd 接管、无监听端口且当前无 CPU 活动才会列入清理。
        var isInactive: Bool {
            ProcessMetrics.isInactiveJava(
                cpuPercent: cpuPercent,
                parentPID: parentPID,
                listeningPorts: listeningPorts,
                portInspectionSucceeded: portInspectionSucceeded
            )
        }

        var activitySummary: String {
            if !portInspectionSucceeded { return "无法确认监听端口，暂不建议清理" }
            if !listeningPorts.isEmpty { return "正在监听端口：\(listeningPorts.map(String.init).joined(separator: ", "))" }
            if parentPID != 1 { return parentAlive ? "父进程仍在运行" : "父进程已退出" }
            if cpuPercent >= 1 { return "最近仍有 CPU 活动" }
            return "孤儿进程且无端口、无近期 CPU 活动"
        }
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
            let name = processName(info.pbsd.pbi_name)
            result.append(Sample(
                pid: pid,
                name: name,
                cpuTime: info.ptinfo.pti_total_user + info.ptinfo.pti_total_system,
                residentSize: info.ptinfo.pti_resident_size,
                parentPID: Int32(info.pbsd.pbi_ppid),
                startDate: processStartDate(info.pbsd)
            ))
        }
        return result
    }

    /// 查询一个 Java 进程的可解释来源信息。lsof 只在用户请求详情或清理时调用。
    static func inspectJavaProcess(_ usage: Usage) -> JavaProcessDetails {
        let parentPID = usage.parentPID
        let parentAlive = parentPID > 1 && processExists(parentPID)
        let commandLine = commandLine(pid: usage.pid) ?? usage.name
        let executablePath = executablePath(pid: usage.pid)
        let workingDirectory = workingDirectory(pid: usage.pid)
        let portResult = listeningPorts(pid: usage.pid)

        return JavaProcessDetails(
            pid: usage.pid,
            name: usage.name,
            cpuPercent: usage.cpuPercent,
            memoryBytes: usage.memoryBytes,
            parentPID: parentPID,
            parentAlive: parentAlive,
            startDate: usage.startDate,
            executablePath: executablePath,
            commandLine: commandLine,
            workingDirectory: workingDirectory,
            parentChain: parentChain(pid: usage.pid, parentPID: parentPID),
            listeningPorts: portResult.ports,
            portInspectionSucceeded: portResult.succeeded
        )
    }

    /// 两次采样之间某进程的 CPU 使用率（0-100%，可超过 100，多线程）。
    static func cpuPercent(prevTime: UInt64?, currTime: UInt64, elapsed: TimeInterval) -> Double {
        guard let prevTime, elapsed > 0, currTime > prevTime else { return 0 }
        let delta = Double(currTime - prevTime)
        return min(max(delta / (elapsed * 1_000_000_000) * 100, 0), 8_000)
    }

    /// 清理指定 Java 进程前使用的保守规则，便于单元测试和 UI 解释。
    static func isInactiveJava(
        cpuPercent: Double,
        parentPID: Int32,
        listeningPorts: [Int],
        portInspectionSucceeded: Bool
    ) -> Bool {
        portInspectionSucceeded && parentPID == 1 && cpuPercent < 1.0 && listeningPorts.isEmpty
    }

    /// 终止指定进程（SIGTERM 正常退出，force 为 true 时使用 SIGKILL 强制结束）。
    @discardableResult
    static func terminate(pid: Int32, force: Bool = false) -> Bool {
        guard pid > 1 else { return false }
        let sig = force ? SIGKILL : SIGTERM
        return Darwin.kill(pid, sig) == 0
    }

    // MARK: - 原生进程信息

    private static func looksLikeJavaProcess(name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized == "java" || normalized == "javaw" || normalized.contains("java")
    }

    private static func processName<T>(_ rawName: T) -> String {
        var value = rawName
        return withUnsafeBytes(of: &value) { raw -> String in
            guard let address = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: address)
        }
    }

    private static func processStartDate(_ bsdInfo: proc_bsdinfo) -> Date? {
        let seconds = TimeInterval(bsdInfo.pbi_start_tvsec)
        let microseconds = TimeInterval(bsdInfo.pbi_start_tvusec) / 1_000_000
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds + microseconds)
    }

    private static func bsdInfo(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else { return nil }
        return info
    }

    private static func processExists(_ pid: Int32) -> Bool {
        guard Darwin.kill(pid, 0) == 0 else { return errno == EPERM }
        return true
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// KERN_PROCARGS2 返回 argv 与环境变量，argc 用于截取环境变量之前的内容。
    private static func commandLine(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &data, &size, nil, 0) == 0 else { return nil }

        let argc = Int(UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24)
        guard argc >= 0 else { return nil }
        var values: [String] = []
        var start = 4
        while start < data.count && values.count < argc + 1 {
            while start < data.count && data[start] == 0 { start += 1 }
            guard start < data.count else { break }
            let end = data[start...].firstIndex(of: 0) ?? data.count
            if let value = String(bytes: data[start..<end], encoding: .utf8), !value.isEmpty {
                values.append(value)
            }
            start = end + 1
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " ")
    }

    private static func workingDirectory(pid: Int32) -> String? {
        let result = runCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        )
        return result.output.split(whereSeparator: \.isNewline)
            .first(where: { $0.first == "n" })
            .map { String($0.dropFirst()) }
    }

    private static func listeningPorts(pid: Int32) -> (ports: [Int], succeeded: Bool) {
        let result = runCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-Fn"]
        )
        let ports = result.output.split(whereSeparator: \.isNewline).compactMap { line -> Int? in
            guard line.first == "n", let colon = line.lastIndex(of: ":") else { return nil }
            return Int(line[line.index(after: colon)...])
        }
        return (Array(Set(ports)).sorted(), result.started)
    }

    private static func parentChain(pid: Int32, parentPID: Int32) -> [String] {
        var result: [String] = []
        var currentPID = parentPID
        var depth = 0
        while currentPID > 0 && depth < 8 {
            guard let info = bsdInfo(pid: currentPID) else {
                result.append("PID \(currentPID)（已退出或无权限）")
                break
            }
            let name = processName(info.pbi_name)
            result.append("\(name.isEmpty ? "未知进程" : name)（PID: \(currentPID)）")
            if currentPID == 1 { break }
            currentPID = Int32(info.pbi_ppid)
            depth += 1
        }
        return result
    }

    private static func runCommand(executable: String, arguments: [String]) -> (output: String, started: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ("", false)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", true)
    }
}
