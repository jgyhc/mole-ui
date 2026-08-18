import Foundation
import Combine

/// 深度清理视图模型：后台扫描、默认勾选、选择集、清理执行。
/// 共享单例：扫描结果跨页面切换缓存（切走再切回不重复扫描，需手动点「扫描」刷新）。
@MainActor
final class CleanViewModel: ObservableObject {
    static let shared = CleanViewModel()

    @Published private(set) var results: [CleanCategoryResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var progress = CleanScanProgress()
    @Published private(set) var selectedItems: Set<UUID> = []
    @Published private(set) var hasScannedOnce = false
    @Published var isShowingCleanConfirmation = false
    @Published private(set) var lastCleanMessage: String?
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    // MARK: - 派生数据

    var allItems: [CleanItem] { results.flatMap { $0.items } }

    var totalSelectableSize: Int64 {
        results.reduce(0) { $0 + $1.totalSize }
    }

    var selectedSize: Int64 {
        allItems.filter { selectedItems.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int { selectedItems.count }

    /// 选择集中是否包含永久删除项（废纸篓内容）
    var hasPermanentSelection: Bool {
        allItems.contains { selectedItems.contains($0.id) && $0.isPermanent }
    }

    // MARK: - 扫描

    func scan() {
        scanTask?.cancel()
        isLoading = true
        errorMessage = nil
        results = []
        selectedItems = []
        lastCleanMessage = nil

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let results = CleanEngine.scanAll { progress in
                DispatchQueue.main.async {
                    self?.progress = progress
                }
            }
            let finished = !Task.isCancelled
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if finished {
                    self.results = results
                    self.hasScannedOnce = true
                    self.applyDefaultSelection()
                } else {
                    self.errorMessage = "扫描已取消"
                }
            }
        }
    }

    /// 默认勾选：安全类别全选，危险类别（废纸篓/临时文件/残留）不选
    private func applyDefaultSelection() {
        var selection: Set<UUID> = []
        for result in results where result.category.defaultSelected {
            for item in result.items {
                selection.insert(item.id)
            }
        }
        selectedItems = selection
    }

    // MARK: - 选择

    func isSelected(_ item: CleanItem) -> Bool {
        selectedItems.contains(item.id)
    }

    func setSelected(_ selected: Bool, for item: CleanItem) {
        if selected {
            selectedItems.insert(item.id)
        } else {
            selectedItems.remove(item.id)
        }
    }

    func setSelected(_ selected: Bool, for result: CleanCategoryResult) {
        for item in result.items {
            if selected {
                selectedItems.insert(item.id)
            } else {
                selectedItems.remove(item.id)
            }
        }
    }

    // MARK: - 清理

    func cleanSelected() {
        let items = allItems.filter { selectedItems.contains($0.id) }
        guard !items.isEmpty else { return }
        scanTask?.cancel()
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = try? CleanEngine.clean(items: items)
            DispatchQueue.main.async {
                guard let self else { return }
                if let outcome {
                    var message = "已清理 \(outcome.moved) 项（移入废纸篓）"
                    if outcome.permanent > 0 {
                        message += "；永久删除 \(outcome.permanent) 项"
                    }
                    self.lastCleanMessage = message
                } else {
                    self.errorMessage = "清理失败，部分项目可能被占用或受保护"
                }
                self.scan()
            }
        }
    }
}
