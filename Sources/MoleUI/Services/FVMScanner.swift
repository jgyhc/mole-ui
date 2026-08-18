import Foundation

/// FVM (Flutter Version Management) 扫描与版本关联分析引擎
public final class FVMScanner: Sendable {
    public static let shared = FVMScanner()

    public init() {}

    // MARK: - 公开接口

    /// 扫描 FVM 版本及指定目录下的 Flutter 项目
    /// - Parameters:
    ///   - customFvmPath: 自定义 FVM versions 路径（主要用于测试，nil 时自动探测）
    ///   - customSearchRoots: 自定义项目搜索根目录（nil 时采用默认目录 + Spotlight）
    /// - Returns: 已安装版本列表（含关联项目及建议）与统计概要
    public func scan(
        customFvmPath: URL? = nil,
        customSearchRoots: [URL]? = nil
    ) async -> (versions: [FVMInstalledVersion], allProjects: [FlutterProjectInfo], summary: FVMSummary) {
        let fvmVersionsDir = customFvmPath ?? detectFVMVersionsDirectory()
        let installedVersions = scanInstalledVersions(in: fvmVersionsDir)

        let projects = await scanFlutterProjects(customSearchRoots: customSearchRoots)

        // 双向关联分析
        let analyzedVersions = correlate(versions: installedVersions, with: projects)
        let summary = buildSummary(versions: analyzedVersions, projectsCount: projects.count)

        return (analyzedVersions, projects, summary)
    }

    // MARK: - FVM 版本检测

    /// 自动探测 FVM versions 目录（优先包含实体目录的 ~/fvm/versions 或 $FVM_HOME）
    public func detectFVMVersionsDirectory() -> URL? {
        let fm = FileManager.default

        // 1. 检查环境变量 FVM_HOME
        if let envFvmHome = ProcessInfo.processInfo.environment["FVM_HOME"], !envFvmHome.isEmpty {
            let envUrl = URL(fileURLWithPath: envFvmHome).appendingPathComponent("versions")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: envUrl.path, isDirectory: &isDir), isDir.boolValue {
                return envUrl
            }
        }

