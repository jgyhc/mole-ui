import Foundation

/// Homebrew 底层服务：负责检测 brew 环境、扫描已安装软件包与元数据、执行更新与卸载等命令。
public final class BrewService: Sendable {
    public static let shared = BrewService()

    public init() {}

    // MARK: - 路径检测

    /// 候选 Homebrew 路径列表
    private static let candidateBrewPaths = [
        "/opt/homebrew/bin/brew",    // Apple Silicon 默认
        "/usr/local/bin/brew",       // Intel 默认
        "\(NSHomeDirectory())/.homebrew/bin/brew",
        "/opt/boxen/homebrew/bin/brew"
    ]

    /// 探测可用的 brew 可执行文件路径
    public func locateBrewBinary() -> String? {
        let fm = FileManager.default
        for path in Self.candidateBrewPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        // 尝试从 PATH 中寻找
        let (code, output) = runCommandSync(executable: "/usr/bin/which", arguments: ["brew"])
        if code == 0 {
            let found = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !found.isEmpty && fm.isExecutableFile(atPath: found) {
                return found
            }
        }
        return nil
    }

    /// 当前系统是否已安装 Homebrew
    public var isInstalled: Bool {
        locateBrewBinary() != nil
    }

    // MARK: - 环境信息获取

    /// 获取 Homebrew 基本环境信息（版本号、安装前缀、Cellar 路径等）
    public func fetchEnvironment() -> (version: String?, prefix: String?, cellar: String?, caskroom: String?) {
        guard let brew = locateBrewBinary() else {
            return (nil, nil, nil, nil)
        }

        let (_, verOut) = runCommandSync(executable: brew, arguments: ["--version"])
        let firstVerLine = verOut.split(separator: "\n").first.map(String.init)

        let (_, prefixOut) = runCommandSync(executable: brew, arguments: ["--prefix"])
        let prefix = prefixOut.trimmingCharacters(in: .whitespacesAndNewlines)

        let (_, cellarOut) = runCommandSync(executable: brew, arguments: ["--cellar"])
        let cellar = cellarOut.trimmingCharacters(in: .whitespacesAndNewlines)

        let (_, caskroomOut) = runCommandSync(executable: brew, arguments: ["--caskroom"])
        let caskroom = caskroomOut.trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            firstVerLine,
            prefix.isEmpty ? nil : prefix,
            cellar.isEmpty ? nil : cellar,
            caskroom.isEmpty ? nil : caskroom
        )
    }

    // MARK: - 软件包全量扫描

    /// 扫描所有已安装的 Homebrew Formulae 和 Casks
    public func scanInstalledPackages() async throws -> (packages: [BrewPackage], summary: BrewSummary) {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }

        let env = fetchEnvironment()
        let prefixURL = env.prefix.map { URL(fileURLWithPath: $0) }
        let cellarURL = env.cellar.map { URL(fileURLWithPath: $0) } ?? prefixURL?.appendingPathComponent("Cellar")
        let caskroomURL = env.caskroom.map { URL(fileURLWithPath: $0) } ?? prefixURL?.appendingPathComponent("Caskroom")

        // 1. 获取全量已安装信息 (brew info --json=v2 --installed)
        let infoResult = await runProcessAsync(executable: brew, arguments: ["info", "--json=v2", "--installed"])
        guard infoResult.exitCode == 0 else {
            throw BrewError.commandFailed(message: "无法获取已安装软件信息：\(infoResult.output)")
        }

        // 2. 获取过期更新信息 (brew outdated --json=v2)
        let outdatedResult = await runProcessAsync(executable: brew, arguments: ["outdated", "--json=v2"])
        let outdatedMap = parseOutdatedJSON(outdatedResult.output)

        // 3. 解析 Info JSON
        guard let data = infoResult.output.data(using: .utf8) else {
            throw BrewError.parseError(message: "输出无法转换为 UTF-8 数据")
        }

        let parsedPackages = parseBrewInfoJSON(
            data: data,
            outdatedMap: outdatedMap,
            cellarURL: cellarURL,
            caskroomURL: caskroomURL
        )

        // 4. 构建反向依赖映射 (usedBy)
        var usedByMap: [String: Set<String>] = [:]
        for pkg in parsedPackages where pkg.type == .formula {
            for dep in pkg.dependencies {
                let depKey = dep.contains("/") ? (dep.components(separatedBy: "/").last ?? dep) : dep
                usedByMap[depKey, default: []].insert(pkg.name)
                usedByMap[dep, default: []].insert(pkg.name)
            }
        }

        // 5. 组合并计算汇总
        var finalPackages: [BrewPackage] = []
        var totalSize: Int64 = 0
        var formulaCount = 0
        var caskCount = 0
        var outdatedCount = 0
        var pinnedCount = 0

        for var pkg in parsedPackages {
            let directName = pkg.name
            let fullName = pkg.fullName
            var usedBy = usedByMap[directName] ?? []
            if let byFull = usedByMap[fullName] {
                usedBy.formUnion(byFull)
            }
            usedBy.remove(pkg.name) // 排除自身
            pkg.usedBy = Array(usedBy).sorted()

            if pkg.type == .formula {
                formulaCount += 1
            } else {
                caskCount += 1
            }

            if pkg.isOutdated {
                outdatedCount += 1
            }
            if pkg.isPinned {
                pinnedCount += 1
            }

            totalSize += pkg.diskSizeBytes
            finalPackages.append(pkg)
        }

        // 默认按名称排序
        finalPackages.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let summary = BrewSummary(
            totalPackagesCount: finalPackages.count,
            formulaeCount: formulaCount,
            casksCount: caskCount,
            outdatedCount: outdatedCount,
            pinnedCount: pinnedCount,
            totalSizeBytes: totalSize,
            homebrewVersion: env.version,
            homebrewPrefix: env.prefix
        )

        return (finalPackages, summary)
    }

    // MARK: - JSON 解析核心

    /// 解析 `brew outdated --json=v2` 输出，提取最新版本映射
    public func parseOutdatedJSON(_ jsonString: String) -> [String: (currentVersion: String, pinned: Bool)] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var map: [String: (currentVersion: String, pinned: Bool)] = [:]

        // Formulae
        if let formulae = json["formulae"] as? [[String: Any]] {
            for item in formulae {
                if let name = item["name"] as? String,
                   let curVer = item["current_version"] as? String {
                    let pinned = item["pinned"] as? Bool ?? false
                    map[name] = (curVer, pinned)
                }
            }
        }

        // Casks
        if let casks = json["casks"] as? [[String: Any]] {
            for item in casks {
                let name = (item["name"] as? String) ?? (item["token"] as? String)
                if let name, let curVer = item["current_version"] as? String {
                    map[name] = (curVer, false)
                }
            }
        }

        return map
    }

    /// 解析 `brew info --json=v2 --installed`
    public func parseBrewInfoJSON(
        data: Data,
        outdatedMap: [String: (currentVersion: String, pinned: Bool)],
        cellarURL: URL?,
        caskroomURL: URL?
    ) -> [BrewPackage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var packages: [BrewPackage] = []
        let fm = FileManager.default

        // 1. 解析 Formulae
        if let formulae = root["formulae"] as? [[String: Any]] {
            for f in formulae {
                guard let name = f["name"] as? String else { continue }
                let fullName = (f["full_name"] as? String) ?? name
                let tap = f["tap"] as? String
                let desc = f["desc"] as? String
                let homepage = f["homepage"] as? String
                let license = f["license"] as? String
                let kegOnly = f["keg_only"] as? Bool ?? false
                let pinnedFlag = f["pinned"] as? Bool ?? false
                let caveats = f["caveats"] as? String

                // 最新可用版本
                var latestVersion: String? = nil
                if let versions = f["versions"] as? [String: Any], let stable = versions["stable"] as? String {
                    latestVersion = stable
                }

                // 依赖
                let deps = (f["dependencies"] as? [String]) ?? []
                let buildDeps = (f["build_dependencies"] as? [String]) ?? []

                // 安装信息
                var installedVer: String? = nil
                var installedTime: Date? = nil
                var isRequested = false
                var formulaDirSize: Int64 = 0

                if let installedList = f["installed"] as? [[String: Any]], let firstInst = installedList.first {
                    installedVer = firstInst["version"] as? String
                    if let timeSec = firstInst["time"] as? Double {
                        installedTime = Date(timeIntervalSince1970: timeSec)
                    } else if let timeInt = firstInst["time"] as? Int64 {
                        installedTime = Date(timeIntervalSince1970: Double(timeInt))
                    }
                    isRequested = firstInst["installed_on_request"] as? Bool ?? false
                }

                // 检查是否过期或锁定
                let isOutdatedFromInfo = f["outdated"] as? Bool ?? false
                let outdatedInfo = outdatedMap[name] ?? outdatedMap[fullName]
                let isOutdated = isOutdatedFromInfo || (outdatedInfo != nil)
                let isPinned = pinnedFlag || (outdatedInfo?.pinned ?? false)

                if let outCur = outdatedInfo?.currentVersion {
                    latestVersion = outCur
                }

                // 计算 Cellar 大小与路径
                var installPath: URL? = nil
                if let cellarURL {
                    let fCellar = cellarURL.appendingPathComponent(name)
                    if fm.fileExists(atPath: fCellar.path) {
                        installPath = fCellar
                        formulaDirSize = calculateDirectorySize(at: fCellar)
                    }
                }

                let reason: BrewInstallReason = isRequested ? .requested : .dependency

                let pkg = BrewPackage(
                    name: name,
                    fullName: fullName,
                    token: nil,
                    displayName: name,
                    type: .formula,
                    tap: tap,
                    desc: desc,
                    homepage: homepage,
                    license: license,
                    installedVersion: installedVer,
                    currentVersion: latestVersion,
                    isOutdated: isOutdated,
                    isPinned: isPinned,
                    isAutoUpdates: false,
                    isKegOnly: kegOnly,
                    installReason: reason,
                    installedTime: installedTime,
                    diskSizeBytes: formulaDirSize,
                    dependencies: deps,
                    buildDependencies: buildDeps,
                    usedBy: [],
                    caveats: caveats,
                    artifacts: [],
                    path: installPath
                )
                packages.append(pkg)
            }
        }

        // 2. 解析 Casks
        if let casks = root["casks"] as? [[String: Any]] {
            for c in casks {
                let token = (c["token"] as? String) ?? ""
                guard !token.isEmpty else { continue }
                let fullToken = (c["full_token"] as? String) ?? token
                let tap = c["tap"] as? String
                let desc = c["desc"] as? String
                let homepage = c["homepage"] as? String
                let autoUpdates = c["auto_updates"] as? Bool ?? false
                let caveats = c["caveats"] as? String

                // 显示名 (Cask name 可能是数组)
                var displayName = token
                if let names = c["name"] as? [String], let first = names.first, !first.isEmpty {
                    displayName = first
                }

                // 版本
                let curVer = c["version"] as? String
                var instVer: String? = nil
                if let inst = c["installed"] as? String {
                    instVer = inst
                }

                var installedTime: Date? = nil
                if let timeSec = c["installed_time"] as? Double {
                    installedTime = Date(timeIntervalSince1970: timeSec)
                } else if let timeInt = c["installed_time"] as? Int64 {
                    installedTime = Date(timeIntervalSince1970: Double(timeInt))
                }

                // 提取 artifacts (app, binary, font 等路径)
                var artifactPaths: [String] = []
                var mainAppPath: URL? = nil

                if let artArray = c["artifacts"] as? [[String: Any]] {
                    for art in artArray {
                        if let appNames = art["app"] as? [String] {
                            for aName in appNames {
                                let target = "/Applications/\(aName)"
                                artifactPaths.append(target)
                                if mainAppPath == nil && fm.fileExists(atPath: target) {
                                    mainAppPath = URL(fileURLWithPath: target)
                                }
                            }
                        }
                        if let target = art["target"] as? String {
                            artifactPaths.append(target)
                            if mainAppPath == nil && target.hasSuffix(".app") && fm.fileExists(atPath: target) {
                                mainAppPath = URL(fileURLWithPath: target)
                            }
                        }
                    }
                }

                // 计算 Cask 占用空间
                var caskSize: Int64 = 0
                var installDir: URL? = nil

                if let caskroomURL {
                    let cDir = caskroomURL.appendingPathComponent(token)
                    if fm.fileExists(atPath: cDir.path) {
                        installDir = cDir
                        caskSize += calculateDirectorySize(at: cDir)
                    }
                }

                if let appURL = mainAppPath {
                    caskSize += calculateDirectorySize(at: appURL)
                }

                let isOutdatedFromInfo = c["outdated"] as? Bool ?? false
                let outdatedInfo = outdatedMap[token] ?? outdatedMap[fullToken]
                let isOutdated = isOutdatedFromInfo || (outdatedInfo != nil)

                let pkg = BrewPackage(
                    name: token,
                    fullName: fullToken,
                    token: token,
                    displayName: displayName,
                    type: .cask,
                    tap: tap,
                    desc: desc,
                    homepage: homepage,
                    license: nil,
                    installedVersion: instVer,
                    currentVersion: curVer,
                    isOutdated: isOutdated,
                    isPinned: false,
                    isAutoUpdates: autoUpdates,
                    isKegOnly: false,
                    installReason: .requested,
                    installedTime: installedTime,
                    diskSizeBytes: caskSize,
                    dependencies: [],
                    buildDependencies: [],
                    usedBy: [],
                    caveats: caveats,
                    artifacts: Array(Set(artifactPaths)).sorted(),
                    path: mainAppPath ?? installDir
                )
                packages.append(pkg)
            }
        }

        return packages
    }

    // MARK: - 软件包操作（更新、卸载、锁定等）

    /// 更新单个软件包
    public func upgrade(package: BrewPackage, onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }

        OperationLog.append(module: "homebrew", "开始更新 \(package.type.shortTitle): \(package.name)")

        let args: [String]
        if package.type == .cask {
            args = ["upgrade", "--cask", package.token ?? package.name]
        } else {
            args = ["upgrade", package.name]
        }

        let result = await runStreamingProcessAsync(executable: brew, arguments: args, onOutput: onOutput)
        if result.exitCode != 0 {
            OperationLog.append(module: "homebrew", "更新失败 \(package.name): 退出码 \(result.exitCode)")
            throw BrewError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "homebrew", "成功更新 \(package.name)")
    }

    /// 一键更新全部可用更新
    public func upgradeAll(onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }

        OperationLog.append(module: "homebrew", "开始一键更新所有 Homebrew 软件包")
        let result = await runStreamingProcessAsync(executable: brew, arguments: ["upgrade"], onOutput: onOutput)
        if result.exitCode != 0 {
            OperationLog.append(module: "homebrew", "全部更新失败: 退出码 \(result.exitCode)")
            throw BrewError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "homebrew", "成功完成全部更新")
    }

    /// 卸载单个软件包
    public func uninstall(package: BrewPackage, zap: Bool = false, onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }

        OperationLog.append(module: "homebrew", "开始卸载 \(package.type.shortTitle): \(package.name) (zap: \(zap))")

        var args = ["uninstall"]
        if zap && package.type == .cask {
            args.append("--zap")
        }
        if package.type == .cask {
            args.append("--cask")
            args.append(package.token ?? package.name)
        } else {
            args.append(package.name)
        }

        let result = await runStreamingProcessAsync(executable: brew, arguments: args, onOutput: onOutput)
        if result.exitCode != 0 {
            OperationLog.append(module: "homebrew", "卸载失败 \(package.name): 退出码 \(result.exitCode)")
            throw BrewError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "homebrew", "成功卸载 \(package.name)")
    }

    /// 锁定版本 (brew pin)
    public func pin(package: BrewPackage) async throws {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }
        guard package.type == .formula else {
            throw BrewError.unsupportedOperation(message: "Cask 不支持版本锁定 (pin)")
        }

        let result = await runProcessAsync(executable: brew, arguments: ["pin", package.name])
        if result.exitCode != 0 {
            throw BrewError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "homebrew", "已锁定版本: \(package.name)")
    }

    /// 解除锁定 (brew unpin)
    public func unpin(package: BrewPackage) async throws {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }
        guard package.type == .formula else {
            throw BrewError.unsupportedOperation(message: "Cask 不支持版本锁定 (pin)")
        }

        let result = await runProcessAsync(executable: brew, arguments: ["unpin", package.name])
        if result.exitCode != 0 {
            throw BrewError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "homebrew", "已解除锁定: \(package.name)")
    }

    /// 执行 Homebrew 索引更新 (brew update)
    public func updateBrew(onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }

        OperationLog.append(module: "homebrew", "开始更新 Homebrew 仓库索引 (brew update)")
        let result = await runStreamingProcessAsync(executable: brew, arguments: ["update"], onOutput: onOutput)
        if result.exitCode != 0 {
            throw BrewError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "homebrew", "Homebrew 索引更新完成")
    }

    /// 执行 Homebrew 缓存与旧版本清理 (brew cleanup)
    public func cleanup(onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = locateBrewBinary() else {
            throw BrewError.brewNotFound
        }

        OperationLog.append(module: "homebrew", "开始执行 brew cleanup")
        let result = await runStreamingProcessAsync(executable: brew, arguments: ["cleanup", "-s", "--prune=all"], onOutput: onOutput)
        if result.exitCode != 0 {
            throw BrewError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "homebrew", "brew cleanup 完成")
    }

    // MARK: - 工具与进程辅助

    /// 同步快速执行轻量命令
    private func runCommandSync(executable: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // 继承环境变量并确保 /opt/homebrew/bin 和 /usr/local/bin 在 PATH 中
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = env

        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let outStr = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, outStr)
    }

    /// 异步执行进程并收集完整输出
    private func runProcessAsync(executable: String, arguments: [String]) async -> (exitCode: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let res = self.runCommandSync(executable: executable, arguments: arguments)
                continuation.resume(returning: res)
            }
        }
    }

    /// 异步执行进程并实时流式回调输出
    private func runStreamingProcessAsync(
        executable: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> (exitCode: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                var env = ProcessInfo.processInfo.environment
                let currentPath = env["PATH"] ?? ""
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
                env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
                env["HOMEBREW_COLOR"] = "1"
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                var fullOutput = ""
                let outLock = NSLock()

                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { fileHandle in
                    let chunk = fileHandle.availableData
                    guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
                    outLock.lock()
                    fullOutput += text
                    outLock.unlock()
                    onOutput(text)
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    handle.readabilityHandler = nil
                    // 读取剩余数据
                    let remaining = handle.readDataToEndOfFile()
                    if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                        outLock.lock()
                        fullOutput += text
                        outLock.unlock()
                        onOutput(text)
                    }
                    continuation.resume(returning: (process.terminationStatus, fullOutput))
                } catch {
                    handle.readabilityHandler = nil
                    let err = "启动进程失败：\(error.localizedDescription)"
                    onOutput(err)
                    continuation.resume(returning: (-1, err))
                }
            }
        }
    }

    /// 递归计算指定目录的物理占用大小
    public func calculateDirectorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else {
                continue
            }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, let sz = values.fileSize {
                total += Int64(sz)
            }
        }
        return total
    }
}

// MARK: - 错误类型

public enum BrewError: LocalizedError, Sendable {
    case brewNotFound
    case commandFailed(message: String)
    case parseError(message: String)
    case unsupportedOperation(message: String)

    public var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "未检测到已安装的 Homebrew。请确认 brew 是否已正确安装并在环境变量中。"
        case .commandFailed(let message):
            return "Homebrew 操作执行失败：\n\(message)"
        case .parseError(let message):
            return "解析 Homebrew 数据失败：\(message)"
        case .unsupportedOperation(let message):
            return message
        }
    }
}
