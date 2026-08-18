import Foundation

/// 项目声明 Flutter / FVM 版本的来源途径
public enum FlutterVersionSource: String, Sendable, Codable {
    case fvmConfig = ".fvm/fvm_config.json"
    case fvmrc = ".fvmrc"
    case symlink = ".fvm/flutter_sdk"
    case pubspecConstraint = "pubspec.yaml"
    case unknown = "未指定"
}

/// 扫描发现的本地 Flutter 项目信息
public struct FlutterProjectInfo: Identifiable, Hashable, Sendable {
    public var id: String { path.path }
    public let name: String
    public let path: URL
    public let declaredVersion: String?
    public let versionSource: FlutterVersionSource
    public let lastModifiedDate: Date
    public let gitLastCommitDate: Date?

    public init(
        name: String,
        path: URL,
        declaredVersion: String?,
        versionSource: FlutterVersionSource,
        lastModifiedDate: Date,
        gitLastCommitDate: Date? = nil
    ) {
        self.name = name
        self.path = path
        self.declaredVersion = declaredVersion
        self.versionSource = versionSource
        self.lastModifiedDate = lastModifiedDate
        self.gitLastCommitDate = gitLastCommitDate
    }

    /// 有效最后活跃时间（优先 Git 提交时间，其次文件修改时间）
    public var effectiveActiveDate: Date {
        gitLastCommitDate ?? lastModifiedDate
    }

    /// 是否在 90 天内活跃
    public var isActiveRecently: Bool {
        Date().timeIntervalSince(effectiveActiveDate) < 90 * 24 * 3600
    }

    /// 是否为超过 180 天未动的归档/陈旧项目
    public var isArchived: Bool {
        Date().timeIntervalSince(effectiveActiveDate) > 180 * 24 * 3600
    }
}

/// FVM 版本的清理与健康建议状态
public enum FVMRecommendationStatus: String, Sendable, CaseIterable {
    case safeToClean       // 🟢 闲置（0 引用，非全局）-> 建议安全清理
    case redundantPatch    // 🔵 冗余小版本（同系列存在更高已安装补丁版）
    case staleInUse        // 🟡 仅归档项目引用（>180天无改动）
    case activeInUse       // 🔴 活跃项目使用中（90天内修改）
    case globalDefault     // 🟣 全局默认版本（fvm global）

    public var title: String {
        switch self {
        case .safeToClean: "闲置可清理"
        case .redundantPatch: "可合并升级"
        case .staleInUse: "仅历史项目引用"
        case .activeInUse: "活跃使用中"
        case .globalDefault: "全局默认"
        }
    }

    public var isDefaultSelected: Bool {
        self == .safeToClean
    }

    public var isProtected: Bool {
        self == .activeInUse || self == .globalDefault
    }
}

/// FVM 本地已安装的 Flutter SDK 版本
public struct FVMInstalledVersion: Identifiable, Hashable, Sendable {
    public var id: String { versionName }
    public let versionName: String
    public let path: URL
    public let diskSizeBytes: Int64
    public let isGlobal: Bool
    public var projects: [FlutterProjectInfo]
    public var status: FVMRecommendationStatus
    public var alternativeVersion: String? // 建议升级到的本地版本（如 3.19.1 -> 3.19.6）

    public init(
        versionName: String,
        path: URL,
        diskSizeBytes: Int64,
        isGlobal: Bool = false,
        projects: [FlutterProjectInfo] = [],
        status: FVMRecommendationStatus = .safeToClean,
        alternativeVersion: String? = nil
    ) {
        self.versionName = versionName
        self.path = path
        self.diskSizeBytes = diskSizeBytes
        self.isGlobal = isGlobal
        self.projects = projects
        self.status = status
        self.alternativeVersion = alternativeVersion
    }
}

/// FVM 扫描结果统计概要
public struct FVMSummary: Sendable {
    public let totalVersionsCount: Int
    public let totalSizeBytes: Int64
    public let cleanableVersionsCount: Int
    public let cleanableSizeBytes: Int64
    public let totalProjectsFound: Int

    public init(
        totalVersionsCount: Int = 0,
        totalSizeBytes: Int64 = 0,
        cleanableVersionsCount: Int = 0,
        cleanableSizeBytes: Int64 = 0,
        totalProjectsFound: Int = 0
    ) {
        self.totalVersionsCount = totalVersionsCount
        self.totalSizeBytes = totalSizeBytes
        self.cleanableVersionsCount = cleanableVersionsCount
        self.cleanableSizeBytes = cleanableSizeBytes
        self.totalProjectsFound = totalProjectsFound
    }
}
