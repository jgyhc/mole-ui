import Foundation
import Combine
import AppKit

/// Node 软件包管理 ViewModel
@MainActor
public final class NodePackageViewModel: ObservableObject {
    public static let shared = NodePackageViewModel()

    // MARK: - 状态属性

    @Published public private(set) var packages: [NodePackage] = []
    @Published public private(set) var summary = NodePackageSummary()
    @Published public private(set) var isLoading = false
    @Published public private(set) var isCheckingUpdates = false
    @Published public private(set) var hasScannedOnce = false
    @Published public private(set) var isOperating = false
    @Published public private(set) var currentOperationTitle: String = ""
    @Published public private(set) var consoleOutput: String = ""
    @Published public var showConsoleSheet = false

    @Published public var searchText = ""
    @Published public var activeFilterTab: NodePackageFilterTab = .all
    @Published public var selectedEnvironment: String? = nil
    @Published public var sortOption: NodePackageSortOption = .name
    @Published public var selectedPackageID: String?

    @Published public var isShowingUninstallAlert = false
    @Published public var isShowingUpgradeAllAlert = false
    @Published public var pendingActionPackage: NodePackage?

    @Published public var statusMessage: String?
    @Published public var errorMessage: String?
    @Published public private(set) var isAnyNodeManagerInstalled = true

    private var scanTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private let service = NodePackageService.shared

    public init() {
        self.isAnyNodeManagerInstalled = service.isAnyNodeManagerInstalled
    }

    // MARK: - 派生计算属性

    public var filteredPackages: [NodePackage] {
        var result = packages

        // 1. Tab 筛选
        switch activeFilterTab {
        case .all:
            break
        case .npm:
            result = result.filter { $0.manager == .npm }
        case .pnpm:
            result = result.filter { $0.manager == .pnpm }
        case .outdated:
            result = result.filter { $0.isOutdated }
        case .hasBin:
            result = result.filter { $0.hasBinaries }
        }

        // 2. 环境筛选
        if let env = selectedEnvironment, !env.isEmpty && env != "全部环境" {
            result = result.filter { $0.environmentName == env }
        }

        // 2. 搜索框筛选
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { pkg in
                pkg.name.localizedCaseInsensitiveContains(query)
                    || pkg.displayName.localizedCaseInsensitiveContains(query)
                    || (pkg.desc ?? "").localizedCaseInsensitiveContains(query)
                    || (pkg.author ?? "").localizedCaseInsensitiveContains(query)
                    || (pkg.license ?? "").localizedCaseInsensitiveContains(query)
                    || pkg.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
                    || pkg.binaries.contains { $0.command.localizedCaseInsensitiveContains(query) }
            }
        }

