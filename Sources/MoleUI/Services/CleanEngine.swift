import Foundation

/// 深度清理引擎：分类扫描（复用 DiskScanner）、卸载残留检测、清理执行（默认移入废纸篓）。
enum CleanEngine {
    /// 扫描全部分类（顺序执行，逐个回调进度）。
    static func scanAll(onProgress: @escaping (CleanScanProgress) -> Void) -> [CleanCategoryResult] {
        var results: [CleanCategoryResult] = []
        for category in CleanCategory.allCases {
            onProgress(CleanScanProgress(currentCategory: category.title, scannedFiles: 0))
            let result = scanCategory(category) { scanned in
                onProgress(CleanScanProgress(currentCategory: category.title, scannedFiles: scanned))
            }
            results.append(result)
        }
        return results
    }

    static func scanCategory(_ category: CleanCategory, onProgress: ((Int) -> Void)? = nil) -> CleanCategoryResult {
        let options = DiskScanner.Options(collectLargeFiles: false)
        var items: [CleanItem] = []
        var totalSize: Int64 = 0
        var errorCount = 0

        for root in category.rootPaths {
            let scan = DiskScanner.scan(root: root, options: options) { progress in
                onProgress?(progress.scannedFiles)
            }
            totalSize += scan.root.size
            errorCount += scan.errorCount
            for child in scan.root.children ?? [] {
                items.append(CleanItem(
                    url: child.url, name: child.name, size: child.size,
                    isDirectory: child.isDirectory, fileCount: child.fileCount,
                    category: category
                ))
            }
        }

        if category == .leftovers {
            let leftovers = scanLeftovers { onProgress?($0) }
            items = leftovers
            totalSize = leftovers.reduce(0) { $0 + $1.size }
        }

        items.sort { $0.size > $1.size }
        return CleanCategoryResult(category: category, totalSize: totalSize, items: items, errorCount: errorCount)
    }

    // MARK: - 卸载残留检测

    /// 名称归一化：小写 + 去除非字母数字（用于应用名/包名/目录名比对）。
    static func normalizeName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 检测已卸载应用的残留目录（Application Support / Caches / Containers / Preferences 中
    /// 找不到对应已安装应用的条目）。保守策略：只收 >10MB 的候选，且用户默认不勾选、人工确认。
    static func scanLeftovers(onProgress: @escaping (Int) -> Void) -> [CleanItem] {
        let installed = InstalledApps.normalizedNames()
        let cliTools = InstalledApps.cliNames()
        // 覆盖判定：精确匹配不受长度限制；前缀匹配要求较短一方 ≥4 字符，
        // 避免 "go"、"bc" 这类短命令名把 "google"、"bclib" 等误覆盖。
        func isCovered(_ candidate: String) -> Bool {
            func covered(by names: Set<String>) -> Bool {
                names.contains { name in
                    if candidate == name { return true }
                    if candidate.hasPrefix(name) || name.hasPrefix(candidate) {
                        return min(candidate.count, name.count) >= 4
                    }
                    return false
                }
            }
            return covered(by: installed) || covered(by: cliTools)
        }
        // 无对应 app 的系统/共享目录白名单（前缀或精确匹配）
        let systemNames: Set<String> = [
            "apple", "mobilesync", "keyboard", "addressbook", "callhistory", "coresimulator",
            "icloud", "telephony", "voicemail", "preferences", "syncservices", "widgets",
            "sounds", "voices", "speech", "cfnetwork", "comapple", "comapplehelp", "printers",
            "assistant", "crashreporter", "diskimages", "filesystems", "knowledge", "mds",
            "shortcuts", "suggestions", "textcomposer", "translation", "universalaccess",
            "notifications", "parsecfnetwork", "orgswiftswiftpm", "node", "npm", "gradle",
            "maven", "cocoapods", "homebrew", "carthage", "spm", "xcode", "docker",
            "virtualbox", "parallels", "vmware", "geoservices", "sogou", "wifianalytics",
            "locationd", "comappleaccountsd"
        ]

        // 已安装应用名是否覆盖候选目录名（前缀关系）：
        // 如 "dingtalkmac" 被 "dingtalk" 覆盖、"google" 被 "googlechrome" 覆盖。
        // 保守策略：宁可漏报，不可误报。
        let minCandidateSize: Int64 = 10 * 1024 * 1024
        let roots = [
            "Library/Application Support",
            "Library/Caches",
            "Library/Containers",
            "Library/Preferences"
        ].map { NSHomeDirectory() + "/" + $0 }

        var candidates: [CleanItem] = []
        for root in roots {
            let url = URL(fileURLWithPath: root)
            let children = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            for child in children ?? [] {
                let name = child.lastPathComponent
                let normalized = normalizeName(name)
                if normalized.isEmpty || systemNames.contains(normalized) { continue }
                if normalized.hasPrefix("comapple") { continue }
                if isCovered(normalized) { continue }
                // 符号链接跳过
                if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { continue }
                let scan = DiskScanner.scan(root: child, options: DiskScanner.Options(collectLargeFiles: false)) { progress in
                    onProgress(progress.scannedFiles)
                }
                guard scan.root.size >= minCandidateSize else { continue }
                candidates.append(CleanItem(
                    url: child, name: name, size: scan.root.size,
                    isDirectory: true, fileCount: scan.root.fileCount,
                    category: .leftovers
                ))
            }
        }
        candidates.sort { $0.size > $1.size }
        if candidates.count > 50 {
            candidates = Array(candidates.prefix(50))
        }
        return candidates
    }

