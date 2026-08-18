import Foundation
import Combine
import AppKit

/// 磁盘分析视图模型：后台扫描、目录导航栈、大文件与废纸篓。
/// 共享单例：扫描结果与导航位置跨页面切换缓存（需手动点「重新扫描」刷新）。
@MainActor
final class DiskAnalysisViewModel: ObservableObject {
    static let shared = DiskAnalysisViewModel()

    @Published private(set) var root: DiskEntry?
    @Published private(set) var largeFiles: [DiskEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var progress = DiskScanner.Progress()
    @Published var errorMessage: String?
    @Published private(set) var scanRootURL = URL(fileURLWithPath: NSHomeDirectory())
    /// 导航栈：从根到当前节点的子索引序列
    @Published private(set) var pathIndices: [Int] = []
    @Published var selectedFiles: Set<DiskEntry.ID> = []
    @Published var isShowingTrashConfirmation = false
    @Published private(set) var lastTrashMessage: String?
    @Published var previewURL: URL?
    @Published var toastMessage: String?

    private var scanTask: Task<Void, Never>?

    // MARK: - 派生数据

    var currentEntry: DiskEntry? {
        guard var node = root else { return nil }
        for index in pathIndices {
            guard let children = node.children, children.indices.contains(index) else { return nil }
            node = children[index]
        }
        return node
    }

    var currentChildren: [DiskEntry] {
        currentEntry?.sortedChildren ?? []
    }

    var breadcrumbs: [(name: String, index: Int)] {
        var result: [(name: String, index: Int)] = []
        var node = root
        for (i, index) in pathIndices.enumerated() {
            guard let children = node?.children, children.indices.contains(index) else { break }
            node = children[index]
            result.append((node?.name ?? "", i))
        }
        return result
    }

    var selectedSize: Int64 {
        largeFiles
            .filter { selectedFiles.contains($0.id) }
            .reduce(0) { $0 + $1.size }
    }

    var selectedSizeString: String {
        ByteFormatter.fileString(from: selectedSize)
    }

    // MARK: - 扫描

    func start() {
        scanRoot(scanRootURL)
    }

    func cancelScan() {
        scanTask?.cancel()
        isLoading = false
        errorMessage = "扫描已停止"
    }

    func scanRoot(_ url: URL) {
        scanRootURL = url
        scanTask?.cancel()
        isLoading = true
        errorMessage = nil
        root = nil
        largeFiles = []
        pathIndices = []
        selectedFiles = []
        lastTrashMessage = nil
        toastMessage = nil

        let options = DiskScanner.Options()
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = DiskScanner.scan(root: url, options: options) { progress in
                DispatchQueue.main.async {
                    self?.progress = progress
                }
            }
            let finished = !Task.isCancelled
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if finished {
                    self.root = result.root
                    self.largeFiles = result.largeFiles
                } else {
                    self.errorMessage = "扫描已取消"
                }
            }
        }
    }

    // MARK: - 快捷文件操作

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openWithDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
        showToast("已拷贝路径")
    }

    func quickLook(_ url: URL) {
        previewURL = url
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    // MARK: - 导航

    func enter(childIndex: Int) {
        guard let children = currentEntry?.children, children.indices.contains(childIndex) else { return }
        pathIndices.append(childIndex)
    }

    func goUp() {
        guard !pathIndices.isEmpty else { return }
        pathIndices.removeLast()
    }

    /// index < 0 表示回到根目录
    func jumpTo(index: Int) {
        if index < 0 {
            pathIndices = []
        } else {
            pathIndices = Array(pathIndices.prefix(index + 1))
        }
    }

    // MARK: - 废纸篓

    func trashSingle(entry: DiskEntry) {
        do {
            _ = try TrashService.moveToTrash([entry.url])
            lastTrashMessage = "已将「\(entry.name)」移入废纸篓"
            scanRoot(scanRootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func trashSelected() {
        let urls = largeFiles.filter { selectedFiles.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        do {
            let moved = try TrashService.moveToTrash(urls)
            lastTrashMessage = "已将 \(moved) 个项目移入废纸篓"
            // 重新扫描以刷新大小
            scanRoot(scanRootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
