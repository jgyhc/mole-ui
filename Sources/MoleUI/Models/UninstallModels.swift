import Foundation

// MARK: - 智能卸载模型（对应 `mo uninstall`）

/// 关联文件安全等级与可删性分类。
enum AssociatedFileSafetyLevel: String, CaseIterable, Identifiable {
    /// 🟢 安全可清理（缓存、日志、临时会话，清理后随时可自动重建）。
    case safe
    /// 🟡 应用专属数据（专属偏好、专属沙盒数据，清理后重置应用）。
    case appData
    /// 🔴 需谨慎 / 共享数据（共享容器、系统级守护进程、用户全局配置，默认不勾选，需用户手动确认）。
    case caution

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: "安全清理"
        case .appData: "应用专属数据"
        case .caution: "需谨慎 / 共享数据"
        }
    }

    var shortTag: String {
        switch self {
        case .safe: "安全"
        case .appData: "专属"
        case .caution: "共享/谨慎"
        }
    }

    /// 默认是否自动勾选。高风险项严禁默认全选。
    var defaultSelected: Bool {
        switch self {
        case .safe, .appData: true
        case .caution: false
        }
    }
}

/// 应用关联文件类别（按系统目录归类）。
enum AppAssociatedFileKind: String, CaseIterable, Identifiable {
    case preferences
    case caches
    case applicationSupport
    case logs
    case containers
    case groupContainers
    case applicationScripts
    case launchAgents
    case launchDaemons
    case privilegedHelperTools
    case userConfig
    case savedState
    case httpStorages
    case webKit
    case cookies
    case autosave
    case quickLook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: "偏好设置"
        case .caches: "缓存"
        case .applicationSupport: "应用支持文件"
        case .logs: "日志"
        case .containers: "沙盒容器"
        case .groupContainers: "共享容器"
        case .applicationScripts: "应用脚本"
        case .launchAgents: "开机启动项"
        case .launchDaemons: "系统守护进程"
        case .privilegedHelperTools: "特权辅助工具"
        case .userConfig: "用户配置与数据"
        case .savedState: "保存的窗口状态"
        case .httpStorages: "HTTP 存储"
        case .webKit: "WebKit 数据"
        case .cookies: "Cookie"
        case .autosave: "自动保存数据"
        case .quickLook: "快速预览插件"
        }
    }

    var symbol: String {
        switch self {
        case .preferences: "gearshape"
        case .caches: "bolt.circle"
        case .applicationSupport: "folder"
        case .logs: "doc.text"
        case .containers: "shippingbox"
        case .groupContainers: "shippingbox.fill"
        case .applicationScripts: "applescript"
        case .launchAgents: "play.circle"
        case .launchDaemons: "bolt.badge.clock"
        case .privilegedHelperTools: "lock.shield"
        case .userConfig: "terminal"
        case .savedState: "memorychip"
        case .httpStorages: "globe"
        case .webKit: "safari"
        case .cookies: "cookie"
        case .autosave: "clock.arrow.circlepath"
        case .quickLook: "eye"
        }
    }

    var defaultSafetyLevel: AssociatedFileSafetyLevel {
        switch self {
        case .caches, .logs, .savedState, .httpStorages, .webKit, .cookies, .autosave:
            return .safe
        case .preferences, .applicationSupport, .containers, .applicationScripts, .launchAgents, .quickLook:
            return .appData
        case .groupContainers, .launchDaemons, .privilegedHelperTools, .userConfig:
            return .caution
        }
    }
}

/// 单个关联文件条目。
struct AssociatedFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let kind: AppAssociatedFileKind
    let safetyLevel: AssociatedFileSafetyLevel
    let warningNote: String?

    init(
        url: URL,
        name: String,
        size: Int64,
        isDirectory: Bool,
        kind: AppAssociatedFileKind,
        safetyLevel: AssociatedFileSafetyLevel? = nil,
        warningNote: String? = nil
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.kind = kind
        self.safetyLevel = safetyLevel ?? kind.defaultSafetyLevel
        self.warningNote = warningNote
    }
}

/// 已安装应用（不含 /System/Applications 系统应用）。
struct InstalledApp: Identifiable {
    var id: String { bundleIdentifier ?? url.path }
    let name: String
    let displayName: String
    let bundleIdentifier: String?
    let version: String?
    let url: URL
    let size: Int64
    let fileCount: Int
}

/// 应用清单扫描进度。
struct AppScanProgress {
    var scannedApps: Int = 0
    var currentName: String = ""
}
