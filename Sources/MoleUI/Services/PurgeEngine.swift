import Foundation

/// 项目产物清理引擎（对应 `mo purge`）。
/// 策略：先按清单文件识别项目类型（Flutter / Rust / SwiftPM / Node / Gradle / Xcode / Python / CocoaPods），
/// 再按该类型的产物清单收集可清理目录；执行时优先调用官方清理命令（flutter clean / cargo clean 等），
/// 无命令的类型对产物目录执行移入废纸篓。
enum PurgeEngine {
    /// 近期阈值：7 天内修改过的项目标记为 Recent，默认不勾选。
    static let recentWindow: TimeInterval = 7 * 86_400

    /// 遍历时跳过的目录（版本控制等，避免无意义深挖）。
    private static let skippedDirectoryNames: Set<String> = [".git", ".svn", ".hg"]

    /// 全部产物目录名（各类型并集）：walk 遇到即不深入——
    /// node_modules 内部每个子包都有 package.json，若不跳过会被误识别为独立项目。
    private static let allArtifactDirectoryNames: Set<String> = Set(ArtifactType.allCases.flatMap { $0.dirNames })

    /// 平台子目录名：即使包含构建标记（build.gradle/Podfile 等）也不算项目根——
    /// Flutter/RN 的 android、ios 等平台层应归到外层项目（项目根有 pubspec.yaml/package.json）。
    private static let platformDirectoryNames: Set<String> = ["android", "ios", "macos", "windows", "linux", "web"]

    /// 项目清单文件标记（用于识别「项目散落地」，同 ProjectType 检测文件）。
    private static let projectFileMarkers: Set<String> = {
        var markers = Set<String>()
        for type in ProjectType.allCases {
            markers.formUnion(type.detectionFiles)
        }
        return markers
    }()

    /// 默认扫描目录：仅惯例目录（Projects / GitHub / dev 等，只检查存在性）。
    /// 注意：不在这里探测桌面/文稿/下载——访问这些目录会触发完全磁盘访问权限弹窗，
    /// 探测必须延迟到用户点击「扫描」时（见 `detectProjectRoots`）。
    static var defaultRoots: [URL] {
        ["Projects", "GitHub", "dev", "Developer", "Documents/Projects"]
            .compactMap { path in
                let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
    }

    /// 探测桌面/文稿/下载等「项目散落地」中存在项目标记的目录。
    /// 访问这些目录需要完全磁盘访问权限，应在用户触发扫描时调用（不能在页面加载时探测）。
    static func detectProjectRoots(dirs: [String] = ["Desktop", "Documents", "Downloads"]) -> [URL] {
        dirs.compactMap { name in
            let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return isProjectRoot(url) ? url : nil
        }
    }

    /// 判断目录是否为「项目根」：目录自身是 *.xcodeproj / *.xcworkspace，
    /// 或直接包含项目标记（清单文件 / 工程文件），或其一层的子目录包含标记。
    /// 用于把桌面/文稿等散落地纳入默认扫描范围，并在扫描时把产物归到最近的项目层。
    static func isProjectRoot(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") { return true }
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(atPath: url.path) else { return false }
        if children.contains(where: {
            projectFileMarkers.contains($0)
                || $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace")
        }) {
            return true
        }
        for child in children {
            let childURL = url.appendingPathComponent(child)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            guard let sub = try? fileManager.contentsOfDirectory(atPath: childURL.path) else { continue }
            if sub.contains(where: {
                projectFileMarkers.contains($0)
                    || $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace")
            }) {
                return true
            }
        }
        return false
    }

    // MARK: - 扫描

    /// 扫描多个目录，返回按大小降序的项目级清理候选。
    static func scan(roots: [URL], maxDepth: Int = 6, onProgress: ((String) -> Void)? = nil) -> [PurgeCandidate] {
        var candidates: [PurgeCandidate] = []
        let fileManager = FileManager.default
        let recentThreshold = Date().addingTimeInterval(-recentWindow)

        func addCandidate(for projectURL: URL, fallbackProjectName: String) {
            let type = ProjectType.detect(in: projectURL)
            var artifacts: [PurgeArtifact] = []
            collectArtifacts(
                in: projectURL, type: type, projectRoot: projectURL,
                depth: 0, into: &artifacts
            )
            guard !artifacts.isEmpty else { return }
            let totalSize = artifacts.reduce(0) { $0 + $1.size }
            let fileCount = artifacts.reduce(0) { $0 + $1.fileCount }
            let modificationDate = (try? fileManager.attributesOfItem(atPath: projectURL.path)[.modificationDate] as? Date) ?? .distantPast
            candidates.append(PurgeCandidate(
                projectURL: projectURL,
                projectName: projectURL.lastPathComponent.isEmpty ? fallbackProjectName : projectURL.lastPathComponent,
                type: type,
                artifacts: artifacts,
                totalSize: totalSize,
                fileCount: fileCount,
                isRecent: modificationDate > recentThreshold
            ))
        }

        /// 收集项目根下的类型化产物。遇到嵌套项目根（monorepo 子项目）跳过其子树——产物归嵌套项目。
        func collectArtifacts(
            in url: URL, type: ProjectType, projectRoot: URL,
            depth: Int, into artifacts: inout [PurgeArtifact]
        ) {
            if Task.isCancelled { return }
            guard depth <= 8 else { return }
            // 平台子目录（android/ios/...）即使含构建标记也不算嵌套项目，继续收集
            if url != projectRoot, !platformDirectoryNames.contains(url.lastPathComponent), isProjectRoot(url) { return }
            guard let children = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: []
            ) else { return }
            for child in children {
                guard let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                ) else { continue }
                if values.isSymbolicLink == true { continue }
                guard values.isDirectory == true else { continue }
                let name = child.lastPathComponent
                if skippedDirectoryNames.contains(name) { continue }
                if type.artifactDirNames.contains(name) {
                    let scan = DiskScanner.scan(
                        root: child,
                        options: DiskScanner.Options(collectLargeFiles: false, skipHiddenFiles: false)
                    )
                    artifacts.append(PurgeArtifact(
                        url: child,
                        name: name,
                        size: scan.root.size,
                        fileCount: scan.root.fileCount
                    ))
                    // 不深入产物目录内部
                } else {
                    collectArtifacts(in: child, type: type, projectRoot: projectRoot, depth: depth + 1, into: &artifacts)
                }
            }
        }

