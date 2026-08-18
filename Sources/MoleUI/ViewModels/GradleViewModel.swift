import Foundation
import SwiftUI
import Combine

/// Gradle 视图模式
enum GradleViewTab: String, CaseIterable, Identifiable {
    case versions = "已装 Gradle 发行版"
    case projects = "本机 Gradle 项目"

    var id: String { rawValue }
}

/// Gradle 管理与清理 ViewModel
@MainActor
final class GradleViewModel: ObservableObject {
    static let shared = GradleViewModel()

    @Published var versions: [GradleInstalledVersion] = []
    @Published var allProjects: [GradleProjectInfo] = []
    @Published var summary: GradleSummary = .init()
    @Published var selectedVersionIds: Set<String> = []

    @Published var isLoading: Bool = false
    @Published var isCleaning: Bool = false
    @Published var hasScannedOnce: Bool = false
    @Published var gradleDetectedDir: URL? = nil

    @Published var isShowingCleanConfirmation: Bool = false
    @Published var migratingVersion: GradleInstalledVersion? = nil

    @Published var selectedStatusFilter: GradleRecommendationStatus? = nil
    @Published var searchText: String = ""
    @Published var activeTab: GradleViewTab = .versions
    @Published var searchRoots: [URL] = []
    @Published var errorMessage: String? = nil

    private let searchRootsKey = "GradleScannerSearchRoots"

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

    var filteredVersions: [GradleInstalledVersion] {
        versions.filter { ver in
            let matchesSearch = searchText.isEmpty ||
                ver.versionName.localizedCaseInsensitiveContains(searchText) ||
                ver.projects.contains { $0.name.localizedCaseInsensitiveContains(searchText) || $0.path.path.localizedCaseInsensitiveContains(searchText) }

            let matchesStatus = (selectedStatusFilter == nil) || (ver.status == selectedStatusFilter)

            return matchesSearch && matchesStatus
        }
    }

    var filteredProjects: [GradleProjectInfo] {
        allProjects.filter { proj in
            searchText.isEmpty ||
                proj.name.localizedCaseInsensitiveContains(searchText) ||
                proj.path.path.localizedCaseInsensitiveContains(searchText) ||
                (proj.declaredVersion?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// 选中的待清理版本对象
    var selectedVersions: [GradleInstalledVersion] {
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
            let scanner = GradleScanner.shared
            let detectedDir = scanner.detectGradleDistsDirectory()
            let (scannedVersions, projects, sum) = await scanner.scan(customSearchRoots: self.searchRoots.isEmpty ? nil : self.searchRoots)

            self.gradleDetectedDir = detectedDir
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
                try GradleCleaner.shared.cleanVersions(targets)

                // 清理成功后，从本地列表移除
                let removedIds = Set(targets.map(\.id))
                self.versions.removeAll { removedIds.contains($0.id) }
                self.selectedVersionIds.subtract(removedIds)

                // 重新核算概要
                self.summary = GradleSummary(
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

    /// 迁移项目配置中的 Gradle 发行版
    func migrateProjects(for version: GradleInstalledVersion, to targetVersion: String) {
        Task {
            for project in version.projects {
                try? GradleCleaner.shared.migrateProject(
                    project: project,
                    toVersion: targetVersion
                )
            }
            // 重新扫描刷新状态
            self.scan()
        }
    }
}
