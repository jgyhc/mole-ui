import Foundation

/// Gradle Wrapper 发行版扫描与项目依赖分析引擎
public final class GradleScanner: Sendable {
    public static let shared = GradleScanner()

    public init() {}

    // MARK: - 公开接口

    /// 扫描 Gradle dists 版本及指定目录下的 Gradle 项目
    public func scan(
        customDistsPath: URL? = nil,
        customSearchRoots: [URL]? = nil
    ) async -> (versions: [GradleInstalledVersion], allProjects: [GradleProjectInfo], summary: GradleSummary) {
        let distsDir = customDistsPath ?? detectGradleDistsDirectory()
        let installedVersions = scanInstalledVersions(in: distsDir)

        let projects = await scanGradleProjects(customSearchRoots: customSearchRoots)

        // 双向关联分析
        let analyzedVersions = correlate(versions: installedVersions, with: projects)
        let summary = buildSummary(versions: analyzedVersions, projectsCount: projects.count)

        return (analyzedVersions, projects, summary)
    }

    // MARK: - Gradle Dists 目录检测

    public func detectGradleDistsDirectory() -> URL? {
        let fm = FileManager.default

        // 1. 检查环境变量 GRADLE_USER_HOME
        if let envGradle = ProcessInfo.processInfo.environment["GRADLE_USER_HOME"], !envGradle.isEmpty {
            let envUrl = URL(fileURLWithPath: envGradle).appendingPathComponent("wrapper/dists")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: envUrl.path, isDirectory: &isDir), isDir.boolValue {
                return envUrl
            }
        }

