import Foundation

// MARK: - 系统优化（对应 `mo optimize`）

/// 优化任务分组。
enum OptimizationGroup: String, CaseIterable, Identifiable {
    case maintenance
    case network
    case caches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maintenance: "系统维护"
        case .network: "网络"
        case .caches: "缓存与日志"
        }
    }

    var symbol: String {
        switch self {
        case .maintenance: "gearshape.2"
        case .network: "network"
        case .caches: "archivebox"
        }
    }
}

/// 任务执行方式。
enum OptimizationAction {
    /// 直接执行一条命令（不经 shell，避免注入；固定可执行文件与参数）。
    case command(executable: String, arguments: [String])
    /// 将目录内的全部条目移入废纸篓（保留目录本身）。
    case trashDirectoryContents(path: String)
}

/// 单个优化任务。
struct OptimizationTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let group: OptimizationGroup
    /// 需要管理员权限的任务在普通权限下不可执行。
    let requiresRoot: Bool
    let action: OptimizationAction

    /// 全部内置任务。
    static let all: [OptimizationTask] = [
        OptimizationTask(
            id: "launch-services",
            title: "重建 LaunchServices 数据库",
            detail: "重新注册 /Applications 中的应用（lsregister），修复双击打不开、图标异常等问题",
            symbol: "arrow.triangle.2.circlepath",
            group: .maintenance,
            requiresRoot: false,
            action: .command(
                executable: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                arguments: ["-kill", "-r", "-domain", "local", "-domain", "user"]
            )
        ),
        OptimizationTask(
            id: "refresh-finder",
            title: "刷新 Finder",
            detail: "重启 Finder 进程，让图标、边栏与排序立即刷新",
            symbol: "folder",
            group: .maintenance,
            requiresRoot: false,
            action: .command(executable: "/usr/bin/killall", arguments: ["Finder"])
        ),
        OptimizationTask(
            id: "refresh-dock",
            title: "刷新 Dock",
            detail: "重启 Dock 进程，清理卡顿的窗口预览与动画",
            symbol: "dock.rectangle",
            group: .maintenance,
            requiresRoot: false,
            action: .command(executable: "/usr/bin/killall", arguments: ["Dock"])
        ),
        OptimizationTask(
            id: "rebuild-spotlight",
            title: "重建 Spotlight 索引",
            detail: "全盘重新建立 Spotlight 索引，修复搜索无结果的问题（需要管理员权限）",
            symbol: "magnifyingglass",
            group: .maintenance,
            requiresRoot: true,
            action: .command(executable: "/usr/bin/mdutil", arguments: ["-E", "/"])
        ),
        OptimizationTask(
            id: "flush-dns",
            title: "清理 DNS 缓存",
            detail: "刷新 DNS 解析缓存（dscacheutil），解决域名解析异常",
            symbol: "network",
            group: .network,
            requiresRoot: false,
            action: .command(executable: "/usr/bin/dscacheutil", arguments: ["-flushcache"])
        ),
        OptimizationTask(
            id: "reset-mdns",
            title: "重置 mDNS 响应器",
            detail: "重启 mDNSResponder，修复本地网络发现异常（需要管理员权限）",
            symbol: "wifi",
            group: .network,
            requiresRoot: true,
            action: .command(executable: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
        ),
        OptimizationTask(
            id: "clean-user-diagnostics",
            title: "清理用户诊断报告",
            detail: "将 ~/Library/Logs/DiagnosticReports 中的崩溃与诊断报告移入废纸篓",
            symbol: "exclamationmark.triangle",
            group: .caches,
            requiresRoot: false,
            action: .trashDirectoryContents(path: NSHomeDirectory() + "/Library/Logs/DiagnosticReports")
        ),
        OptimizationTask(
            id: "clean-system-diagnostics",
            title: "清理系统诊断报告",
            detail: "清理 /Library/Logs/DiagnosticReports 系统级诊断报告（需要管理员权限）",
            symbol: "externaldrive",
            group: .caches,
            requiresRoot: true,
            action: .trashDirectoryContents(path: "/Library/Logs/DiagnosticReports")
        )
    ]
}

/// 任务状态。
enum OptimizationTaskState {
    case idle
    case running
    case succeeded(message: String)
    case failed(message: String)
    case skipped(reason: String)
}

/// 带运行状态的任务条目。
struct OptimizationTaskEntry: Identifiable {
    let task: OptimizationTask
    var state: OptimizationTaskState = .idle

    var id: String { task.id }
}
