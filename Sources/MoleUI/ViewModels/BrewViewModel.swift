import Foundation
import Combine
import AppKit

/// Homebrew 软件管理 ViewModel
@MainActor
public final class BrewViewModel: ObservableObject {
    public static let shared = BrewViewModel()

    // MARK: - 状态属性

    @Published public private(set) var packages: [BrewPackage] = []
    @Published public private(set) var summary = BrewSummary()
    @Published public private(set) var isLoading = false
    @Published public private(set) var hasScannedOnce = false
    @Published public private(set) var isOperating = false
    @Published public private(set) var currentOperationTitle: String = ""
    @Published public private(set) var consoleOutput: String = ""
    @Published public var showConsoleSheet = false

    @Published public var searchText = ""
    @Published public var activeFilterTab: BrewFilterTab = .all
    @Published public var sortOption: BrewSortOption = .name
    @Published public var selectedPackageID: String?

    @Published public var isShowingUninstallAlert = false
    @Published public var isShowingUpgradeAllAlert = false
    @Published public var zapCaskDataOnUninstall = false
    @Published public var pendingActionPackage: BrewPackage?

    @Published public var statusMessage: String?
    @Published public var errorMessage: String?
    @Published public private(set) var isBrewInstalled = true

    private var scanTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private let service = BrewService.shared

    public init() {
        self.isBrewInstalled = service.isInstalled
    }

    // MARK: - 派生数据