        /// 主遍历：识别项目根并生成候选，继续深入以发现嵌套项目。
        /// 注意：不能基于字符串偏移计算相对路径——/var 是 /private/var 的符号链接，
        /// 扫描根与子目录 URL 的前缀可能不一致。
        func walk(_ url: URL, depth: Int, projectName: String) {
            if Task.isCancelled || depth > maxDepth { return }
            onProgress?(url.path)
            let isPlatform = platformDirectoryNames.contains(url.lastPathComponent)
            let effectiveProjectName = !isPlatform && isProjectRoot(url)
                ? url.lastPathComponent
                : projectName
            guard let children = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ) else { return }
            for child in children {
                guard let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                ) else { continue }
                if values.isSymbolicLink == true { continue }
                guard values.isDirectory == true else { continue }
                let name = child.lastPathComponent
                if skippedDirectoryNames.contains(name) { continue }
                // 产物目录不深入（node_modules 内部是海量子包，不是项目）
                if allArtifactDirectoryNames.contains(name) { continue }
                if !platformDirectoryNames.contains(name), isProjectRoot(child) {
                    // 项目根：生成候选，并深入以发现嵌套子项目
                    addCandidate(for: child, fallbackProjectName: effectiveProjectName)
                    walk(child, depth: depth + 1, projectName: child.lastPathComponent)
                } else {
                    walk(child, depth: depth + 1, projectName: effectiveProjectName)
                }
            }
        }

        for root in roots {
            if isProjectRoot(root) {
                addCandidate(for: root, fallbackProjectName: root.lastPathComponent)
            }
            walk(root, depth: 0, projectName: root.lastPathComponent)
        }
        candidates.sort { $0.totalSize > $1.totalSize }
        return candidates
    }

    // MARK: - 清理

    struct CleanOutcome {
        var commandSucceeded: Int = 0
        var trashed: Int = 0
        var failures: [String] = []
    }

    /// 执行清理：有官方命令的类型运行命令（如 flutter clean），其余对产物目录移入废纸篓。
    /// 命令失败不会抛错，计入 failures（可能因工具未安装或权限不足）。
    /// onProgress 每处理一个候选回调一次：(项目描述, 已完成数, 总数)，供 UI 显示实时进度。
    @discardableResult
    static func clean(
        candidates: [PurgeCandidate],
        onProgress: ((_ label: String, _ completed: Int, _ total: Int) -> Void)? = nil
    ) -> CleanOutcome {
        var outcome = CleanOutcome()
        let total = candidates.count
        for (index, candidate) in candidates.enumerated() {
            let command = candidate.type.cleanCommand
            let label: String
            if let command {
                label = "\(candidate.projectName)（\(command)）"
            } else {
                label = "\(candidate.projectName)（移入废纸篓）"
            }
            onProgress?(label, index + 1, total)

            if let command {
                let result = runCommand("cd \"\(candidate.projectURL.path)\" && \(command)")
                if result.success {
                    outcome.commandSucceeded += 1
                } else {
                    outcome.failures.append("\(candidate.projectName)（\(command)）：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } else {
                var moved = 0
                for artifact in candidate.artifacts {
                    guard !TrashService.isProtected(artifact.url) else { continue }
                    do {
                        try FileManager.default.trashItem(at: artifact.url, resultingItemURL: nil)
                        moved += 1
                    } catch {
                        outcome.failures.append("\(candidate.projectName)/\(artifact.name)：\(error.localizedDescription)")
                    }
                }
                outcome.trashed += moved
            }
        }
        return outcome
    }

    /// 运行 shell 命令（/bin/zsh -lc），等待结束并收集输出。命令均为内部白名单。
    static func runCommand(_ command: String, timeout: TimeInterval = 180) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (false, "无法启动命令：\(error.localizedDescription)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, output)
    }
}
