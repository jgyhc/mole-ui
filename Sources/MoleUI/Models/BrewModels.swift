import Foundation

/// Homebrew 软件包类型：命令行工具 (Formula) 或 macOS 桌面应用 (Cask)
public enum BrewPackageType: String, Sendable, Codable, CaseIterable, Identifiable {
    case formula
    case cask

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .formula: "Formula (命令行)"
        case .cask: "Cask (桌面应用)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .formula: "Formula"
        case .cask: "Cask"
        }
    }

    public var symbol: String {
        switch self {
        case .formula: "terminal"
        case .cask: "macwindow"
        }
    }
}

/// Homebrew 软件包安装理由
public enum BrewInstallReason: String, Sendable, Codable {
    case requested    // 用户主动安装 (on request)
    case dependency   // 作为依赖被动安装 (dependency)
    case unknown      // 未知 / 默认
}

/// Homebrew 软件包详细模型
public struct BrewPackage: Identifiable, Sendable, Hashable {
    public var id: String {
        type == .formula ? name : (token ?? name)
    }

    /// 软件包名称（如 `git`, `node` 或 Cask 的 `visual-studio-code`）
    public let name: String
    /// 完整标识（如 `homebrew/core/git`, `can1357/tap/omp`）
    public let fullName: String
    /// Cask 专用标识 token（如 `stash`, `visual-studio-code`）
    public let token: String?
    /// 显示名称（Cask 可能有多个本地化/通用名，优先选用人类可读名）
    public let displayName: String
    /// 类型：Formula 还是 Cask
    public let type: BrewPackageType
    /// 软件仓库 Tap（如 `homebrew/core`, `homebrew/cask`, 第三方 tap）
    public let tap: String?
    /// 软件简介 / 概述
    public let desc: String?
    /// 官方主页 URL
    public let homepage: String?
    /// 开源许可证（如 MIT, Apache-2.0, BSD-3-Clause）
    public let license: String?
    /// 本地已安装的版本
    public let installedVersion: String?
    /// Tap 中最新可用的版本
    public let currentVersion: String?
    /// 是否存在可用更新
    public let isOutdated: Bool
    /// 是否已被用户锁定版本 (pin)
    public let isPinned: Bool
    /// 是否支持自动更新 (Cask auto_updates)
    public let isAutoUpdates: Bool
    /// 是否为 Keg-only 软件（不软链至全局 PATH）
    public let isKegOnly: Bool
    /// 是否为用户主动安装的顶级软件
    public let installReason: BrewInstallReason
    /// 安装时间戳
    public let installedTime: Date?
    /// 磁盘占用空间（字节数）
    public let diskSizeBytes: Int64
    /// 运行时依赖
    public let dependencies: [String]
    /// 构建依赖
    public let buildDependencies: [String]
    /// 被哪些已安装的软件包所依赖（反向依赖关系）
    public var usedBy: [String]
    /// 软件提示与注意事项 (Caveats)
    public let caveats: String?
    /// 软件关联产物列表（可执行文件、App 路径、字体路径等）
    public let artifacts: [String]
    /// 本地文件系统主路径（如 Cellar 或 /Applications 下的路径）
    public let path: URL?

    public init(
        name: String,
        fullName: String? = nil,
        token: String? = nil,
        displayName: String? = nil,
        type: BrewPackageType,
        tap: String? = nil,
        desc: String? = nil,
        homepage: String? = nil,
        license: String? = nil,
        installedVersion: String? = nil,
        currentVersion: String? = nil,
        isOutdated: Bool = false,
        isPinned: Bool = false,
        isAutoUpdates: Bool = false,
        isKegOnly: Bool = false,
        installReason: BrewInstallReason = .unknown,
        installedTime: Date? = nil,
        diskSizeBytes: Int64 = 0,
        dependencies: [String] = [],
        buildDependencies: [String] = [],
        usedBy: [String] = [],
        caveats: String? = nil,
        artifacts: [String] = [],
        path: URL? = nil
    ) {
        self.name = name
        self.fullName = fullName ?? name
        self.token = token
        self.displayName = displayName ?? name
        self.type = type
        self.tap = tap
        self.desc = desc
        self.homepage = homepage
        self.license = license
        self.installedVersion = installedVersion
        self.currentVersion = currentVersion
        self.isOutdated = isOutdated
        self.isPinned = isPinned
        self.isAutoUpdates = isAutoUpdates
        self.isKegOnly = isKegOnly
        self.installReason = installReason
        self.installedTime = installedTime
        self.diskSizeBytes = diskSizeBytes
        self.dependencies = dependencies
        self.buildDependencies = buildDependencies
        self.usedBy = usedBy
        self.caveats = caveats
        self.artifacts = artifacts
        self.path = path
    }

    /// 有效版本文本
    public var displayVersion: String {
        if let installed = installedVersion {
            if isOutdated, let latest = currentVersion, latest != installed {
                return "\(installed) ➔ \(latest)"
            }
            return installed
        }
        return currentVersion ?? "未知版本"
    }
}

/// Homebrew 整体统计摘要
public struct BrewSummary: Sendable, Equatable {
    public let totalPackagesCount: Int
    public let formulaeCount: Int
    public let casksCount: Int
    public let outdatedCount: Int
    public let pinnedCount: Int
    public let totalSizeBytes: Int64
    public let homebrewVersion: String?
    public let homebrewPrefix: String?

    public init(
        totalPackagesCount: Int = 0,
        formulaeCount: Int = 0,
        casksCount: Int = 0,
        outdatedCount: Int = 0,
        pinnedCount: Int = 0,
        totalSizeBytes: Int64 = 0,
        homebrewVersion: String? = nil,
        homebrewPrefix: String? = nil
    ) {
        self.totalPackagesCount = totalPackagesCount
        self.formulaeCount = formulaeCount
        self.casksCount = casksCount
        self.outdatedCount = outdatedCount
        self.pinnedCount = pinnedCount
        self.totalSizeBytes = totalSizeBytes
        self.homebrewVersion = homebrewVersion
        self.homebrewPrefix = homebrewPrefix
    }
}

/// 过滤器类别
public enum BrewFilterTab: String, CaseIterable, Identifiable {
    case all = "全部"
    case formulae = "命令行 (Formula)"
    case casks = "桌面应用 (Cask)"
    case outdated = "可更新"
    case requested = "直接安装"
    case dependencies = "作为依赖"

    public var id: String { rawValue }
}

/// 排序规则
public enum BrewSortOption: String, CaseIterable, Identifiable {
    case name = "名称 (A-Z)"
    case size = "占用空间 (从大到小)"
    case installDate = "安装时间 (最新优先)"
    case outdatedFirst = "更新状态优先"

    public var id: String { rawValue }
}
