import Foundation

/// Node 软件包管理器类型：npm 或 pnpm（可扩展 yarn / bun）
public enum NodePackageManagerType: String, Sendable, Codable, CaseIterable, Identifiable {
    case npm
    case pnpm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .npm: "npm"
        case .pnpm: "pnpm"
        }
    }

    public var displayName: String {
        switch self {
        case .npm: "npm 全局软件"
        case .pnpm: "pnpm 全局软件"
        }
    }

    public var symbol: String {
        switch self {
        case .npm: "shippingbox.fill"
        case .pnpm: "cube.box.fill"
        }
    }
}

/// Node 软件包的二进制命令入口 (CLI Executable)
public struct NodePackageBinary: Sendable, Hashable, Identifiable {
    public var id: String { command }
    public let command: String
    public let targetPath: String

    public init(command: String, targetPath: String) {
        self.command = command
        self.targetPath = targetPath
    }
}

/// Node 软件包详细模型
public struct NodePackage: Identifiable, Sendable, Hashable {
    public var id: String {
        "\(manager.rawValue):\(environmentName):\(name)"
    }

    /// 软件包名（例如 `@anthropic-ai/claude-code`, `wrangler`, `freebuff`）
    public let name: String
    /// 所属包管理器
    public let manager: NodePackageManagerType
    /// 环境名称（如 `NVM v22.19.0`, `Homebrew`, `系统全局`, `pnpm 全局`）
    public let environmentName: String
    /// 是否来自当前终端默认活跃的环境
    public let isActiveEnvironment: Bool
    /// 管理此包对应的 npm / pnpm 可执行程序路径
    public let managerBinPath: String?
    /// 显示名称（若为作用域包可友好展示）
    public let displayName: String
    /// 作用域（如 `@anthropic-ai`）
    public let scope: String?
    /// 当前已安装版本
    public let installedVersion: String
    /// 远端最新版本（若已检测到）
    public var latestVersion: String?
    /// 是否存在可用更新
    public var isOutdated: Bool
    /// 软件包描述 / 简介
    public let desc: String?
    /// 官方主页 URL
    public let homepage: String?
    /// 代码仓库 URL
    public let repository: String?
    /// 开源许可证 (License)
    public let license: String?
    /// 作者信息
    public let author: String?
    /// 提供的 CLI 命令列表（如 `bin: { "claude": "bin/claude.exe" }`）
    public let binaries: [NodePackageBinary]
    /// 磁盘占用物理大小（字节）
    public let diskSizeBytes: Int64
    /// 本地文件系统主目录（如 node_modules/@anthropic-ai/claude-code）
    public let path: URL?
    /// 安装或修改时间戳
    public let installedTime: Date?
    /// Node / 运行引擎要求（如 `node: ">=18.0.0"`）
    public let engines: [String: String]
    /// 生产依赖列表
    public let dependencies: [String: String]
    /// 关键字标签 (Keywords)
    public let keywords: [String]

    public init(
        name: String,
        manager: NodePackageManagerType,
        environmentName: String = "默认环境",
        isActiveEnvironment: Bool = true,
        managerBinPath: String? = nil,
        displayName: String? = nil,
        scope: String? = nil,
        installedVersion: String,
        latestVersion: String? = nil,
        isOutdated: Bool = false,
        desc: String? = nil,
        homepage: String? = nil,
        repository: String? = nil,
        license: String? = nil,
        author: String? = nil,
        binaries: [NodePackageBinary] = [],
        diskSizeBytes: Int64 = 0,
        path: URL? = nil,
        installedTime: Date? = nil,
        engines: [String: String] = [:],
        dependencies: [String: String] = [:],
        keywords: [String] = []
    ) {
        self.name = name
        self.manager = manager
        self.environmentName = environmentName
        self.isActiveEnvironment = isActiveEnvironment
        self.managerBinPath = managerBinPath
        self.displayName = displayName ?? name
        self.scope = scope
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.desc = desc
        self.homepage = homepage
        self.repository = repository
        self.license = license
        self.author = author
        self.binaries = binaries
        self.diskSizeBytes = diskSizeBytes
        self.path = path
        self.installedTime = installedTime
        self.engines = engines
        self.dependencies = dependencies
        self.keywords = keywords
    }

    /// 有效版本显示文本
    public var displayVersion: String {
        if isOutdated, let latest = latestVersion, latest != installedVersion {
            return "\(installedVersion) ➔ \(latest)"
        }
        return installedVersion
    }

    /// 是否包含 CLI 可执行命令行入口
    public var hasBinaries: Bool {
        !binaries.isEmpty
    }
}

/// Node 软件包整体统计摘要
public struct NodePackageSummary: Sendable, Equatable {
    public let totalPackagesCount: Int
    public let npmPackagesCount: Int
    public let pnpmPackagesCount: Int
    public let outdatedCount: Int
    public let totalSizeBytes: Int64
    public let activeNodeVersion: String?
    public let activeNpmVersion: String?
    public let activePnpmVersion: String?
    public let environmentNames: [String]

    public init(
        totalPackagesCount: Int = 0,
        npmPackagesCount: Int = 0,
        pnpmPackagesCount: Int = 0,
        outdatedCount: Int = 0,
        totalSizeBytes: Int64 = 0,
        activeNodeVersion: String? = nil,
        activeNpmVersion: String? = nil,
        activePnpmVersion: String? = nil,
        environmentNames: [String] = []
    ) {
        self.totalPackagesCount = totalPackagesCount
        self.npmPackagesCount = npmPackagesCount
        self.pnpmPackagesCount = pnpmPackagesCount
        self.outdatedCount = outdatedCount
        self.totalSizeBytes = totalSizeBytes
        self.activeNodeVersion = activeNodeVersion
        self.activeNpmVersion = activeNpmVersion
        self.activePnpmVersion = activePnpmVersion
        self.environmentNames = environmentNames
    }
}

/// 过滤器类别
public enum NodePackageFilterTab: String, CaseIterable, Identifiable {
    case all = "全部"
    case npm = "npm"
    case pnpm = "pnpm"
    case outdated = "可更新"
    case hasBin = "包含 CLI 命令"

    public var id: String { rawValue }
}

/// 排序规则
public enum NodePackageSortOption: String, CaseIterable, Identifiable {
    case name = "名称 (A-Z)"
    case size = "占用空间 (从大到小)"
    case installDate = "安装时间 (最新优先)"
    case outdatedFirst = "更新状态优先"

    public var id: String { rawValue }
}
