import Foundation
import Combine
import AppKit

/// 智能卸载视图模型：应用清单扫描、选中应用关联文件扫描、安全分级选择集与卸载执行。
/// 共享单例：应用清单跨页面切换缓存（需手动点「加载应用」刷新）。
@MainActor
final class UninstallViewModel: ObservableObject {
    static let shared = UninstallViewModel()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false
    @Published private(set) var progress = AppScanProgress()
    @Published var searchText = ""
    /// 由左侧 List 直接写入选择。
    @Published var selectedAppID: InstalledApp.ID?

    @Published private(set) var associatedFiles: [AssociatedFile] = []
    @Published private(set) var isScanningDetails = false
    @Published private(set) var selectedFileIDs: Set<AssociatedFile.ID> = []
    @Published var isShowingUninstallConfirmation = false
    @Published private(set) var lastUninstallMessage: String?
    @Published var errorMessage: String?

    private var appTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    /// 已定位关联文件的应用（避免 List 选择变化时重复扫描）。
    private var lastScannedAppID: InstalledApp.ID?

    // MARK: - 派生数据

    var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var selectedApp: InstalledApp? {
        apps.first { $0.id == selectedAppID }
    }

    var selectedFiles: [AssociatedFile] {
        associatedFiles.filter { selectedFileIDs.contains($0.id) }
    }

    var selectedFilesSize: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    var totalUninstallSize: Int64 {
        (selectedApp?.size ?? 0) + selectedFilesSize
    }

    /// 选中的敏感/共享文件项
    var selectedCautionFiles: [AssociatedFile] {
        selectedFiles.filter { $0.safetyLevel == .caution }
    }

    var hasSelectedCautionFiles: Bool {
        !selectedCautionFiles.isEmpty
    }

    /// 选中应用是否正在运行（运行中禁止卸载）。
    var isSelectedAppRunning: Bool {
        guard let app = selectedApp else { return false }
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains(where: { running in
            (app.bundleIdentifier != nil && running.bundleIdentifier == app.bundleIdentifier) ||
            running.bundleURL?.standardizedFileURL.path == app.url.standardizedFileURL.path
        })
    }

    /// 按安全等级分层的关联文件
    var safetyGroups: [(level: AssociatedFileSafetyLevel, files: [AssociatedFile])] {
        AssociatedFileSafetyLevel.allCases.compactMap { level in
            let files = associatedFiles.filter { $0.safetyLevel == level }
            return files.isEmpty ? nil : (level, files)
        }
    }

    /// 按类别分组的关联文件（保持 allCases 顺序）。
    var associatedGroups: [(kind: AppAssociatedFileKind, files: [AssociatedFile])] {
        AppAssociatedFileKind.allCases.compactMap { kind in
            let files = associatedFiles.filter { $0.kind == kind }
            return files.isEmpty ? nil : (kind, files)
        }
    }

    // MARK: - 应用清单

    func loadApps() {
        appTask?.cancel()
        isLoading = true
        errorMessage = nil
        apps = []
        selectedAppID = nil
        associatedFiles = []
        selectedFileIDs = []
        lastUninstallMessage = nil

        appTask = Task.detached(priority: .userInitiated) { [weak self] in
            let apps = AppCatalog.scanInstalledApps { progress in
                DispatchQueue.main.async {
                    self?.progress = progress
                }
            }
            let finished = !Task.isCancelled
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                guard finished else { return }
                self.apps = apps
                if let first = apps.first {
                    self.select(first)
                }
            }
        }
    }

    // MARK: - 关联文件

    /// List 选择直接写 selectedAppID，此处响应选择变化并触发关联文件扫描。
    func handleSelectionChange() {
        guard let id = selectedAppID, lastScannedAppID != id,
              let app = apps.first(where: { $0.id == id }) else { return }
        select(app)
    }

    func select(_ app: InstalledApp) {
        selectedAppID = app.id
        lastScannedAppID = app.id
        errorMessage = nil
        lastUninstallMessage = nil
        detailTask?.cancel()
        associatedFiles = []
        selectedFileIDs = []
        isScanningDetails = true

        detailTask = Task.detached(priority: .userInitiated) { [weak self] in
            let files = AppCatalog.findAssociatedFiles(for: app)
            let finished = !Task.isCancelled
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanningDetails = false
                guard finished else { return }
                self.associatedFiles = files
                // 智能安全默认选择：仅自动勾选 safe 和 appData，严禁自动勾选 caution
                self.selectedFileIDs = Set(files.filter { $0.safetyLevel.defaultSelected }.map(\.id))
            }
        }
    }

    // MARK: - 选择

    func setSelected(_ selected: Bool, for file: AssociatedFile) {
        if selected {
            selectedFileIDs.insert(file.id)
        } else {
            selectedFileIDs.remove(file.id)
        }
    }

    func setSelected(_ selected: Bool, for kind: AppAssociatedFileKind) {
        for file in associatedFiles where file.kind == kind {
            if selected {
                selectedFileIDs.insert(file.id)
            } else {
                selectedFileIDs.remove(file.id)
            }
        }
    }

    func setSelected(_ selected: Bool, for level: AssociatedFileSafetyLevel) {
        for file in associatedFiles where file.safetyLevel == level {
            if selected {
                selectedFileIDs.insert(file.id)
            } else {
                selectedFileIDs.remove(file.id)
            }
        }
    }

    // MARK: - 进程辅助

    /// 退出选中的正在运行的应用
    func quitSelectedApp(force: Bool = false) {
        guard let app = selectedApp else { return }
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            (app.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier) ||
            $0.bundleURL?.standardizedFileURL.path == app.url.standardizedFileURL.path
        }
        for r in runningApps {
            if force {
                r.forceTerminate()
            } else {
                r.terminate()
            }
        }
        // 延迟 0.5s 刷新状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.objectWillChange.send()
        }
    }

    // MARK: - 卸载

    func uninstallSelected() {
        guard let app = selectedApp else { return }
        guard !isSelectedAppRunning else {
            errorMessage = "「\(app.displayName)」正在运行，请先退出后再卸载。"
            return
        }
        let files = selectedFiles
        detailTask?.cancel()
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let outcome = try Uninstaller.uninstall(app: app, files: files)
                DispatchQueue.main.async {
                    guard let self else { return }
                    var message = "已卸载「\(app.displayName)」：应用\(outcome.appMoved ? "已移入废纸篓" : "未移动")"
                    if outcome.filesMoved > 0 {
                        message += "，关联文件 \(outcome.filesMoved) 项"
                    }
                    self.lastUninstallMessage = message
                    self.apps.removeAll { $0.id == app.id }
                    self.associatedFiles = []
                    self.selectedFileIDs = []
                    self.selectedAppID = nil
                    if let next = self.apps.first {
                        self.select(next)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.errorMessage = "卸载失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
