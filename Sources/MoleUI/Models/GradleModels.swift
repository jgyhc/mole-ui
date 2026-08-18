import Foundation

/// 扫描发现的本地 Gradle 项目信息（包含 Android / Flutter / SpringBoot / Java / Kotlin 等）
public struct GradleProjectInfo: Identifiable, Hashable, Sendable {
    public var id: String { path.path }
    public let name: String
    public let path: URL
    public let wrapperPropertiesPath: URL?
    public let declaredVersion: String?      // 如 "gradle-8.9-all"
    public let distributionUrl: String?      // 完整的 distributionUrl
    public let lastModifiedDate: Date
    public let gitLastCommitDate: Date?

    public init(
        name: String,
        path: URL,
        wrapperPropertiesPath: URL? = nil,
        declaredVersion: String?,
        distributionUrl: String? = nil,
        lastModifiedDate: Date,
        gitLastCommitDate: Date? = nil
    ) {
        self.name = name
        self.path = path
        self.wrapperPropertiesPath = wrapperPropertiesPath
        self.declaredVersion = declaredVersion
        self.distributionUrl = distributionUrl
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

/// Gradle 版本的清理与健康建议状态
public enum GradleRecommendationStatus: String, Sendable, CaseIterable {
    case safeToClean       // 🟢 闲置（0 引用）-> 建议安全清理
    case redundantPatch    // 🔵 冗余小版本（同系列存在更高已安装补丁版）
    case staleInUse        // 🟡 仅归档项目引用（>180天无改动）
    case activeInUse       // 🔴 活跃项目使用中（90天内修改）

    public var title: String {
        switch self {
        case .safeToClean: "闲置可清理"
        case .redundantPatch: "可合并升级"
        case .staleInUse: "仅历史项目引用"
        case .activeInUse: "活跃使用中"
        }
    }

    public var isDefaultSelected: Bool {
        self == .safeToClean
    }

    public var isProtected: Bool {
        self == .activeInUse
    }
}

/// 本地已安装的 Gradle 发行版（位于 ~/.gradle/wrapper/dists）
public struct GradleInstalledVersion: Identifiable, Hashable, Sendable {
    public var id: String { versionName }
    public let versionName: String           // 如 "gradle-8.9-all" 或 "gradle-7.6.1-bin"
    public let path: URL
    public let diskSizeBytes: Int64
    public var projects: [GradleProjectInfo]
    public var status: GradleRecommendationStatus
    public var alternativeVersion: String?   // 建议升级到的本地版本（如 gradle-8.4-bin -> gradle-8.9-bin）

    public init(
        versionName: String,
        path: URL,
        diskSizeBytes: Int64,
        projects: [GradleProjectInfo] = [],
        status: GradleRecommendationStatus = .safeToClean,
        alternativeVersion: String? = nil
    ) {
        self.versionName = versionName
        self.path = path
        self.diskSizeBytes = diskSizeBytes
        self.projects = projects
        self.status = status
        self.alternativeVersion = alternativeVersion
    }
}

/// Gradle 扫描结果统计概要
public struct GradleSummary: Sendable {
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