    // MARK: - 清理执行

    /// 执行清理：普通条目移入废纸篓（可恢复），废纸篓类别永久删除。
    /// 返回 (移入废纸篓数量, 永久删除数量)。
    @discardableResult
    static func clean(items: [CleanItem]) throws -> (moved: Int, permanent: Int) {
        let fileManager = FileManager.default
        var moved = 0
        var permanent = 0
        var lastError: Error?
        for item in items {
            guard !TrashService.isProtected(item.url) else { continue }
            do {
                if item.isPermanent {
                    try fileManager.removeItem(at: item.url)
                    permanent += 1
                    OperationLog.append(module: "clean", "永久删除：\(item.url.path)（\(ByteFormatter.fileString(from: item.size))）")
                } else {
                    try fileManager.trashItem(at: item.url, resultingItemURL: nil)
                    moved += 1
                    OperationLog.append(module: "clean", "移入废纸篓：\(item.url.path)（\(ByteFormatter.fileString(from: item.size))）")
                }
            } catch {
                lastError = error
            }
        }
        if moved == 0 && permanent == 0, let lastError {
            throw lastError
        }
        if moved > 0 || permanent > 0 {
            OperationLog.append(module: "clean", "完成：移入废纸篓 \(moved) 项，永久删除 \(permanent) 项")
        }
        return (moved, permanent)
    }
}

/// 已安装应用清单（用于残留检测）。
enum InstalledApps {
    /// PATH 中的命令行工具名（fvm、gitkraken 等非 .app 软件的数据目录不应视为残留）。
    static func cliNames() -> Set<String> {
        var directories: [String] = [
            "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/bin"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        var names: Set<String> = []
        for directory in directories {
            let urls = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in urls ?? [] {
                names.insert(CleanEngine.normalizeName(url.deletingPathExtension().lastPathComponent))
            }
        }
        return names
    }

    /// 所有已安装应用的归一化名称集合（应用名 + Bundle ID + 显示名）。
    static func normalizedNames() -> Set<String> {
        let directories = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications"
        ]
        var names: Set<String> = []
        for directory in directories {
            let urls = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in urls ?? [] where url.pathExtension == "app" {
                names.insert(CleanEngine.normalizeName(url.deletingPathExtension().lastPathComponent))
                if let bundle = Bundle(url: url) {
                    if let identifier = bundle.bundleIdentifier {
                        names.insert(CleanEngine.normalizeName(identifier))
                    }
                    if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                        names.insert(CleanEngine.normalizeName(displayName))
                    }
                }
            }
        }
        return names
    }
}