    public var filteredPackages: [BrewPackage] {
        var result = packages

        // 1. Tab 筛选
        switch activeFilterTab {
        case .all:
            break
        case .formulae:
            result = result.filter { $0.type == .formula }
        case .casks:
            result = result.filter { $0.type == .cask }
        case .outdated:
            result = result.filter { $0.isOutdated }
        case .requested:
            result = result.filter { $0.installReason == .requested }
        case .dependencies:
            result = result.filter { $0.installReason == .dependency }
        }

        // 2. 搜索框筛选
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { pkg in
                pkg.name.localizedCaseInsensitiveContains(query)
                    || pkg.displayName.localizedCaseInsensitiveContains(query)
                    || pkg.fullName.localizedCaseInsensitiveContains(query)
                    || (pkg.desc ?? "").localizedCaseInsensitiveContains(query)
                    || (pkg.tap ?? "").localizedCaseInsensitiveContains(query)
                    || pkg.dependencies.contains { $0.localizedCaseInsensitiveContains(query) }
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

    public var selectedPackage: BrewPackage? {
        guard let id = selectedPackageID else { return nil }
        return packages.first { $0.id == id }
    }

    public var outdatedPackages: [BrewPackage] {
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
            let brewExists = self.service.isInstalled

            await MainActor.run {
                self.isBrewInstalled = brewExists
                if !brewExists {
                    self.isLoading = false
                    self.hasScannedOnce = true
                    self.packages = []
                    self.summary = BrewSummary()
                    return
                }
            }

            guard brewExists else { return }

            do {
                let (scannedPackages, summary) = try await self.service.scanInstalledPackages()
                let isCancelled = Task.isCancelled

                await MainActor.run {
                    self.isLoading = false
                    self.hasScannedOnce = true
                    guard !isCancelled else { return }
                    self.packages = scannedPackages
                    self.summary = summary

                    // 保持原选中，或者默认选中第一个
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

    // MARK: - 软件包选择与跳转

    public func selectPackage(_ package: BrewPackage) {
        selectedPackageID = package.id
    }

    /// 点击依赖跳转到对应的软件包详情
    public func selectPackage(byName name: String) {
        let cleanName = name.contains("/") ? (name.components(separatedBy: "/").last ?? name) : name
        if let found = packages.first(where: { $0.name == cleanName || $0.fullName == name || $0.token == cleanName }) {
            selectedPackageID = found.id
            // 如果不在当前 Tab 筛选中，切到全部
            if !filteredPackages.contains(where: { $0.id == found.id }) {
                activeFilterTab = .all
                searchText = ""
            }
        }
    }

    // MARK: - 操作：更新

    public func promptUpgrade(package: BrewPackage) {
        pendingActionPackage = package
        upgrade(package: package)
    }

    public func upgrade(package: BrewPackage) {
        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在更新 \(package.displayName)..."
        consoleOutput = "==> 执行: brew upgrade \(package.name)\n"
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
                    self.consoleOutput += "\n✔ 更新完成！\n"
                    self.isOperating = false
                    self.statusMessage = "成功更新「\(package.displayName)」"
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 更新失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "更新「\(package.displayName)」失败"
                }
            }
        }
    }

    public func promptUpgradeAll() {
        guard !outdatedPackages.isEmpty else { return }
        isShowingUpgradeAllAlert = true
    }

    public func upgradeAll() {
        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在一键更新所有软件 (\(outdatedPackages.count) 个)..."
        consoleOutput = "==> 执行: brew upgrade\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.upgradeAll { line in
                    Task { @MainActor in
                        self.consoleOutput += line
                    }
                }
                await MainActor.run {
                    self.consoleOutput += "\n✔ 全部更新完成！\n"
                    self.isOperating = false
                    self.statusMessage = "所有可用软件更新已完成"
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 更新失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "一键更新失败"
                }
            }
        }
    }

    // MARK: - 操作：卸载

    public func promptUninstall(package: BrewPackage) {
        pendingActionPackage = package
        zapCaskDataOnUninstall = false
        isShowingUninstallAlert = true
    }

    public func confirmUninstall() {
        guard let package = pendingActionPackage else { return }
        let zap = zapCaskDataOnUninstall && package.type == .cask
        pendingActionPackage = nil

        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在卸载 \(package.displayName)..."
        consoleOutput = "==> 执行: brew uninstall \(zap ? "--zap " : "")\(package.name)\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.uninstall(package: package, zap: zap) { line in
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

    // MARK: - 操作：锁定 / 解锁 (Pin / Unpin)

    public func togglePin(package: BrewPackage) {
        guard package.type == .formula else { return }
        let newPinned = !package.isPinned

        Task {
            do {
                if newPinned {
                    try await service.pin(package: package)
                } else {
                    try await service.unpin(package: package)
                }
                // 本地快速更新状态
                if let idx = packages.firstIndex(where: { $0.id == package.id }) {
                    let old = packages[idx]
                    packages[idx] = BrewPackage(
                        name: old.name,
                        fullName: old.fullName,
                        token: old.token,
                        displayName: old.displayName,
                        type: old.type,
                        tap: old.tap,
                        desc: old.desc,
                        homepage: old.homepage,
                        license: old.license,
                        installedVersion: old.installedVersion,
                        currentVersion: old.currentVersion,
                        isOutdated: old.isOutdated,
                        isPinned: newPinned,
                        isAutoUpdates: old.isAutoUpdates,
                        isKegOnly: old.isKegOnly,
                        installReason: old.installReason,
                        installedTime: old.installedTime,
                        diskSizeBytes: old.diskSizeBytes,
                        dependencies: old.dependencies,
                        buildDependencies: old.buildDependencies,
                        usedBy: old.usedBy,
                        caveats: old.caveats,
                        artifacts: old.artifacts,
                        path: old.path
                    )
                }
                statusMessage = newPinned ? "已锁定 \(package.name) 版本" : "已解除 \(package.name) 版本锁定"
            } catch {
                errorMessage = "锁定/解锁操作失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 操作：刷新索引 / 清理缓存

    public func updateBrewIndex() {
        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在更新 Homebrew 仓库索引 (brew update)..."
        consoleOutput = "==> 执行: brew update\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.updateBrew { line in
                    Task { @MainActor in
                        self.consoleOutput += line
                    }
                }
                await MainActor.run {
                    self.consoleOutput += "\n✔ Homebrew 索引更新完成！\n"
                    self.isOperating = false
                    self.statusMessage = "Homebrew 索引已更新"
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 索引更新失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "更新索引失败"
                }
            }
        }
    }

    public func cleanupBrew() {
        guard !isOperating else { return }
        isOperating = true
        currentOperationTitle = "正在清理 Homebrew 历史缓存与旧版本 (brew cleanup)..."
        consoleOutput = "==> 执行: brew cleanup -s --prune=all\n"
        showConsoleSheet = true
        errorMessage = nil

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.service.cleanup { line in
                    Task { @MainActor in
                        self.consoleOutput += line
                    }
                }
                await MainActor.run {
                    self.consoleOutput += "\n✔ 清理完成！\n"
                    self.isOperating = false
                    self.statusMessage = "Homebrew 缓存清理完毕"
                    self.scan()
                }
            } catch {
                await MainActor.run {
                    self.consoleOutput += "\n✖ 清理失败：\(error.localizedDescription)\n"
                    self.isOperating = false
                    self.errorMessage = "清理失败"
                }
            }
        }
    }
}