        // 3. 排序
        switch sortOption {
        case .name:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .size:
            result.sort { $0.diskSizeBytes > $1.diskSizeBytes }
        case .installDate:
            result.sort {
                let d1 = $0.installedTime ?? Date.distantPast
                let d2 = $1.installedTime ?? Date.distantPast
                return d1 > d2
            }
        case .outdatedFirst:
            result.sort {
                if $0.isOutdated != $1.isOutdated {
                    return $0.isOutdated && !$1.isOutdated
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        return result
    }

    public var selectedPackage: NodePackage? {
        guard let id = selectedPackageID else { return nil }
        return packages.first { $0.id == id }
    }

    public var outdatedPackages: [NodePackage] {
        packages.filter { $0.isOutdated }
    }

    // MARK: - 扫描

    public func scan() {
        scanTask?.cancel()
        isLoading = true
        errorMessage = nil
        statusMessage = nil

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let exists = self.service.isAnyNodeManagerInstalled

            await MainActor.run {
                self.isAnyNodeManagerInstalled = exists
                if !exists {
                    self.isLoading = false
                    self.hasScannedOnce = true
                    self.packages = []
                    self.summary = NodePackageSummary()
                    return
                }
            }

            guard exists else { return }

            do {
                let (scannedPackages, summary) = try await self.service.scanInstalledPackages()
                let isCancelled = Task.isCancelled

                await MainActor.run {
                    self.isLoading = false
                    self.hasScannedOnce = true
                    guard !isCancelled else { return }
                    self.packages = scannedPackages
                    self.summary = summary

                    if let cur = self.selectedPackageID, scannedPackages.contains(where: { $0.id == cur }) {
                        // 保持选中
                    } else {
                        self.selectedPackageID = scannedPackages.first?.id
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.hasScannedOnce = true
                    self.errorMessage = "扫描失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 检查远端更新

    public func checkAllUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        statusMessage = "正在检查最新版本..."

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let currentPackages = await MainActor.run { self.packages }

            for pkg in currentPackages {
                if let latest = await self.service.fetchLatestVersion(packageName: pkg.name) {
                    let isOutdated = latest != pkg.installedVersion && self.isVersionNewer(latest: latest, current: pkg.installedVersion)
                    await MainActor.run {
                        if let idx = self.packages.firstIndex(where: { $0.id == pkg.id }) {
                            var p = self.packages[idx]
                            p.latestVersion = latest
                            p.isOutdated = isOutdated
                            self.packages[idx] = p
                        }
                    }
                }
            }

            await MainActor.run {
                self.isCheckingUpdates = false
                let outdatedCount = self.packages.filter { $0.isOutdated }.count
                self.summary = NodePackageSummary(
                    totalPackagesCount: self.summary.totalPackagesCount,
                    npmPackagesCount: self.summary.npmPackagesCount,
                    pnpmPackagesCount: self.summary.pnpmPackagesCount,
                    outdatedCount: outdatedCount,
                    totalSizeBytes: self.summary.totalSizeBytes,
                    activeNodeVersion: self.summary.activeNodeVersion,
                    activeNpmVersion: self.summary.activeNpmVersion,
                    activePnpmVersion: self.summary.activePnpmVersion,
                    environmentNames: self.summary.environmentNames
                )
                self.statusMessage = outdatedCount > 0 ? "检查完毕，发现 \(outdatedCount) 个软件可更新" : "检查完毕，所有软件已是最新版本"
            }
        }
    }

    nonisolated private func isVersionNewer(latest: String, current: String) -> Bool {
        if latest == current { return false }
        let lParts = latest.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        let cParts = current.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        for i in 0..<max(lParts.count, cParts.count) {
            let l = i < lParts.count ? lParts[i] : 0
            let c = i < cParts.count ? cParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return latest != current
    }

    // MARK: - 软件包选择

    public func selectPackage(_ package: NodePackage) {
        selectedPackageID = package.id
    }

    // MARK: - 操作：升级单个软件包

    public func promptUpgrade(package: NodePackage) {
        pendingActionPackage = package
        upgrade(package: package)
    }

    public func upgrade(package: NodePackage) {
        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在升级 \(package.displayName)..."
        let cmd = package.manager == .npm ? "npm install -g \(package.name)@latest" : "pnpm add -g \(package.name)@latest"
        consoleOutput = "==> 执行: \(cmd)\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.upgrade(package: package) { line in
                    Task { @MainActor in
                        self.consoleOutput += line
                    }
                }
                await MainActor.run {
                    self.consoleOutput += "\n✔ 升级成功！\n"
                    self.isOperating = false
                    self.statusMessage = "成功升级「\(package.displayName)」"
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 升级失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "升级「\(package.displayName)」失败"
                }
            }
        }
    }

    // MARK: - 操作：一键全部升级

    public func promptUpgradeAll() {
        guard !outdatedPackages.isEmpty else { return }
        isShowingUpgradeAllAlert = true
    }

    public func upgradeAll() {
        guard !isOperating else { return }
        let toUpdate = outdatedPackages
        guard !toUpdate.isEmpty else { return }

        isOperating = true
        currentOperationTitle = "正在一键升级所有软件 (\(toUpdate.count) 个)..."
        consoleOutput = "==> 开始批量更新 \(toUpdate.count) 个软件包\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.upgradeAll(packages: toUpdate) { line in
                    Task { @MainActor in
                        self.consoleOutput += line
                    }
                }
                await MainActor.run {
                    self.consoleOutput += "\n✔ 全部软件升级完成！\n"
                    self.isOperating = false
                    self.statusMessage = "所有可用更新已升级完成"
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 批量升级失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "一键升级失败"
                }
            }
        }
    }

    // MARK: - 操作：卸载

    public func promptUninstall(package: NodePackage) {
        pendingActionPackage = package
        isShowingUninstallAlert = true
    }

    public func confirmUninstall() {
        guard let package = pendingActionPackage else { return }
        pendingActionPackage = nil

        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在卸载 \(package.displayName)..."
        let cmd = package.manager == .npm ? "npm uninstall -g \(package.name)" : "pnpm remove -g \(package.name)"
        consoleOutput = "==> 执行: \(cmd)\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.uninstall(package: package) { line in
                    Task { @MainActor in
                        self.consoleOutput += line
                    }
                }
                await MainActor.run {
                    self.consoleOutput += "\n✔ 卸载成功！\n"
                    self.isOperating = false
                    self.statusMessage = "成功卸载「\(package.displayName)」"
                    self.packages.removeAll { $0.id == package.id }
                    if self.selectedPackageID == package.id {
                        self.selectedPackageID = self.packages.first?.id
                    }
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 卸载失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "卸载「\(package.displayName)」失败"
                }
            }
        }
    }

    // MARK: - 操作：清理包管理器缓存

    public func cleanCache(manager: NodePackageManagerType) {
        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在清理 \(manager.title) 缓存..."
        let cmd = manager == .npm ? "npm cache clean --force" : "pnpm store prune"
        consoleOutput = "==> 执行: \(cmd)\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.cleanCache(manager: manager) { line in
                    Task { @MainActor in
                        self.consoleOutput += line
                    }
                }
                await MainActor.run {
                    self.consoleOutput += "\n✔ \(manager.title) 缓存清理完成！\n"
                    self.isOperating = false
                    self.statusMessage = "\(manager.title) 缓存已清理"
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 清理缓存失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "清理 \(manager.title) 缓存失败"
                }
            }
        }
    }
}
