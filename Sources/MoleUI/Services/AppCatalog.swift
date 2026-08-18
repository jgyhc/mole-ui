import Foundation

/// 应用目录清单：枚举已安装应用并定位其关联文件（偏好 / 缓存 / 日志 / 容器 / 启动项 / 系统级守护进程 / 用户配置等）。
/// 不支持 /System/Applications —— 系统应用不可卸载，避免误删系统组件。
enum AppCatalog {
    static let defaultAppDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: NSHomeDirectory() + "/Applications")
    ]

    /// 严格过滤的通用词与系统保留词（绝对不可作为单字候选词，防止误匹配公共目录）。
    static let genericTokens: Set<String> = [
        "desktop", "client", "app", "mac", "macos", "osx", "ios", "ui",
        "helper", "service", "daemon", "agent", "launcher", "runner",
        "server", "web", "browser", "editor", "viewer", "player", "manager",
        "studio", "tool", "tools", "utility", "suite", "pro", "lite",
        "free", "plus", "dev", "beta", "release", "stable", "preview",
        "insiders", "community", "edition", "x86", "arm64", "x64", "universal",
        "google", "microsoft", "adobe", "apple", "tencent", "jetbrains", "alibaba",
        "bytedance", "baidu", "meta", "facebook", "amazon", "mozilla", "com", "org",
        "net", "io", "cn", "me", "bin", "data", "test", "common", "shared",
        "core", "support", "framework", "library", "default"
    ]

    /// 公共套件组件/更新程序/共享服务黑名单（严禁作为关联文件误删）。
    static let sharedBlacklist: Set<String> = [
        "google software update",
        "chrome component builds",
        "autoupdate",
        "mau",
        "edge autoupdate",
        "creative cloud",
        "creative cloud experience",
        "coresync",
        "oobe",
        "caps",
        "slstore",
        "clouddocs",
        "mobilesync",
        "crashpad",
        "diagnosticreports",
        "system",
        "library",
        "desktop"
    ]

    /// 枚举已安装应用，支持最多 `maxDepth` 层子目录递归扫描（如 `/Applications/Utilities`），相同 Bundle ID 去重。
    static func scanInstalledApps(
        in directories: [URL] = AppCatalog.defaultAppDirectories,
        maxDepth: Int = 3,
        onProgress: ((AppScanProgress) -> Void)? = nil
    ) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seenIdentifiers: Set<String> = []
        var seenPaths: Set<String> = []
        var scanned = 0

        func enumerateDirectory(_ dir: URL, currentDepth: Int) {
            guard currentDepth <= maxDepth else { return }
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in urls {
                if Task.isCancelled { break }
                let standardizedPath = url.standardizedFileURL.path.lowercased()
                guard !seenPaths.contains(standardizedPath) else { continue }

                if url.pathExtension.lowercased() == "app" {
                    seenPaths.insert(standardizedPath)
                    scanned += 1
                    let identifier = bundleIdentifier(of: url)
                    if let identifier, !identifier.isEmpty, !seenIdentifiers.insert(identifier.lowercased()).inserted {
                        continue
                    }
                    apps.append(makeApp(url: url, bundleIdentifier: identifier))
                    onProgress?(AppScanProgress(scannedApps: scanned, currentName: url.lastPathComponent))
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let name = url.lastPathComponent
                    if !name.hasPrefix(".") && name != "System" && url.pathExtension.lowercased() != "app" {
                        enumerateDirectory(url, currentDepth: currentDepth + 1)
                    }
                }
            }
        }

        for directory in directories {
            enumerateDirectory(directory, currentDepth: 1)
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 定位应用关联文件，并按安全等级和风险做精准标记（APFS 大小写不敏感去重）。
    static func findAssociatedFiles(
        for app: InstalledApp,
        home: String = NSHomeDirectory()
    ) -> [AssociatedFile] {
        var files: [AssociatedFile] = []
        var seenPaths: Set<String> = []
        let candidates = candidateNames(for: app)
        let appLowerPath = app.url.standardizedFileURL.path.lowercased()

        for kind in AppAssociatedFileKind.allCases {
            for match in kind.locateDetailed(app: app, candidates: candidates, home: home) {
                let lowerPath = match.url.standardizedFileURL.path.lowercased()
                // 排除应用本体和已收录文件（严格大小写无关比对）
                guard lowerPath != appLowerPath else { continue }
                guard !seenPaths.contains(lowerPath) else { continue }
                seenPaths.insert(lowerPath)
                guard let file = makeAssociatedFile(
                    url: match.url,
                    kind: kind,
                    safetyLevel: match.safetyLevel,
                    warningNote: match.warningNote
                ) else { continue }
                files.append(file)
            }
        }
        return files.sorted {
            if $0.safetyLevel.rawValue != $1.safetyLevel.rawValue {
                return $0.safetyLevel.rawValue < $1.safetyLevel.rawValue
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    // MARK: - 候选名提取

    /// 提取严格的候选匹配词（全称、去空格名、连字符名，智能剔除 genericTokens 如 desktop 等通用后缀）。
    static func candidateNames(for app: InstalledApp) -> [String] {
        var set = CaseInsensitiveOrderedSet()

        // 1. 显示名与去空格/连字符版本
        if !app.displayName.isEmpty {
            set.append(app.displayName)
            let noSpace = app.displayName.replacingOccurrences(of: " ", with: "")
            if noSpace != app.displayName {
                set.append(noSpace)
            }
            let hyphenated = app.displayName.lowercased().replacingOccurrences(of: " ", with: "-")
            set.append(hyphenated)
        }

        // 2. Bundle Identifier 全称与有效段
        if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty {
            set.append(bundleIdentifier)
            let parts = bundleIdentifier.split(separator: ".").map(String.init)
            if parts.count >= 2 {
                let lastTwo = parts.suffix(2).joined(separator: ".")
                set.append(lastTwo)
            }
            // 智能段处理：如果末段是通用词（如 desktop），取倒数第二段作为产品名（如 clueark）
            if let last = parts.last {
                let lowerLast = last.lowercased()
                if !genericTokens.contains(lowerLast) && lowerLast.count >= 3 {
                    set.append(last)
                } else if parts.count >= 3 {
                    let secondLast = parts[parts.count - 2]
                    let lowerSecond = secondLast.lowercased()
                    if !genericTokens.contains(lowerSecond) && lowerSecond.count >= 3 {
                        set.append(secondLast)
                    }
                }
            }
        }

        if !app.name.isEmpty && app.name != app.displayName {
            set.append(app.name)
            let noSpace = app.name.replacingOccurrences(of: " ", with: "")
            if noSpace != app.name {
                set.append(noSpace)
            }
        }

        // 3. 可执行文件名 (CFBundleExecutable)
        if let execName = Bundle(url: app.url)?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
           !execName.isEmpty {
            set.append(execName)
        }

        return set.items.filter { candidate in
            let clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return clean.count >= 3 && !genericTokens.contains(clean)
        }
    }

    // MARK: - 私有

    private static func makeApp(url: URL, bundleIdentifier: String?) -> InstalledApp {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let scan = DiskScanner.scan(root: url, options: DiskScanner.Options(collectLargeFiles: false))
        return InstalledApp(
            name: url.deletingPathExtension().lastPathComponent,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            version: version,
            url: url,
            size: scan.root.size,
            fileCount: scan.root.fileCount
        )
    }

    private static func bundleIdentifier(of url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    /// 计算条目大小：文件取分配大小，目录递归聚合。
    private static func makeAssociatedFile(
        url: URL,
        kind: AppAssociatedFileKind,
        safetyLevel: AssociatedFileSafetyLevel,
        warningNote: String?
    ) -> AssociatedFile? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        // 符号链接一律跳过（避免指向应用本体或系统目录）
        if values.isSymbolicLink == true { return nil }
        if values.isDirectory == true {
            let scan = DiskScanner.scan(root: url, options: DiskScanner.Options(collectLargeFiles: false))
            return AssociatedFile(
                url: url,
                name: url.lastPathComponent,
                size: scan.root.size,
                isDirectory: true,
                kind: kind,
                safetyLevel: safetyLevel,
                warningNote: warningNote
            )
        }
        let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        return AssociatedFile(
            url: url,
            name: url.lastPathComponent,
            size: size,
            isDirectory: false,
            kind: kind,
            safetyLevel: safetyLevel,
            warningNote: warningNote
        )
    }
}

// MARK: - 大小写不敏感的去重有序集合

private struct CaseInsensitiveOrderedSet {
    private(set) var items: [String] = []
    private var lowercasedSet: Set<String> = []

    mutating func append(_ element: String) {
        let lower = element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return }
        if lowercasedSet.insert(lower).inserted {
            items.append(element)
        }
    }
}

// MARK: - 匹配项中间结构

struct AssociatedMatch {
    let url: URL
    let safetyLevel: AssociatedFileSafetyLevel
    let warningNote: String?
}

// MARK: - 定位规则扩展

extension AppAssociatedFileKind {
    /// 兼容旧定位接口
    func locate(candidates: [String], home: String) -> [URL] {
        locateDetailed(
            app: InstalledApp(name: "", displayName: "", bundleIdentifier: nil, version: nil, url: URL(fileURLWithPath: "/"), size: 0, fileCount: 0),
            candidates: candidates,
            home: home
        ).map(\.url)
    }

    /// 给定候选名集合，返回该类别下所有存在的关联路径及安全信息。
    func locateDetailed(app: InstalledApp, candidates: [String], home: String) -> [AssociatedMatch] {
        let fileManager = FileManager.default
        let isProduction = (home == NSHomeDirectory())
        let sysRoot = isProduction ? "/" : home

        func userPath(_ components: String...) -> URL {
            URL(fileURLWithPath: home).appendingPathComponent(components.joined(separator: "/"))
        }

        func sysPath(_ components: String...) -> URL {
            URL(fileURLWithPath: sysRoot).appendingPathComponent(components.joined(separator: "/"))
        }

        func existingMatches(_ urls: [URL], level: AssociatedFileSafetyLevel? = nil, warning: String? = nil) -> [AssociatedMatch] {
            urls.compactMap { url in
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                return AssociatedMatch(url: url, safetyLevel: level ?? defaultSafetyLevel, warningNote: warning)
            }
        }

        var results: [AssociatedMatch] = []

        switch self {
        case .preferences:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Preferences/\(candidate).plist"),
                    userPath("Library/SyncedPreferences/\(candidate).plist")
                ], level: .appData))
                results.append(contentsOf: existingMatches([
                    sysPath("Library/Preferences/\(candidate).plist")
                ], level: .caution, warning: "系统全局偏好设置"))
                // ByHost：<candidate>.*.plist
                let byHostURLs = prefixMatches(
                    in: userPath("Library/Preferences/ByHost"), candidate: candidate, suffix: ".plist"
                )
                results.append(contentsOf: existingMatches(byHostURLs, level: .appData))
            }

        case .caches:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Caches/\(candidate)")
                ], level: .safe))
                results.append(contentsOf: existingMatches([
                    sysPath("Library/Caches/\(candidate)")
                ], level: .safe))
            }
            results.append(contentsOf: findVendorSubdirectoryMatches(
                in: userPath("Library/Caches"), candidates: candidates, level: .safe
            ))
            results.append(contentsOf: findVendorSubdirectoryMatches(
                in: sysPath("Library/Caches"), candidates: candidates, level: .safe
            ))

        case .applicationSupport:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Application Support/\(candidate)")
                ], level: .appData))
                results.append(contentsOf: existingMatches([
                    sysPath("Library/Application Support/\(candidate)")
                ], level: .caution, warning: "系统级全局应用支持目录"))
            }
            results.append(contentsOf: findVendorSubdirectoryMatches(
                in: userPath("Library/Application Support"), candidates: candidates, level: .appData
            ))
            results.append(contentsOf: findVendorSubdirectoryMatches(
                in: sysPath("Library/Application Support"), candidates: candidates, level: .caution, warning: "系统级全局应用支持目录"
            ))

        case .logs:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Logs/\(candidate)"),
                    sysPath("Library/Logs/\(candidate)")
                ], level: .safe))
            }
            results.append(contentsOf: findVendorSubdirectoryMatches(
                in: userPath("Library/Logs"), candidates: candidates, level: .safe
            ))
            results.append(contentsOf: findVendorSubdirectoryMatches(
                in: sysPath("Library/Logs"), candidates: candidates, level: .safe
            ))

        case .containers:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Containers/\(candidate)")
                ], level: .appData))
            }

        case .groupContainers:
            let groupDir = userPath("Library/Group Containers")
            if let entries = try? fileManager.contentsOfDirectory(at: groupDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for entry in entries {
                    let name = entry.lastPathComponent
                    for candidate in candidates {
                        if name == "group.\(candidate)" || name.hasSuffix(".\(candidate)") {
                            results.append(AssociatedMatch(
                                url: entry,
                                safetyLevel: .caution,
                                warningNote: "共享容器：可能被同套件应用共用，默认不勾选"
                            ))
                            break
                        }
                    }
                }
            }

        case .applicationScripts:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Application Scripts/\(candidate)")
                ], level: .appData))
            }

        case .launchAgents:
            let userDir = userPath("Library/LaunchAgents")
            let sysDir = sysPath("Library/LaunchAgents")
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userDir.appendingPathComponent("\(candidate).plist")
                ], level: .appData))
                results.append(contentsOf: existingMatches([
                    sysDir.appendingPathComponent("\(candidate).plist")
                ], level: .caution, warning: "系统级开机启动项"))
                results.append(contentsOf: existingMatches(prefixMatches(in: userDir, candidate: candidate), level: .appData))
                results.append(contentsOf: existingMatches(prefixMatches(in: sysDir, candidate: candidate), level: .caution, warning: "系统级开机启动项"))
            }

        case .launchDaemons:
            let sysDir = sysPath("Library/LaunchDaemons")
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    sysDir.appendingPathComponent("\(candidate).plist")
                ], level: .caution, warning: "系统后台守护进程，删除可能需要管理员权限"))
                results.append(contentsOf: existingMatches(
                    prefixMatches(in: sysDir, candidate: candidate),
                    level: .caution,
                    warning: "系统后台守护进程"
                ))
            }

        case .privilegedHelperTools:
            let sysDir = sysPath("Library/PrivilegedHelperTools")
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    sysDir.appendingPathComponent(candidate)
                ], level: .caution, warning: "特权辅助工具，删除可能需要管理员权限"))
                results.append(contentsOf: existingMatches(
                    prefixMatches(in: sysDir, candidate: candidate),
                    level: .caution,
                    warning: "特权辅助工具"
                ))
            }

        case .userConfig:
            let blockedDotfiles: Set<String> = [
                ".", "..", ".Trash", ".ssh", ".bashrc", ".zshrc", ".profile",
                ".gitconfig", ".DS_Store", ".CFUserTextEncoding", ".local", ".config", ".cache"
            ]
            for candidate in candidates {
                let dotName = ".\(candidate.lowercased())"
                if !blockedDotfiles.contains(dotName) && dotName.count > 3 {
                    results.append(contentsOf: existingMatches([
                        userPath(dotName),
                        userPath(".config/\(candidate)"),
                        userPath(".config/\(candidate.lowercased())"),
                        userPath(".local/share/\(candidate)"),
                        userPath(".local/share/\(candidate.lowercased())"),
                        userPath(".cache/\(candidate)"),
                        userPath(".cache/\(candidate.lowercased())")
                    ], level: .caution, warning: "用户配置或工程插件数据，默认不勾选"))
                }
            }

        case .savedState:
            let stateDir = userPath("Library/Saved Application State")
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    stateDir.appendingPathComponent("\(candidate).savedState")
                ], level: .safe))
                results.append(contentsOf: existingMatches(
                    prefixMatches(in: stateDir, candidate: candidate, suffix: ".savedState"),
                    level: .safe
                ))
            }

        case .httpStorages:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/HTTPStorages/\(candidate)"),
                    sysPath("Library/HTTPStorages/\(candidate)")
                ], level: .safe))
            }

        case .webKit:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/WebKit/\(candidate)"),
                    sysPath("Library/WebKit/\(candidate)")
                ], level: .safe))
            }

        case .cookies:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Cookies/\(candidate).binarycookies"),
                    userPath("Library/Cookies/\(candidate).cookies"),
                    userPath("Library/Cookies/\(candidate)")
                ], level: .safe))
            }

        case .autosave:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/Autosave Information/\(candidate)")
                ], level: .safe))
            }

        case .quickLook:
            for candidate in candidates {
                results.append(contentsOf: existingMatches([
                    userPath("Library/QuickLook/\(candidate).qlgenerator"),
                    sysPath("Library/QuickLook/\(candidate).qlgenerator")
                ], level: .appData))
            }
        }

        // 大小写不敏感精准去重
        var unique: [AssociatedMatch] = []
        var seenLowerPaths: Set<String> = []
        for match in results {
            let lowerPath = match.url.standardizedFileURL.path.lowercased()
            if seenLowerPaths.insert(lowerPath).inserted {
                unique.append(match)
            }
        }
        return unique
    }

    /// 目录内前缀匹配：条目名 == candidate 或以 candidate + "." 开头。
    private func prefixMatches(
        in directory: URL, candidate: String, prefix: String = "", suffix: String = ""
    ) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { entry in
            let name = entry.lastPathComponent
            guard name.hasPrefix(prefix) else { return false }
            let rest = name.dropFirst(prefix.count)
            guard rest.caseInsensitiveCompare(candidate) == .orderedSame ||
                rest.lowercased().hasPrefix(candidate.lowercased() + ".") ||
                rest.lowercased().hasPrefix(candidate.lowercased() + "-") else { return false }
            guard suffix.isEmpty || name.lowercased().hasSuffix(suffix.lowercased()) else { return false }
            return true
        }
    }

    /// 精准探测厂商二级子目录（严格等值/规范化全等比对，杜绝反向子串模糊匹配与通用词误配）。
    private func findVendorSubdirectoryMatches(
        in baseDir: URL,
        candidates: [String],
        level: AssociatedFileSafetyLevel,
        warning: String? = nil
    ) -> [AssociatedMatch] {
        let fileManager = FileManager.default
        guard let vendorDirs = try? fileManager.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var matches: [AssociatedMatch] = []
        for vendorDir in vendorDirs {
            guard (try? vendorDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let productEntries = try? fileManager.contentsOfDirectory(
                at: vendorDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for productEntry in productEntries {
                let productName = productEntry.lastPathComponent
                let cleanProduct = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                // 黑名单与通用词跳过
                if AppCatalog.sharedBlacklist.contains(cleanProduct) || AppCatalog.genericTokens.contains(cleanProduct) {
                    continue
                }

                for candidate in candidates {
                    let cleanCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let noSpaceCand = cleanCandidate.replacingOccurrences(of: " ", with: "")
                    let noSpaceProd = cleanProduct.replacingOccurrences(of: " ", with: "")

                    // 精准比对：全等，或去空格全等，或规范化复合名全等
                    if cleanProduct == cleanCandidate ||
                        noSpaceProd == noSpaceCand ||
                        cleanProduct == "\(vendorDir.lastPathComponent.lowercased()) \(cleanCandidate)" ||
                        (cleanProduct.count >= 4 && cleanCandidate.hasSuffix(cleanProduct)) {
                        matches.append(AssociatedMatch(
                            url: productEntry,
                            safetyLevel: level,
                            warningNote: warning
                        ))
                        break
                    }
                }
            }
        }
        return matches
    }
}