        // 2. 默认路径 ~/.gradle/wrapper/dists
        let defaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gradle/wrapper/dists")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: defaultPath.path, isDirectory: &isDir), isDir.boolValue {
            return defaultPath
        }

        return nil
    }

    /// 扫描 ~/.gradle/wrapper/dists 下的已安装发行版
    public func scanInstalledVersions(in directory: URL?) -> [GradleInstalledVersion] {
        guard let directory else { return [] }
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var versions: [GradleInstalledVersion] = []

        for url in contents {
            let name = url.lastPathComponent
            if name.starts(with: ".") || name == "CACHEDIR.TAG" || name.contains("REPLACEME") {
                continue
            }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let size = calculateDirectorySize(at: url)
                if size > 0 {
                    versions.append(GradleInstalledVersion(
                        versionName: name,
                        path: url,
                        diskSizeBytes: size
                    ))
                }
            }
        }

        // 按版本号降序排序
        return versions.sorted { $0.versionName.localizedStandardCompare($1.versionName) == .orderedDescending }
    }

    // MARK: - 项目扫描

    public func scanGradleProjects(customSearchRoots: [URL]? = nil) async -> [GradleProjectInfo] {
        var projects: [GradleProjectInfo] = []

        // 1. 如果指定了目录，直接深度遍历指定目录
        if let customRoots = customSearchRoots, !customRoots.isEmpty {
            for root in customRoots {
                projects.append(contentsOf: scanDirectoryRecursively(root))
            }
            return deduplicateProjects(projects)
        }

        // 2. 默认采用 Spotlight 极速检索
        let spotlightProps = runSpotlightQuery()
        for prop in spotlightProps {
            if let proj = parseGradleProject(fromWrapperProperties: prop) {
                projects.append(proj)
            }
        }

        // 3. 补充扫描常用目录
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let defaultRoots = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Workspace"),
            home.appendingPathComponent("src"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Code")
        ]

        for root in defaultRoots {
            projects.append(contentsOf: scanDirectoryRecursively(root))
        }

        return deduplicateProjects(projects)
    }

    private func runSpotlightQuery() -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemFSName == 'gradle-wrapper.properties'"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            return output
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
                .filter { url in
                    isValidProjectPath(url.path)
                }
        } catch {
            return []
        }
    }

    private func isValidProjectPath(_ path: String) -> Bool {
        if path.contains("/.gradle/") ||
           path.contains("/.pub-cache/") ||
           path.contains("/.dart_tool/") ||
           path.contains("/Pods/") ||
           path.contains("/node_modules/") ||
           path.contains("/.Trash/") ||
           path.contains("/build/") ||
           path.contains("/.build/") ||
           path.contains("/Library/") {
            return false
        }
        return true
    }

    private func scanDirectoryRecursively(_ root: URL) -> [GradleProjectInfo] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        var results: [GradleProjectInfo] = []
        let skipNames: Set<String> = [
            ".git", ".svn", "node_modules", "Pods", "DerivedData",
            ".dart_tool", "build", ".build", ".Trash", "Library", "Caches",
            ".gradle", ".pub-cache"
        ]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            let filename = url.lastPathComponent
            if skipNames.contains(filename) {
                enumerator.skipDescendants()
                continue
            }

            if filename == "gradle-wrapper.properties" {
                if isValidProjectPath(url.path), let project = parseGradleProject(fromWrapperProperties: url) {
                    results.append(project)
                }
                enumerator.skipDescendants()
            }
        }

        return results
    }

    // MARK: - 项目与版本属性解析

    public func parseGradleProject(fromWrapperProperties propUrl: URL) -> GradleProjectInfo? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: propUrl.path),
              let content = try? String(contentsOf: propUrl, encoding: .utf8) else {
            return nil
        }

        let (declaredVer, distUrl) = extractGradleVersion(from: content)

        // 定位项目根目录：gradle-wrapper.properties 通常位于 <projectRoot>/gradle/wrapper/gradle-wrapper.properties
        var projectRoot = propUrl.deletingLastPathComponent().deletingLastPathComponent()
        var projectName = projectRoot.lastPathComponent

        // 如果是子模块（如 android/gradle/wrapper），上探一级获取主项目名
        if projectName == "android" || projectName == "app" {
            let parent = projectRoot.deletingLastPathComponent()
            if parent.path != "/" && parent.path != NSHomeDirectory() {
                projectRoot = parent
                projectName = parent.lastPathComponent
            }
        }

        let modDate = (try? fm.attributesOfItem(atPath: propUrl.path)[.modificationDate] as? Date) ?? Date()
        let gitDate = fetchGitLastCommitDate(in: projectRoot)

        return GradleProjectInfo(
            name: projectName,
            path: projectRoot,
            wrapperPropertiesPath: propUrl,
            declaredVersion: declaredVer,
            distributionUrl: distUrl,
            lastModifiedDate: modDate,
            gitLastCommitDate: gitDate
        )
    }

    public func extractGradleVersion(from propertiesContent: String) -> (String?, String?) {
        for line in propertiesContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("distributionUrl") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let rawUrl = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\:", with: ":")

                    // 从 URL 中提取类似 gradle-8.9-all 或 gradle-8.9-bin
                    // 例如: https://services.gradle.org/distributions/gradle-8.9-all.zip -> gradle-8.9-all
                    if let filename = rawUrl.split(separator: "/").last {
                        let nameWithoutZip = filename.replacingOccurrences(of: ".zip", with: "")
                        return (nameWithoutZip, rawUrl)
                    }
                    return (nil, rawUrl)
                }
            }
        }
        return (nil, nil)
    }

    private func fetchGitLastCommitDate(in projectDir: URL) -> Date? {
        let gitDir = projectDir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectDir.path, "log", "-1", "--format=%ct"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let timestamp = Double(output) {
                return Date(timeIntervalSince1970: timestamp)
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - 关联与推荐算法

    public func correlate(
        versions: [GradleInstalledVersion],
        with projects: [GradleProjectInfo]
    ) -> [GradleInstalledVersion] {
        let installedVersionNames = Set(versions.map(\.versionName))

        return versions.map { version in
            var updated = version

            // 找到所有使用该版本的项目
            let boundProjects = projects.filter { proj in
                guard let declared = proj.declaredVersion else { return false }
                return matchGradleVersion(declared: declared, against: version.versionName)
            }
            updated.projects = boundProjects

            // 计算推荐状态
            if boundProjects.isEmpty {
                updated.status = .safeToClean
            } else {
                let hasActive = boundProjects.contains(where: \.isActiveRecently)
                let allArchived = boundProjects.allSatisfy(\.isArchived)

                let altVersion = findAlternativeGradleVersion(for: version.versionName, among: installedVersionNames)
                updated.alternativeVersion = altVersion

                if altVersion != nil && !hasActive {
                    updated.status = .redundantPatch
                } else if hasActive {
                    updated.status = .activeInUse
                } else if allArchived {
                    updated.status = .staleInUse
                } else {
                    updated.status = .activeInUse
                }
            }

            return updated
        }
    }

    private func matchGradleVersion(declared: String, against installed: String) -> Bool {
        if declared == installed { return true }
        // 兼容去除 -all / -bin 后的比对
        let cleanDeclared = declared.replacingOccurrences(of: ".zip", with: "").trimmingCharacters(in: .whitespaces)
        let cleanInstalled = installed.replacingOccurrences(of: ".zip", with: "").trimmingCharacters(in: .whitespaces)
        return cleanDeclared == cleanInstalled
    }

    /// 查找同大版本/同类型下的更高已安装版本（如 gradle-8.4-bin -> gradle-8.9-bin）
    private func findAlternativeGradleVersion(for current: String, among installed: Set<String>) -> String? {
        let isAll = current.hasSuffix("-all")
        let isBin = current.hasSuffix("-bin")
        let typeSuffix = isAll ? "-all" : (isBin ? "-bin" : "")

        let cleanVer = current.replacingOccurrences(of: "gradle-", with: "").replacingOccurrences(of: typeSuffix, with: "")
        let components = cleanVer.split(separator: ".")
        guard let major = components.first else { return nil }

        let candidates = installed.filter { candidate in
            guard candidate != current else { return false }
            if !typeSuffix.isEmpty && !candidate.hasSuffix(typeSuffix) { return false }
            return candidate.starts(with: "gradle-\(major).")
        }

        return candidates.sorted { $0.localizedStandardCompare($1) == .orderedDescending }.first
    }

    private func buildSummary(versions: [GradleInstalledVersion], projectsCount: Int) -> GradleSummary {
        let totalCount = versions.count
        let totalSize = versions.reduce(0) { $0 + $1.diskSizeBytes }

        let cleanable = versions.filter { $0.status == .safeToClean }
        let cleanableCount = cleanable.count
        let cleanableSize = cleanable.reduce(0) { $0 + $1.diskSizeBytes }

        return GradleSummary(
            totalVersionsCount: totalCount,
            totalSizeBytes: totalSize,
            cleanableVersionsCount: cleanableCount,
            cleanableSizeBytes: cleanableSize,
            totalProjectsFound: projectsCount
        )
    }

    private func calculateDirectorySize(at directory: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileSizeKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileUrl as URL in enumerator {
            guard let values = try? fileUrl.resourceValues(forKeys: [.totalFileSizeKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else {
                continue
            }
            totalSize += Int64(values.totalFileSize ?? 0)
        }
        return totalSize
    }

    private func deduplicateProjects(_ projects: [GradleProjectInfo]) -> [GradleProjectInfo] {
        var seen = Set<String>()
        var deduped: [GradleProjectInfo] = []
        for p in projects {
            let key = p.wrapperPropertiesPath?.path ?? p.path.path
            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(p)
            }
        }
        return deduped.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
