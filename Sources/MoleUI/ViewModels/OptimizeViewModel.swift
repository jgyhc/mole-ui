import Foundation
import Combine

/// 系统优化视图模型：任务状态管理、单任务执行与「全部运行」。
@MainActor
final class OptimizeViewModel: ObservableObject {
    @Published private(set) var entries: [OptimizationTaskEntry] =
        OptimizationTask.all.map { OptimizationTaskEntry(task: $0) }
    @Published private(set) var isRunning = false

    // MARK: - 派生数据

    var runnableCount: Int {
        entries.filter { !$0.task.requiresRoot }.count
    }

    var succeededCount: Int {
        entries.filter { entry in
            if case .succeeded = entry.state { return true }
            return false
        }.count
    }

    var failedCount: Int {
        entries.filter { entry in
            if case .failed = entry.state { return true }
            return false
        }.count
    }

    var skippedCount: Int {
        entries.filter { entry in
            if case .skipped = entry.state { return true }
            return false
        }.count
    }

    var runningCount: Int {
        entries.filter { entry in
            if case .running = entry.state { return true }
            return false
        }.count
    }

    var hasRunAny: Bool {
        runningCount > 0 || succeededCount > 0 || failedCount > 0 || skippedCount > 0
    }

    // MARK: - 执行

    /// 依次运行全部非管理员任务。
    func runAll() {
        guard !isRunning else { return }
        let targets = entries.filter { !$0.task.requiresRoot }
        guard !targets.isEmpty else { return }
        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            for entry in targets {
                guard !Task.isCancelled else { break }
                await self.execute(entry.task)
            }
            self.isRunning = false
        }
    }

    func runSingle(_ task: OptimizationTask) {
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            guard let self else { return }
            await self.execute(task)
            self.isRunning = false
        }
    }

    /// 将所有任务状态重置为未运行。
    func resetAll() {
        guard !isRunning else { return }
        for index in entries.indices {
            entries[index].state = .idle
        }
    }

    // MARK: - 私有

    private func execute(_ task: OptimizationTask) async {
        update(state: .running, for: task)
        let result = await Task.detached(priority: .userInitiated) {
            OptimizationEngine.run(task)
        }.value
        update(state: result, for: task)
    }

    private func update(state: OptimizationTaskState, for task: OptimizationTask) {
        guard let index = entries.firstIndex(where: { $0.task.id == task.id }) else { return }
        entries[index].state = state
    }
}
