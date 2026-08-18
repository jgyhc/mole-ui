import Foundation
import SwiftUI
import Combine

/// 视图模式
enum FVMViewTab: String, CaseIterable, Identifiable {
    case versions = "已装 SDK 版本"
    case projects = "本机 Flutter 项目"

    var id: String { rawValue }
}

/// FVM 管理与清理 ViewModel
@MainActor
final class FVMViewModel: ObservableObject {
    static let shared = FVMViewModel()

    @Published var versions: [FVMInstalledVersion] = []
    @Published var allProjects: [FlutterProjectInfo] = []
    @Published var summary: FVMSummary = .init()
    @Published var selectedVersionIds: Set<String> = []

    @Published var isLoading: Bool = false
    @Published var isCleaning: Bool = false
    @Published var hasScannedOnce: Bool = false
    @Published var fvmDetectedDir: URL? = nil

    @Published var isShowingCleanConfirmation: Bool = false
    @Published var migratingVersion: FVMInstalledVersion? = nil

    @Published var selectedStatusFilter: FVMRecommendationStatus? = nil
    @Published var searchText: String = ""
    @Published var activeTab: FVMViewTab = .versions
    @Published var searchRoots: [URL] = []
    @Published var errorMessage: String? = nil

    private let searchRootsKey = "FVMScannerSearchRoots"

    private init() {
        loadSearchRoots()
    }

    // MARK: - 扫描根目录管理

    private func loadSearchRoots() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let defaultRoots = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Workspace"),
            home.appendingPathComponent("src"),
            home.appendingPathComponent("Documents")
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        if let saved = UserDefaults.standard.stringArray(forKey: searchRootsKey) {
            let urls = saved.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            self.searchRoots = urls.isEmpty ? defaultRoots : urls
        } else {
            self.searchRoots = defaultRoots
        }
    }

    private func saveSearchRoots() {
        let paths = searchRoots.map(\.path)
        UserDefaults.standard.set(paths, forKey: searchRootsKey)
    }

    func addSearchRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        if !searchRoots.contains(where: { $0.path == standardized.path }) {
            searchRoots.append(standardized)
            saveSearchRoots()
            scan()
        }
    }

    func removeSearchRoot(_ url: URL) {
        searchRoots.removeAll(where: { $0.path == url.path })
        saveSearchRoots()
        scan()
    }

    // MARK: - 过滤计算属性

    var filteredVersions: [FVMInstalledVersion] {
        versions.filter { ver in
            let matchesSearch = searchText.isEmpty ||
                ver.versionName.localizedCaseInsensitiveContains(searchText) ||
                ver.projects.contains { $0.name.localizedCaseInsensitiveContains(searchText) || $0.path.path.localizedCaseInsensitiveContains(searchText) }

            let matchesStatus = (selectedStatusFilter == nil) || (ver.status == selectedStatusFilter)

            return matchesSearch && matchesStatus
        }
    }

    var filteredProjects: [FlutterProjectInfo] {
        allProjects.filter { proj in
            searchText.isEmpty ||
                proj.name.localizedCaseInsensitiveContains(searchText) ||
                proj.path.path.localizedCaseInsensitiveContains(searchText) ||
                (proj.declaredVersion?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// 选中的待清理版本对象
    var selectedVersions: [FVMInstalledVersion] {
        versions.filter { selectedVersionIds.contains($0.id) }
    }

    /// 选中的待清理总字节数
    var selectedSizeBytes: Int64 {
        selectedVersions.reduce(0) { $0 + $1.diskSizeBytes }
    }

    // MARK: - 扫描

    func scan() {
        guard !isLoading && !isCleaning else { return }
        isLoading = true
        errorMessage = nil

        Task {
            let scanner = FVMScanner.shared
            let detectedDir = scanner.detectFVMVersionsDirectory()
            let (scannedVersions, projects, sum) = await scanner.scan(customSearchRoots: self.searchRoots.isEmpty ? nil : self.searchRoots)

            self.fvmDetectedDir = detectedDir
            self.versions = scannedVersions
            self.allProjects = projects
            self.summary = sum
            self.hasScannedOnce = true
            self.isLoading = false

            // 默认勾选所有闲置可清理的版本
            self.selectSafeVersions()
        }
    }

    // MARK: - 选择管理

    func selectSafeVersions() {
        let safeIds = versions.filter { $0.status == .safeToClean }.map(\.id)
        selectedVersionIds = Set(safeIds)
    }

    func selectAll() {
        let nonProtected = versions.filter { !$0.status.isProtected }.map(\.id)
        selectedVersionIds = Set(nonProtected)
    }

    func deselectAll() {
        selectedVersionIds.removeAll()
    }

    func toggleSelection(_ id: String) {
        if selectedVersionIds.contains(id) {
            selectedVersionIds.remove(id)
        } else {
            selectedVersionIds.insert(id)
        }
    }

    // MARK: - 清理与迁移

    func cleanSelected() {
        guard !selectedVersions.isEmpty else { return }
        isCleaning = true

        Task {
            do {
                let targets = self.selectedVersions
                try FVMCleaner.shared.cleanVersions(targets)

                // 清理成功后，从本地列表移除
                let removedIds = Set(targets.map(\.id))
                self.versions.removeAll { removedIds.contains($0.id) }
                self.selectedVersionIds.subtract(removedIds)

                // 重新核算概要
                self.summary = FVMSummary(
                    totalVersionsCount: self.versions.count,
                    totalSizeBytes: self.versions.reduce(0) { $0 + $1.diskSizeBytes },
                    cleanableVersionsCount: self.versions.filter { $0.status == .safeToClean }.count,
                    cleanableSizeBytes: self.versions.filter { $0.status == .safeToClean }.reduce(0) { $0 + $1.diskSizeBytes },
                    totalProjectsFound: self.allProjects.count
                )
            } catch {
                self.errorMessage = "清理失败：\(error.localizedDescription)"
            }
            self.isCleaning = false
        }
    }

    /// 迁移项目版本配置
    func migrateProjects(for version: FVMInstalledVersion, to targetVersion: String) {
        let fvmDir = self.fvmDetectedDir
        Task {
            for project in version.projects {
                try? FVMCleaner.shared.migrateProject(
                    project: project,
                    toVersion: targetVersion,
                    fvmVersionsDir: fvmDir
                )
            }
            // 重新扫描刷新状态
            self.scan()
        }
    }
}