        // 2. 检查常见默认路径: ~/fvm/versions 优先，其次 ~/.fvm/versions
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            home.appendingPathComponent("fvm/versions"),
            home.appendingPathComponent(".fvm/versions")
        ]

        for candidate in candidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }

        return nil
    }

    /// 扫描已安装版本目录
    public func scanInstalledVersions(in directory: URL?) -> [FVMInstalledVersion] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default

        // 收集候选 FVM versions 目录
        var versionDirs: [URL] = []
        if let directory {
            versionDirs.append(directory)
        } else {
            let fallbackDirs = [
                home.appendingPathComponent("fvm/versions"),
                home.appendingPathComponent(".fvm/versions")
            ]
            for dir in fallbackDirs {
                if fm.fileExists(atPath: dir.path) {
                    versionDirs.append(dir)
                }
            }
        }

        // 确定全局默认版本
        var globalVersionName: String? = nil
        if let directory {
            let localDefault = directory.appendingPathComponent("default")
            if let dest = try? fm.destinationOfSymbolicLink(atPath: localDefault.path) {
                globalVersionName = URL(fileURLWithPath: dest).lastPathComponent
            }
        }
        if globalVersionName == nil {
            globalVersionName = detectGlobalVersion()
        }

        var versionMap: [String: FVMInstalledVersion] = [:]

        for dir in versionDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in contents {
                let name = url.lastPathComponent
                if name == "default" || name == ".DS_Store" { continue }

                // 解析软链接真实目标
                var realUrl = url
                if let dest = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                    realUrl = dest.hasPrefix("/") ? URL(fileURLWithPath: dest) : url.deletingLastPathComponent().appendingPathComponent(dest)
                }

                var isDir: ObjCBool = false
                if fm.fileExists(atPath: realUrl.path, isDirectory: &isDir), isDir.boolValue {
                    let size = calculateDirectorySize(at: realUrl)
                    let isGlobal = (name == globalVersionName) || (globalVersionName != nil && realUrl.lastPathComponent == globalVersionName)

                    if versionMap[name] == nil || (versionMap[name]?.diskSizeBytes ?? 0) < size {
                        versionMap[name] = FVMInstalledVersion(
                            versionName: name,
                            path: realUrl,
                            diskSizeBytes: size,
                            isGlobal: isGlobal
                        )
                    }
                }
            }
        }

        return Array(versionMap.values).sorted { $0.versionName.localizedStandardCompare($1.versionName) == .orderedDescending }
    }

    /// 探测当前 FVM 全局默认版本
    private func detectGlobalVersion() -> String? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default

        // 1. 检查 ~/.fvm/flutter_sdk 符号链接
        let dotFvmSdk = home.appendingPathComponent(".fvm/flutter_sdk")
        if let dest = try? fm.destinationOfSymbolicLink(atPath: dotFvmSdk.path) {
            let name = URL(fileURLWithPath: dest).lastPathComponent
            if !name.isEmpty { return name }
        }

        // 2. 检查 ~/fvm/versions/default 符号链接
        let defaultLink = home.appendingPathComponent("fvm/versions/default")
        if let dest = try? fm.destinationOfSymbolicLink(atPath: defaultLink.path) {
            let name = URL(fileURLWithPath: dest).lastPathComponent
            if !name.isEmpty { return name }
        }

        // 3. 检查 ~/.fvm/fvm_config.json 或 ~/fvm/fvm_config.json
        let configPaths = [
            home.appendingPathComponent(".fvm/fvm_config.json"),
            home.appendingPathComponent("fvm/fvm_config.json"),
            home.appendingPathComponent(".fvm/release"),
            home.appendingPathComponent(".fvm/version")
        ]

        for configUrl in configPaths {
            if let data = try? Data(contentsOf: configUrl) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ver = json["flutterSdkVersion"] as? String ?? json["flutter"] as? String {
                    return ver.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let rawStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawStr.isEmpty {
                    return rawStr
                }
            }
        }

        return nil
    }

    // MARK: - Flutter 项目扫描

    public func scanFlutterProjects(customSearchRoots: [URL]? = nil) async -> [FlutterProjectInfo] {
        var projects: [FlutterProjectInfo] = []

        // 如果用户指定了搜索目录，直接递归扫描用户指定的目录
        if let customRoots = customSearchRoots, !customRoots.isEmpty {
            for root in customRoots {
                projects.append(contentsOf: scanDirectoryRecursively(root))
            }
            return deduplicateProjects(projects)
        }

        // 默认扫描策略：Spotlight 极速查找 + 常用开发目录扫描
        let spotlightPubspecs = runSpotlightQuery()
        for pubspec in spotlightPubspecs {
            let projectDir = pubspec.deletingLastPathComponent()
            if let proj = parseFlutterProject(at: projectDir) {
                projects.append(proj)
            }
        }

        // 扫描常用目录作为强有力补充/保证
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
        process.arguments = ["kMDItemFSName == 'pubspec.yaml'"]

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
                    let path = url.path
                    return isValidProjectPubspecPath(path)
                }
        } catch {
            return []
        }
    }

    private func isValidProjectPubspecPath(_ path: String) -> Bool {
        // 排除 FVM 内部自带示例/测试 SDK 目录及系统/包管理缓存
        if path.contains("/fvm/versions/") ||
           path.contains("/.fvm/versions/") ||
           path.contains("/fvm/cache.git/") ||
           path.contains("/flutter/bin/cache/") ||
           path.contains("/flutter/packages/") ||
           path.contains("/flutter/examples/") ||
           path.contains("/flutter/dev/") ||
           path.contains("/Library/Application Support/Kiro/") ||
           path.contains("/Library/Caches/") ||
           path.contains("/.pub-cache/") ||
           path.contains("/.dart_tool/") ||
           path.contains("/Pods/") ||
           path.contains("/node_modules/") ||
           path.contains("/.Trash/") {
            return false
        }
        return true
    }

    private func scanDirectoryRecursively(_ root: URL) -> [FlutterProjectInfo] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        var results: [FlutterProjectInfo] = []
        let skipNames: Set<String> = [
            ".git", ".svn", "node_modules", "Pods", "DerivedData",
            ".dart_tool", "build", ".build", ".Trash", "Library", "Caches",
            "fvm", ".fvm", "cache.git", ".gradle"
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

            if filename == "pubspec.yaml" {
                let projectDir = url.deletingLastPathComponent()
                if isValidProjectPubspecPath(url.path), let project = parseFlutterProject(at: projectDir) {
                    results.append(project)
                }
                enumerator.skipDescendants()
            }
        }

        return results
    }

    // MARK: - 项目版本解析

    public func parseFlutterProject(at projectDir: URL) -> FlutterProjectInfo? {
        let fm = FileManager.default
        let pubspecUrl = projectDir.appendingPathComponent("pubspec.yaml")
        let fvmDir = projectDir.appendingPathComponent(".fvm")
        let fvmrcUrl = projectDir.appendingPathComponent(".fvmrc")

        let hasPubspec = fm.fileExists(atPath: pubspecUrl.path)
        let hasFVM = fm.fileExists(atPath: fvmDir.path) || fm.fileExists(atPath: fvmrcUrl.path)

        // 必须存在 pubspec.yaml 或者 .fvm 配置
        guard hasPubspec || hasFVM else { return nil }

        var pubspecContent = ""
        if hasPubspec, let content = try? String(contentsOf: pubspecUrl, encoding: .utf8) {
            pubspecContent = content
        }

        // 判定是否为 Flutter/Dart 相关项目
        let isFlutterProject = hasFVM ||
            pubspecContent.contains("flutter:") ||
            pubspecContent.contains("sdk: flutter") ||
            pubspecContent.contains("workspace:") ||
            fm.fileExists(atPath: projectDir.appendingPathComponent(".metadata").path) ||
            fm.fileExists(atPath: projectDir.appendingPathComponent("lib/main.dart").path) ||
            fm.fileExists(atPath: projectDir.appendingPathComponent("android").path) ||
            fm.fileExists(atPath: projectDir.appendingPathComponent("ios").path)

        guard isFlutterProject else { return nil }

        let projectName = extractProjectName(from: pubspecContent) ?? projectDir.lastPathComponent
        let (version, source) = extractDeclaredVersion(in: projectDir, pubspecContent: pubspecContent)

        // 获取修改日期与 Git 最近提交日期
        let modDate = (try? fm.attributesOfItem(atPath: hasPubspec ? pubspecUrl.path : projectDir.path)[.modificationDate] as? Date) ?? Date()
        let gitDate = fetchGitLastCommitDate(in: projectDir)

        return FlutterProjectInfo(
            name: projectName,
            path: projectDir,
            declaredVersion: version,
            versionSource: source,
            lastModifiedDate: modDate,
            gitLastCommitDate: gitDate
        )
    }

    private func extractDeclaredVersion(in projectDir: URL, pubspecContent: String) -> (String?, FlutterVersionSource) {
        let fm = FileManager.default

        // 1. .fvm/fvm_config.json
        let fvmJsonUrl = projectDir.appendingPathComponent(".fvm/fvm_config.json")
        if let data = try? Data(contentsOf: fvmJsonUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ver = json["flutterSdkVersion"] as? String ?? json["flutter"] as? String {
                let trimmed = ver.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return (trimmed, .fvmConfig)
                }
            }
        }

        // 2. .fvmrc
        let fvmrcUrl = projectDir.appendingPathComponent(".fvmrc")
        if let fvmrcContent = try? String(contentsOf: fvmrcUrl, encoding: .utf8) {
            let trimmed = fvmrcContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let data = trimmed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ver = json["flutter"] as? String ?? json["flutterSdkVersion"] as? String {
                    return (ver.trimmingCharacters(in: .whitespacesAndNewlines), .fvmrc)
                }
                return (trimmed, .fvmrc)
            }
        }

        // 3. .fvm/flutter_sdk 软链接
        let symlinkUrl = projectDir.appendingPathComponent(".fvm/flutter_sdk")
        if let dest = try? fm.destinationOfSymbolicLink(atPath: symlinkUrl.path) {
            let verName = URL(fileURLWithPath: dest).lastPathComponent
            if !verName.isEmpty {
                return (verName, .symlink)
            }
        }

        // 4. 从 .fvm/version 文件读取
        let fvmVerUrl = projectDir.appendingPathComponent(".fvm/version")
        if let content = try? String(contentsOf: fvmVerUrl, encoding: .utf8) {
            let ver = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ver.isEmpty {
                return (ver, .fvmConfig)
            }
        }

        return (nil, .unknown)
    }

    private func extractProjectName(from pubspec: String) -> String? {
        for line in pubspec.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "'\"")))
                    if !name.isEmpty { return name }
                }
            }
        }
        return nil
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
        versions: [FVMInstalledVersion],
        with projects: [FlutterProjectInfo]
    ) -> [FVMInstalledVersion] {
        let installedVersionNames = Set(versions.map(\.versionName))

        return versions.map { version in
            var updated = version

            // 找到所有绑定该版本的项目
            let boundProjects = projects.filter { proj in
                if let declared = proj.declaredVersion {
                    return matchVersion(declared: declared, against: version.versionName)
                }
                // 未指定版本的普通 Flutter 项目归入全局默认版本
                if version.isGlobal {
                    return true
                }
                return false
            }
            updated.projects = boundProjects

            // 计算推荐状态
            if version.isGlobal {
                updated.status = .globalDefault
            } else if boundProjects.isEmpty {
                updated.status = .safeToClean
            } else {
                let hasActive = boundProjects.contains(where: \.isActiveRecently)
                let allArchived = boundProjects.allSatisfy(\.isArchived)

                // 检查是否有同系列更高已安装补丁版本（如 3.19.1 与 3.19.6）
                let altVersion = findAlternativeVersion(for: version.versionName, among: installedVersionNames)
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

    /// 宽松版本名称匹配（支持 3.24.5, v3.24.5, 3.24.5-stable 等）
    private func matchVersion(declared: String, against installed: String) -> Bool {
        if declared == installed { return true }
        let cleanDeclared = declared.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
        let cleanInstalled = installed.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
        if cleanDeclared == cleanInstalled { return true }
        if cleanDeclared.hasPrefix(cleanInstalled + "-") || cleanDeclared.hasPrefix(cleanInstalled + "@") { return true }
        if cleanInstalled.hasPrefix(cleanDeclared + "-") || cleanInstalled.hasPrefix(cleanDeclared + "@") { return true }
        return false
    }

    /// 查找同 major.minor 下更高已安装 patch 版本
    private func findAlternativeVersion(for current: String, among installed: Set<String>) -> String? {
        let currentComponents = current.split(separator: ".")
        guard currentComponents.count >= 2 else { return nil }
        let majorMinor = "\(currentComponents[0]).\(currentComponents[1])"

        let candidates = installed.filter { candidate in
            guard candidate != current else { return false }
            return candidate.starts(with: majorMinor + ".")
        }

        return candidates.sorted { $0.localizedStandardCompare($1) == .orderedDescending }.first
    }

    private func buildSummary(versions: [FVMInstalledVersion], projectsCount: Int) -> FVMSummary {
        let totalCount = versions.count
        let totalSize = versions.reduce(0) { $0 + $1.diskSizeBytes }

        let cleanable = versions.filter { $0.status == .safeToClean }
        let cleanableCount = cleanable.count
        let cleanableSize = cleanable.reduce(0) { $0 + $1.diskSizeBytes }

        return FVMSummary(
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
            includingPropertiesForKeys: [.totalFileSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey],
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

    private func deduplicateProjects(_ projects: [FlutterProjectInfo]) -> [FlutterProjectInfo] {
        var seen = Set<String>()
        var deduped: [FlutterProjectInfo] = []
        for p in projects {
            let key = p.path.standardizedFileURL.path
            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(p)
            }
        }
        return deduped.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
