import Foundation

/// Gradle 版本安全清理与项目配置迁移服务
public final class GradleCleaner: Sendable {
    public static let shared = GradleCleaner()

    public init() {}

    /// 将指定的 Gradle 发行版目录移入废纸篓
    @discardableResult
    public func cleanVersions(_ versions: [GradleInstalledVersion]) throws -> Int {
        let urls = versions.map(\.path)
        let count = try TrashService.moveToTrash(urls)

        for version in versions {
            OperationLog.append(module: "gradle", "已将 Gradle 发行版 [\(version.versionName)] 移入废纸篓")
        }

        return count
    }

    /// 将项目的 gradle-wrapper.properties 中的 Gradle 发行版升级替换为新版本
    public func migrateProject(
        project: GradleProjectInfo,
        toVersion targetVersion: String
    ) throws {
        guard let propUrl = project.wrapperPropertiesPath else {
            throw NSError(domain: "GradleCleaner", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 gradle-wrapper.properties 文件"])
        }

        let content = try String(contentsOf: propUrl, encoding: .utf8)
        var newLines: [String] = []

        // 规范目标文件名
        let targetFileName = targetVersion.hasSuffix(".zip") ? targetVersion : "\(targetVersion).zip"

        for line in content.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("distributionUrl") {
                // 替换 URL 结尾的文件名
                // 例如: distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
                if let lastSlash = line.lastIndex(of: "/") {
                    let prefix = line[..<line.index(after: lastSlash)]
                    newLines.append("\(prefix)\(targetFileName)")
                } else if let eqIndex = line.firstIndex(of: "=") {
                    let prefix = line[...eqIndex]
                    newLines.append("\(prefix)https\\://services.gradle.org/distributions/\(targetFileName)")
                } else {
                    newLines.append("distributionUrl=https\\://services.gradle.org/distributions/\(targetFileName)")
                }
            } else {
                newLines.append(line)
            }
        }

        let updatedContent = newLines.joined(separator: "\n")
        try updatedContent.write(to: propUrl, atomically: true, encoding: .utf8)

        OperationLog.append(module: "gradle", "已将项目 [\(project.name)] 的 Gradle 升级为 \(targetVersion)")
    }
}
