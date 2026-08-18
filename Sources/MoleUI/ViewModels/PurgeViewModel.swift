import Foundation
import Combine

/// 项目产物清理视图模型：扫描目录管理、产物扫描、默认勾选、清理执行。
/// 共享单例：扫描结果跨页面切换缓存（切走再切回不重复扫描，需手动点「扫描」刷新）。
@MainActor
final class PurgeViewModel: ObservableObject {
    static let shared = PurgeViewModel()

    @Published private(set) var roots: [URL] = PurgeEngine.defaultRoots
    @Published private(set) var candidates: [PurgeCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var currentPath = ""
    @Published private(set) var selectedCandidates: Set<UUID> = []
    @Published private(set) var lastCleanMessage: String?
    @Published private(set) var hasScannedOnce = false
    @Published private(set) var isCleaning = false
    @Published private(set) var cleanProgressText = ""
    @Published private(set) var cleanCompleted = 0
    @Published private(set) var cleanTotal = 0
    @Published var errorMessage: String?
    @Published var isShowingCleanConfirmation = false

    private var scanTask: Task<Void, Never>?
    /// 是否已自动探测桌面/文稿/下载（探测需要完全磁盘访问权限，只在用户点击扫描时执行一次）
    private var hasAutoDetectedRoots = false

    // MARK: - 派生数据

    var groupedCandidates: [(type: ProjectType, items: [PurgeCandidate])] {
        let groups = Dictionary(grouping: candidates, by: { $0.type })
        return ProjectType.allCases.compactMap { type in
            guard let items = groups[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    var selectedSize: Int64 {
        candidates.filter { selectedCandidates.contains($0.id) }.reduce(0) { $0 + $1.totalSize }
    }

    var totalSize: Int64 {
        candidates.reduce(0) { $0 + $1.totalSize }
    }

    var selectedCount: Int { selectedCandidates.count }

    /// 清理进度 0...1，供进度条使用
    var cleanProgress: Double {
        cleanTotal > 0 ? Double(cleanCompleted) / Double(cleanTotal) : 0
    }

    // MARK: - 扫描目录管理

    func addRoot(_ url: URL) {
        guard !roots.contains(url) else { return }
        roots.append(url)
        scan()
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
        scan()
    }

    // MARK: - 扫描

    func scan() {
        scanTask?.cancel()
        // 首次扫描时自动探测桌面/文稿/下载中的项目散落地——探测需要磁盘访问权限，
        // 只能在用户点击「扫描」时执行，不能在页面加载/初始化时探测。
        if !hasAutoDetectedRoots {
            hasAutoDetectedRoots = true
            let detected = PurgeEngine.detectProjectRoots()
            if !detected.isEmpty {
                roots.append(contentsOf: detected)
            }
        }
        isLoading = true
        errorMessage = nil
        candidates = []
        selectedCandidates = []

        let roots = roots
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let candidates = PurgeEngine.scan(roots: roots) { path in
                DispatchQueue.main.async {
                    self?.currentPath = path
                }
            }
            let finished = !Task.isCancelled
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if finished {
                    self.candidates = candidates
                    self.hasScannedOnce = true
                    self.applyDefaultSelection()
                } else {
                    self.errorMessage = "扫描已取消"
                }
            }
        }
    }

    /// 默认勾选：仅勾选非近期的产物（近期修改过的可能是活跃项目，默认不勾）。
    private func applyDefaultSelection() {
        selectedCandidates = Set(candidates.filter { !$0.isRecent }.map { $0.id })
    }

    // MARK: - 选择

    func isSelected(_ candidate: PurgeCandidate) -> Bool {
        selectedCandidates.contains(candidate.id)
    }

    func setSelected(_ selected: Bool, for candidate: PurgeCandidate) {
        if selected {
            selectedCandidates.insert(candidate.id)
        } else {
            selectedCandidates.remove(candidate.id)
        }
    }

    func setSelected(_ selected: Bool, for type: ProjectType) {
        for candidate in candidates where candidate.type == type {
            if selected {
                selectedCandidates.insert(candidate.id)
            } else {
                selectedCandidates.remove(candidate.id)
            }
        }
    }

    // MARK: - 清理

    func cleanSelected() {
        let items = candidates.filter { selectedCandidates.contains($0.id) }
        guard !items.isEmpty else { return }
        scanTask?.cancel()
        // 进入清理状态：显示实时进度，直到完成后再重新扫描
        isCleaning = true
        lastCleanMessage = nil
        errorMessage = nil
        cleanProgressText = "准备清理…"
        cleanCompleted = 0
        cleanTotal = items.count

        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = PurgeEngine.clean(candidates: items) { label, completed, total in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.cleanProgressText = label
                    self.cleanCompleted = completed
                    self.cleanTotal = total
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCleaning = false
                var message = ""
                if outcome.commandSucceeded > 0 {
                    message += "命令清理成功 \(outcome.commandSucceeded) 个项目；"
                }
                if outcome.trashed > 0 {
                    message += "已移入废纸篓 \(outcome.trashed) 个产物目录；"
                }
                if outcome.failures.isEmpty {
                    self.lastCleanMessage = message.isEmpty ? "没有可清理的项目" : String(message.dropLast())
                } else {
                    self.errorMessage = "\(message)另有 \(outcome.failures.count) 项失败（工具未安装或权限不足）："
                        + outcome.failures.prefix(3).joined(separator: "；")
                }
                self.scan()
            }
        }
    }
}
