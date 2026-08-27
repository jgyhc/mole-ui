import Foundation
import Combine

/// 进程排序字段
enum ProcessSortField: String, CaseIterable, Identifiable {
    case cpu = "CPU 占用"
    case memory = "内存占用"
    case name = "进程名称"
    case pid = "PID"

    var id: String { rawValue }
}

/// 进程过滤分类
enum ProcessFilterKind: String, CaseIterable, Identifiable {
    case all = "全部进程"
    case highCPU = "高 CPU 占用"
    case highMemory = "高内存占用"
    case java = "Java 进程"

    var id: String { rawValue }
}

/// 进程监控独立页视图模型：负责采样全系统进程状态、支持搜索、多维度排序与安全终止。
@MainActor
final class ProcessesViewModel: ObservableObject {
    @Published private(set) var allProcesses: [ProcessMetrics.Usage] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isPaused = false
    @Published private(set) var lastUpdated = Date()
    @Published var searchText = ""
    @Published var sortField: ProcessSortField = .cpu
    @Published var sortAscending = false
    @Published var filterKind: ProcessFilterKind = .all

    // 终止进程确认弹窗状态
    @Published var processToTerminate: ProcessMetrics.Usage?
    @Published var terminateErrorMessage: String?
    @Published var javaDetails: ProcessMetrics.JavaProcessDetails?
    @Published var isInspectingJava = false
    @Published var showInactiveJavaConfirmation = false
    @Published private(set) var memorySnapshot: MemoryMetrics.Snapshot?

    private var prevProcessTimes: [Int32: UInt64] = [:]
    private var lastSampleDate = Date()
    private var timer: Timer?
    private let sampleInterval: TimeInterval = 2.0

    // 统计指标
    var totalProcessCount: Int { allProcesses.count }
    var highCPUCount: Int { allProcesses.filter { $0.cpuPercent > 10.0 }.count }
    var totalResidentMemory: UInt64 { allProcesses.reduce(0) { $0 + $1.memoryBytes } }

    /// 过滤与排序后的显示列表
    var filteredProcesses: [ProcessMetrics.Usage] {
        var list = allProcesses

        // 快捷筛选
        switch filterKind {
        case .all:
            break
        case .highCPU:
            list = list.filter { $0.cpuPercent >= 5.0 }
        case .highMemory:
            list = list.filter { $0.memoryBytes >= 100 * 1024 * 1024 } // >= 100MB
        case .java:
            list = list.filter(\.isJava)
        }

        // 文本搜索
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query) || "\($0.pid)".contains(query)
            }
        }

        // 排序
        return list.sorted { a, b in
            let result: Bool
            switch sortField {
            case .cpu:
                result = a.cpuPercent > b.cpuPercent
            case .memory:
                result = a.memoryBytes > b.memoryBytes
            case .name:
                result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .pid:
                result = a.pid < b.pid
            }
            return sortAscending ? !result : result
        }
    }

    func start() {
        guard timer == nil else { return }
        sampleProcesses()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleProcesses()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func togglePaused() {
        isPaused.toggle()
        if isPaused {
            stop()
        } else {
            start()
        }
    }

    func refreshNow() {
        sampleProcesses()
    }

    var javaProcesses: [ProcessMetrics.Usage] {
        allProcesses.filter(\.isJava)
    }

    func inspectJava(_ process: ProcessMetrics.Usage) {
        isInspectingJava = true
        Task.detached(priority: .utility) { [weak self] in
            let details = ProcessMetrics.inspectJavaProcess(process)
            await MainActor.run {
                self?.javaDetails = details
                self?.isInspectingJava = false
            }
        }
    }

    func inspectInactiveJavaProcesses() {
        guard !javaProcesses.isEmpty else {
            javaDetails = nil
            return
        }
        isInspectingJava = true
        let processes = javaProcesses
        Task.detached(priority: .utility) { [weak self] in
            let details = processes.map(ProcessMetrics.inspectJavaProcess)
            let inactive = details.filter(\.isInactive)
            await MainActor.run {
                self?.isInspectingJava = false
                self?.inactiveJavaCandidates = inactive
                self?.showInactiveJavaConfirmation = !inactive.isEmpty
            }
        }
    }

    @Published private(set) var inactiveJavaCandidates: [ProcessMetrics.JavaProcessDetails] = []

    func cancelInactiveJavaCleanup() {
        inactiveJavaCandidates = []
        showInactiveJavaConfirmation = false
    }

    func terminateInactiveJavaProcesses() {
        let candidates = inactiveJavaCandidates
        var terminated = 0
        for candidate in candidates where ProcessMetrics.terminate(pid: candidate.pid) {
            allProcesses.removeAll { $0.pid == candidate.pid }
            OperationLog.append(module: "process", "清理不活跃 Java 进程：\(candidate.name) (PID: \(candidate.pid))")
            terminated += 1
        }
        inactiveJavaCandidates = []
        showInactiveJavaConfirmation = false
        if terminated == 0 && !candidates.isEmpty {
            terminateErrorMessage = "未能清理检测到的不活跃 Java 进程，可能需要管理员权限或进程已退出。"
        }
    }

    /// 终止选中的进程
    func terminateProcess(_ process: ProcessMetrics.Usage, force: Bool = false) {
        let success = ProcessMetrics.terminate(pid: process.pid, force: force)
        if success {
            allProcesses.removeAll { $0.pid == process.pid }
            OperationLog.append(module: "process", "终止进程：\(process.name) (PID: \(process.pid))")
            processToTerminate = nil
        } else {
            terminateErrorMessage = "未能终止进程「\(process.name)」（PID: \(process.pid)），可能需要管理员权限或进程已退出。"
        }
    }

    private func sampleProcesses() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleDate)
        lastSampleDate = now

        memorySnapshot = MemoryMetrics.snapshot()

        let samples = ProcessMetrics.sample()
        let usages = samples.map { sample in
            ProcessMetrics.Usage(
                pid: sample.pid,
                name: sample.name,
                cpuPercent: ProcessMetrics.cpuPercent(
                    prevTime: prevProcessTimes[sample.pid],
                    currTime: sample.cpuTime,
                    elapsed: elapsed
                ),
                memoryBytes: sample.residentSize,
                parentPID: sample.parentPID,
                startDate: sample.startDate
            )
        }

        prevProcessTimes = Dictionary(
            uniqueKeysWithValues: samples.map { ($0.pid, $0.cpuTime) }
        )

        allProcesses = usages
        lastUpdated = now
        isLoading = false
    }
}
