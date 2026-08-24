import Foundation

/// 扫描到的 Node 全局环境根目录描述
public struct NodeGlobalRootDescriptor: Sendable, Hashable {
    public let path: String
    public let manager: NodePackageManagerType
    public let environmentName: String
    public let isActive: Bool
    public let managerBinPath: String?
}

/// Node 软件包服务：负责全面探测系统及多版本管理器下的 npm 与 pnpm 全局软件包、读取元数据、检查可用更新、执行更新与卸载等。
public final class NodePackageService: Sendable {
    public static let shared = NodePackageService()

    public init() {}

    // MARK: - 终端用户环境解析

    /// 从用户的交互式登录 shell 中解析环境变量与活跃路径
    public func fetchShellActiveEnvironment() -> (
        nodeBin: String?,
        npmBin: String?,
        pnpmBin: String?,
        npmRoot: String?,
        pnpmRoot: String?,
        nodeVer: String?,
        npmVer: String?,
        pnpmVer: String?,
        shellPath: String?
    ) {
        let shellScript = "echo '__MOLE_SPLIT__'; which node 2>/dev/null; which npm 2>/dev/null; which pnpm 2>/dev/null; npm root -g 2>/dev/null; pnpm root -g 2>/dev/null; node -v 2>/dev/null; npm -v 2>/dev/null; pnpm -v 2>/dev/null; echo $PATH"

        let (code, output) = runCommandSync(executable: "/bin/zsh", arguments: ["-ilc", shellScript])
        guard code == 0, output.contains("__MOLE_SPLIT__") else {
            return (nil, nil, nil, nil, nil, nil, nil, nil, nil)
        }

        let parts = output.components(separatedBy: "__MOLE_SPLIT__")
        guard let payload = parts.last else {
            return (nil, nil, nil, nil, nil, nil, nil, nil, nil)
        }

        let lines = payload.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var nodeBin: String?
        var npmBin: String?
        var pnpmBin: String?
        var npmRoot: String?
        var pnpmRoot: String?
        var nodeVer: String?
        var npmVer: String?
        var pnpmVer: String?
        var shellPath: String?

        for line in lines {
            if line.hasPrefix("/") && line.hasSuffix("/node") && nodeBin == nil {
                nodeBin = line
            } else if line.hasPrefix("/") && line.hasSuffix("/npm") && npmBin == nil {
                npmBin = line
            } else if line.hasPrefix("/") && line.hasSuffix("/pnpm") && pnpmBin == nil {
                pnpmBin = line
            } else if line.hasPrefix("/") && line.contains("node_modules") {
                if line.contains("pnpm") && pnpmRoot == nil {
                    pnpmRoot = line
                } else if npmRoot == nil {
                    npmRoot = line
                }
            } else if line.hasPrefix("v") && nodeVer == nil && line.split(separator: ".").count >= 2 {
                nodeVer = line
            } else if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: String(line.prefix(1)))) && line.split(separator: ".").count >= 2 {
                if npmVer == nil {
                    npmVer = line
                } else if pnpmVer == nil {
                    pnpmVer = line
                }
            } else if line.contains(":") && line.contains("/bin") && shellPath == nil {
                shellPath = line
            }
        }

        return (nodeBin, npmBin, pnpmBin, npmRoot, pnpmRoot, nodeVer, npmVer, pnpmVer, shellPath)
    }

    // MARK: - 综合发现所有 Node/npm/pnpm 全局目录

    public func discoverAllGlobalRoots() -> [NodeGlobalRootDescriptor] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var results: [NodeGlobalRootDescriptor] = []
        var scannedPaths: Set<String> = []

        let shellEnv = fetchShellActiveEnvironment()

        // 1. 用户当前活跃的 npm root
        if let activeNpmRoot = shellEnv.npmRoot, fm.fileExists(atPath: activeNpmRoot) {
            let standardPath = URL(fileURLWithPath: activeNpmRoot).standardized.path
            if !scannedPaths.contains(standardPath) {
                scannedPaths.insert(standardPath)
                var envName = "默认环境"
                if activeNpmRoot.contains(".nvm/versions/node/") {
                    let ver = activeNpmRoot.components(separatedBy: ".nvm/versions/node/").last?.components(separatedBy: "/").first ?? "nvm"
                    envName = "NVM (\(ver))"
                } else if activeNpmRoot.contains("/opt/homebrew") {
                    envName = "Homebrew"
                } else if activeNpmRoot.contains("/usr/local") {
                    envName = "系统全局"
                }
                results.append(NodeGlobalRootDescriptor(
                    path: standardPath,
                    manager: .npm,
                    environmentName: "\(envName) · 活跃",
                    isActive: true,
                    managerBinPath: shellEnv.npmBin
                ))
            }
        }

        // 2. 扫描 NVM 下所有安装的 Node 版本
        let nvmVersionsDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmVersionsDir) {
            for ver in versions {
                if ver.hasPrefix(".") { continue }
                let libPath = "\(nvmVersionsDir)/\(ver)/lib/node_modules"
                let binPath = "\(nvmVersionsDir)/\(ver)/bin/npm"
                let standardPath = URL(fileURLWithPath: libPath).standardized.path
                if fm.fileExists(atPath: libPath) && !scannedPaths.contains(standardPath) {
                    scannedPaths.insert(standardPath)
                    results.append(NodeGlobalRootDescriptor(
                        path: standardPath,
                        manager: .npm,
                        environmentName: "NVM (\(ver))",
                        isActive: false,
                        managerBinPath: fm.isExecutableFile(atPath: binPath) ? binPath : shellEnv.npmBin
                    ))
                }
            }
        }

        // 3. 扫描 FNM 下的安装
        let fnmDirs = [
            "\(home)/.local/share/fnm/current/lib/node_modules",
            "\(home)/.fnm/current/lib/node_modules"
        ]
        for fnmDir in fnmDirs {
            let standardPath = URL(fileURLWithPath: fnmDir).standardized.path
            if fm.fileExists(atPath: fnmDir) && !scannedPaths.contains(standardPath) {
                scannedPaths.insert(standardPath)
                results.append(NodeGlobalRootDescriptor(
                    path: standardPath,
                    manager: .npm,
                    environmentName: "FNM",
                    isActive: false,
                    managerBinPath: shellEnv.npmBin
                ))
            }
        }

        // 4. 扫描 Homebrew (Apple Silicon)
        let brewNpmLib = "/opt/homebrew/lib/node_modules"
        let standardBrewPath = URL(fileURLWithPath: brewNpmLib).standardized.path
        if fm.fileExists(atPath: brewNpmLib) && !scannedPaths.contains(standardBrewPath) {
            scannedPaths.insert(standardBrewPath)
            results.append(NodeGlobalRootDescriptor(
                path: standardBrewPath,
                manager: .npm,
                environmentName: "Homebrew",
                isActive: false,
                managerBinPath: "/opt/homebrew/bin/npm"
            ))
        }

        // 5. 扫描 /usr/local/lib/node_modules (Intel / 系统)
        let usrLocalNpmLib = "/usr/local/lib/node_modules"
        let standardUsrLocalPath = URL(fileURLWithPath: usrLocalNpmLib).standardized.path
        if fm.fileExists(atPath: usrLocalNpmLib) && !scannedPaths.contains(standardUsrLocalPath) {
            scannedPaths.insert(standardUsrLocalPath)
            results.append(NodeGlobalRootDescriptor(
                path: standardUsrLocalPath,
                manager: .npm,
                environmentName: "系统全局",
                isActive: false,
                managerBinPath: "/usr/local/bin/npm"
            ))
        }

        // 6. 扫描自定义 ~/.npm-global
        let customNpmLib = "\(home)/.npm-global/lib/node_modules"
        let standardCustomPath = URL(fileURLWithPath: customNpmLib).standardized.path
        if fm.fileExists(atPath: customNpmLib) && !scannedPaths.contains(standardCustomPath) {
            scannedPaths.insert(standardCustomPath)
            results.append(NodeGlobalRootDescriptor(
                path: standardCustomPath,
                manager: .npm,
                environmentName: "npm 用户目录",
                isActive: false,
                managerBinPath: "\(home)/.npm-global/bin/npm"
            ))
        }

        // 7. 扫描 pnpm 全局目录
        var pnpmCandidateRoots = [
            "\(home)/Library/pnpm/global/5/node_modules",
            "\(home)/Library/pnpm/global/node_modules",
            "\(home)/.local/share/pnpm/global/5/node_modules",
            "\(home)/.local/share/pnpm/global/node_modules",
            "\(home)/.pnpm-global/node_modules"
        ]
        if let pnpmRoot = shellEnv.pnpmRoot {
            pnpmCandidateRoots.insert(pnpmRoot, at: 0)
        }

        for pnpmPath in pnpmCandidateRoots {
            let standardPnpmPath = URL(fileURLWithPath: pnpmPath).standardized.path
            if fm.fileExists(atPath: pnpmPath) && !scannedPaths.contains(standardPnpmPath) {
                scannedPaths.insert(standardPnpmPath)
                results.append(NodeGlobalRootDescriptor(
                    path: standardPnpmPath,
                    manager: .pnpm,
                    environmentName: "pnpm 全局",
                    isActive: true,
                    managerBinPath: shellEnv.pnpmBin ?? locateBinary(name: "pnpm")
                ))
            }
        }

        return results
    }

    // MARK: - 路径探测回退

    public func locateBinary(name: String) -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        var candidatePaths: [String] = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/Library/pnpm/\(name)",
            "\(home)/.local/share/pnpm/\(name)",
            "\(home)/.pnpm-global/bin/\(name)",
            "\(home)/.volta/bin/\(name)",
            "\(home)/.asdf/shims/\(name)",
            "\(home)/.bun/bin/\(name)"
        ]

        let nvmVersionsDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmVersionsDir) {
            let sortedVersions = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            for ver in sortedVersions {
                candidatePaths.append("\(nvmVersionsDir)/\(ver)/bin/\(name)")
            }
        }

        for path in candidatePaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        let (code, output) = runCommandSync(executable: "/usr/bin/which", arguments: [name])
        if code == 0 {
            let found = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !found.isEmpty && fm.isExecutableFile(atPath: found) {
                return found
            }
        }

        return nil
    }

    public var isAnyNodeManagerInstalled: Bool {
        !discoverAllGlobalRoots().isEmpty || locateBinary(name: "npm") != nil || locateBinary(name: "pnpm") != nil
    }

    // MARK: - 全量扫描

    public func scanInstalledPackages() async throws -> (packages: [NodePackage], summary: NodePackageSummary) {
        let shellEnv = fetchShellActiveEnvironment()
        let roots = discoverAllGlobalRoots()

        var allPackages: [NodePackage] = []
        var environmentNames: Set<String> = []

        // 1. 扫描所有发现的全局目录
        for root in roots {
            environmentNames.insert(root.environmentName)
            let scanned = scanDirectoryPackages(
                rootPath: root.path,
                manager: root.manager,
                environmentName: root.environmentName,
                isActiveEnvironment: root.isActive,
                managerBinPath: root.managerBinPath
            )
            allPackages.append(contentsOf: scanned)
        }

        // 2. 异步检查可更新状态
        let outdatedMap = await fetchOutdatedMap(shellEnv: shellEnv, roots: roots)

        var finalPackages: [NodePackage] = []
        var npmCount = 0
        var pnpmCount = 0
        var outdatedCount = 0
        var totalSize: Int64 = 0

        for var pkg in allPackages {
            if let latest = outdatedMap[pkg.name] {
                pkg.latestVersion = latest
                pkg.isOutdated = true
            }

            if pkg.manager == .npm {
                npmCount += 1
            } else {
                pnpmCount += 1
            }

            if pkg.isOutdated {
                outdatedCount += 1
            }

            totalSize += pkg.diskSizeBytes
            finalPackages.append(pkg)
        }

        finalPackages.sort {
            if $0.isActiveEnvironment != $1.isActiveEnvironment {
                return $0.isActiveEnvironment && !$1.isActiveEnvironment
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        let summary = NodePackageSummary(
            totalPackagesCount: finalPackages.count,
            npmPackagesCount: npmCount,
            pnpmPackagesCount: pnpmCount,
            outdatedCount: outdatedCount,
            totalSizeBytes: totalSize,
            activeNodeVersion: shellEnv.nodeVer,
            activeNpmVersion: shellEnv.npmVer,
            activePnpmVersion: shellEnv.pnpmVer,
            environmentNames: Array(environmentNames).sorted()
        )

        return (finalPackages, summary)
    }

    private func fetchOutdatedMap(
        shellEnv: (nodeBin: String?, npmBin: String?, pnpmBin: String?, npmRoot: String?, pnpmRoot: String?, nodeVer: String?, npmVer: String?, pnpmVer: String?, shellPath: String?),
        roots: [NodeGlobalRootDescriptor]
    ) async -> [String: String] {
        var map: [String: String] = [:]

        // 使用活跃的 npm 运行 outdated
        if let npmBin = shellEnv.npmBin ?? roots.first(where: { $0.manager == .npm })?.managerBinPath {
            let (_, out) = runCommandSync(executable: npmBin, arguments: ["outdated", "-g", "--json"])
            if let parsed = parseOutdatedJSON(out) {
                map.merge(parsed) { _, new in new }
            }
        }

        return map
    }

    // MARK: - 目录扫描解析

    public func scanDirectoryPackages(
        rootPath: String,
        manager: NodePackageManagerType,
        environmentName: String = "默认环境",
        isActiveEnvironment: Bool = true,
        managerBinPath: String? = nil
    ) -> [NodePackage] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootPath) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(atPath: rootPath) else {
            return []
        }

        var packages: [NodePackage] = []

        for item in contents {
            if item.hasPrefix(".") { continue }
            let itemPath = (rootPath as NSString).appendingPathComponent(item)

            if item.hasPrefix("@") {
                if let subContents = try? fm.contentsOfDirectory(atPath: itemPath) {
                    for subItem in subContents {
                        if subItem.hasPrefix(".") { continue }
                        let pkgPath = (itemPath as NSString).appendingPathComponent(subItem)
                        let pkgURL = URL(fileURLWithPath: pkgPath)
                        let fullPkgName = "\(item)/\(subItem)"
                        if let pkg = parsePackageDirectory(
                            dirURL: pkgURL,
                            fullName: fullPkgName,
                            scope: item,
                            manager: manager,
                            environmentName: environmentName,
                            isActiveEnvironment: isActiveEnvironment,
                            managerBinPath: managerBinPath
                        ) {
                            packages.append(pkg)
                        }
                    }
                }
            } else {
                let pkgURL = URL(fileURLWithPath: itemPath)
                if let pkg = parsePackageDirectory(
                    dirURL: pkgURL,
                    fullName: item,
                    scope: nil,
                    manager: manager,
                    environmentName: environmentName,
                    isActiveEnvironment: isActiveEnvironment,
                    managerBinPath: managerBinPath
                ) {
                    packages.append(pkg)
                }
            }
        }

        return packages
    }

    public func parsePackageDirectory(
        dirURL: URL,
        fullName: String,
        scope: String?,
        manager: NodePackageManagerType,
        environmentName: String = "默认环境",
        isActiveEnvironment: Bool = true,
        managerBinPath: String? = nil
    ) -> NodePackage? {
        let packageJsonURL = dirURL.appendingPathComponent("package.json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageJsonURL.path),
              let data = try? Data(contentsOf: packageJsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let name = (json["name"] as? String) ?? fullName
        let version = (json["version"] as? String) ?? "0.0.0"
        let desc = json["description"] as? String
        let homepage = json["homepage"] as? String
        let license = json["license"] as? String

        var authorStr: String?
        if let authorObj = json["author"] as? [String: Any] {
            let aName = authorObj["name"] as? String ?? ""
            let email = authorObj["email"] as? String
            if let email, !email.isEmpty {
                authorStr = "\(aName) <\(email)>"
            } else {
                authorStr = aName
            }
        } else if let aStr = json["author"] as? String {
            authorStr = aStr
        }

        var repoURL: String?
        if let repoObj = json["repository"] as? [String: Any], let url = repoObj["url"] as? String {
            repoURL = url
        } else if let repoStr = json["repository"] as? String {
            repoURL = repoStr
        }
        if let rawRepo = repoURL {
            repoURL = normalizeRepositoryURL(rawRepo)
        }

        var binaries: [NodePackageBinary] = []
        if let binDict = json["bin"] as? [String: String] {
            for (cmd, relPath) in binDict {
                binaries.append(NodePackageBinary(command: cmd, targetPath: relPath))
            }
        } else if let binStr = json["bin"] as? String {
            let cmd = name.contains("/") ? (name.components(separatedBy: "/").last ?? name) : name
            binaries.append(NodePackageBinary(command: cmd, targetPath: binStr))
        }
        binaries.sort { $0.command < $1.command }

        var engines: [String: String] = [:]
        if let engDict = json["engines"] as? [String: String] {
            engines = engDict
        }

        var dependencies: [String: String] = [:]
        if let depDict = json["dependencies"] as? [String: String] {
            dependencies = depDict
        }

        let keywords = (json["keywords"] as? [String]) ?? []
        let diskSizeBytes = calculateDirectorySize(at: dirURL)
        let installedTime = (try? fm.attributesOfItem(atPath: dirURL.path)[.modificationDate]) as? Date

        return NodePackage(
            name: name,
            manager: manager,
            environmentName: environmentName,
            isActiveEnvironment: isActiveEnvironment,
            managerBinPath: managerBinPath,
            displayName: name,
            scope: scope,
            installedVersion: version,
            latestVersion: nil,
            isOutdated: false,
            desc: desc,
            homepage: homepage,
            repository: repoURL,
            license: license,
            author: authorStr,
            binaries: binaries,
            diskSizeBytes: diskSizeBytes,
            path: dirURL,
            installedTime: installedTime,
            engines: engines,
            dependencies: dependencies,
            keywords: keywords
        )
    }

    public func normalizeRepositoryURL(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("git+") {
            clean = String(clean.dropFirst(4))
        }
        if clean.hasPrefix("git://") {
            clean = "https://" + clean.dropFirst(6)
        }
        if clean.hasSuffix(".git") {
            clean = String(clean.dropLast(4))
        }
        if clean.hasPrefix("github:") {
            clean = "https://github.com/" + clean.dropFirst(7)
        }
        return clean
    }

    public func parseOutdatedJSON(_ jsonString: String) -> [String: String]? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return nil
        }

        var result: [String: String] = [:]
        for (pkgName, info) in json {
            if let latest = info["latest"] as? String {
                result[pkgName] = latest
            }
        }
        return result
    }

    public func fetchLatestVersion(packageName: String, usingBin: String? = nil) async -> String? {
        let bin = usingBin ?? locateBinary(name: "npm") ?? "/opt/homebrew/bin/npm"
        let (code, output) = await runProcessAsync(executable: bin, arguments: ["view", packageName, "version", "--json"])
        guard code == 0 else { return nil }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? String {
            return parsed
        }
        let clean = trimmed.replacingOccurrences(of: "\"", with: "")
        return clean.isEmpty ? nil : clean
    }

    // MARK: - 软件包操作（更新、卸载、清理缓存）

    public func upgrade(package: NodePackage, onOutput: @escaping @Sendable (String) -> Void) async throws {
        let binaryPath = package.managerBinPath ?? locateBinary(name: package.manager.rawValue)
        guard let bin = binaryPath else {
            throw NodePackageError.managerNotFound(name: package.manager.rawValue)
        }

        OperationLog.append(module: "node_packages", "开始升级 \(package.manager.title) [\(package.environmentName)]: \(package.name)")

        let args: [String]
        if package.manager == .npm {
            args = ["install", "-g", "\(package.name)@latest"]
        } else {
            args = ["add", "-g", "\(package.name)@latest"]
        }

        let result = await runStreamingProcessAsync(executable: bin, arguments: args, onOutput: onOutput)
        if result.exitCode != 0 {
            OperationLog.append(module: "node_packages", "升级失败 \(package.name): 退出码 \(result.exitCode)")
            throw NodePackageError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "node_packages", "成功升级 \(package.name)")
    }

    public func upgradeAll(packages: [NodePackage], onOutput: @escaping @Sendable (String) -> Void) async throws {
        for pkg in packages {
            onOutput("\n========================================\n")
            onOutput("==> 正在升级 \(pkg.name) [\(pkg.environmentName)]...\n")
            onOutput("========================================\n")
            try await upgrade(package: pkg, onOutput: onOutput)
        }
    }

    public func uninstall(package: NodePackage, onOutput: @escaping @Sendable (String) -> Void) async throws {
        let binaryPath = package.managerBinPath ?? locateBinary(name: package.manager.rawValue)
        guard let bin = binaryPath else {
            throw NodePackageError.managerNotFound(name: package.manager.rawValue)
        }

        OperationLog.append(module: "node_packages", "开始卸载 \(package.manager.title) [\(package.environmentName)]: \(package.name)")

        let args: [String]
        if package.manager == .npm {
            args = ["uninstall", "-g", package.name]
        } else {
            args = ["remove", "-g", package.name]
        }

        let result = await runStreamingProcessAsync(executable: bin, arguments: args, onOutput: onOutput)
        if result.exitCode != 0 {
            OperationLog.append(module: "node_packages", "卸载失败 \(package.name): 退出码 \(result.exitCode)")
            throw NodePackageError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "node_packages", "成功卸载 \(package.name)")
    }

    public func cleanCache(manager: NodePackageManagerType, onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard let bin = locateBinary(name: manager.rawValue) else {
            throw NodePackageError.managerNotFound(name: manager.rawValue)
        }

        OperationLog.append(module: "node_packages", "开始清理 \(manager.title) 缓存")

        let args: [String]
        if manager == .npm {
            args = ["cache", "clean", "--force"]
        } else {
            args = ["store", "prune"]
        }

        let result = await runStreamingProcessAsync(executable: bin, arguments: args, onOutput: onOutput)
        if result.exitCode != 0 {
            OperationLog.append(module: "node_packages", "清理 \(manager.title) 缓存失败: 退出码 \(result.exitCode)")
            throw NodePackageError.commandFailed(message: result.output)
        }
        OperationLog.append(module: "node_packages", "成功清理 \(manager.title) 缓存")
    }

    // MARK: - 辅助执行

    private func runCommandSync(executable: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let home = NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "\(home)/.nvm/versions/node/v22.19.0/bin:\(home)/Library/pnpm:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
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

    private func runProcessAsync(executable: String, arguments: [String]) async -> (exitCode: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let res = self.runCommandSync(executable: executable, arguments: arguments)
                continuation.resume(returning: res)
            }
        }
    }

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

                let home = NSHomeDirectory()
                var env = ProcessInfo.processInfo.environment
                let currentPath = env["PATH"] ?? ""
                env["PATH"] = "\(home)/.nvm/versions/node/v22.19.0/bin:\(home)/Library/pnpm:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
                env["FORCE_COLOR"] = "1"
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

public enum NodePackageError: LocalizedError, Sendable {
    case managerNotFound(name: String)
    case commandFailed(message: String)
    case parseError(message: String)

    public var errorDescription: String? {
        switch self {
        case .managerNotFound(let name):
            return "未检测到已安装的 \(name)。请确认 Node 及 \(name) 是否已正确安装并在环境变量中。"
        case .commandFailed(let message):
            return "命令执行失败：\n\(message)"
        case .parseError(let message):
            return "解析软件包数据失败：\(message)"
        }
    }
}
