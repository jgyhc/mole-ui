import Foundation
import Combine

/// 安装包清理视图模型：扫描安装包、选择、清理执行。
/// 共享单例：扫描结果跨页面切换缓存（切走再切回不重复扫描，需手动点「扫描」刷新）。
@MainActor
final class InstallerViewModel: ObservableObject {
    static let shared = InstallerViewModel()

    @Published private(set) var files: [InstallerFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var currentSource: InstallerSource?
    @Published private(set) var currentPath = ""
    @Published var selection: Set<UUID> = []
    @Published private(set) var lastCleanMessage: String?
    @Published private(set) var hasScannedOnce = false
    @Published var errorMessage: String?
    @Published var isShowingCleanConfirmation = false

    private var scanTask: Task<Void, Never>?

    // MARK: - 派生数据

    var selectedSize: Int64 {
        files.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    // MARK: - 扫描

    func scan() {
        scanTask?.cancel()
        isLoading = true
        errorMessage = nil
        files = []
        selection = []
        lastCleanMessage = nil

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let files = InstallerEngine.scan { source, path in
                DispatchQueue.main.async {
                    self?.currentSource = source
                    self?.currentPath = path
                }
            }
            let finished = !Task.isCancelled
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if finished {
                    self.files = files
                    self.hasScannedOnce = true
                } else {
                    self.errorMessage = "扫描已取消"
                }
            }
        }
    }

    // MARK: - 选择

    func isSelected(_ file: InstallerFile) -> Bool {
        selection.contains(file.id)
    }

    func setSelected(_ selected: Bool, for file: InstallerFile) {
        if selected {
            selection.insert(file.id)
        } else {
            selection.remove(file.id)
        }
    }

    // MARK: - 清理

    func cleanSelected() {
        let items = files.filter { selection.contains($0.id) }
        guard !items.isEmpty else { return }
        scanTask?.cancel()
        Task.detached(priority: .userInitiated) { [weak self] in
            let moved = try? InstallerEngine.clean(files: items)
            DispatchQueue.main.async {
                guard let self else { return }
                if let moved {
                    self.lastCleanMessage = "已将 \(moved) 个安装包移入废纸篓"
                } else {
                    self.errorMessage = "清理失败，部分文件可能被占用或受保护"
                }
                self.scan()
            }
        }
    }
}
