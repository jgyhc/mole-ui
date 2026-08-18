import XCTest
@testable import MoleUI

final class OptimizeTests: XCTestCase {
    private var originalLogURL: URL!
    private var tempLogURL: URL!

    override func setUpWithError() throws {
        // 目录清理会写操作日志，重定向到临时文件避免污染真实日志
        originalLogURL = OperationLog.logFileURL
        tempLogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-optimize-log-\(UUID().uuidString)/operations.log")
        OperationLog.logFileURL = tempLogURL
    }

    override func tearDownWithError() throws {
        OperationLog.logFileURL = originalLogURL
        try? FileManager.default.removeItem(at: tempLogURL.deletingLastPathComponent())
    }

    // MARK: - 任务元数据

    func testTaskListMetadata() {
        let tasks = OptimizationTask.all
        XCTAssertFalse(tasks.isEmpty)
        // id 唯一
        XCTAssertEqual(Set(tasks.map(\.id)).count, tasks.count)
        for task in tasks {
            XCTAssertFalse(task.title.isEmpty, "\(task.id) 标题为空")
            XCTAssertFalse(task.detail.isEmpty, "\(task.id) 描述为空")
            XCTAssertFalse(task.symbol.isEmpty, "\(task.id) 图标为空")
        }
    }

    func testGroupMetadataAndCoverage() {
        for group in OptimizationGroup.allCases {
            XCTAssertFalse(group.title.isEmpty)
            XCTAssertFalse(group.symbol.isEmpty)
            XCTAssertFalse(
                OptimizationTask.all.filter { $0.group == group }.isEmpty,
                "分组 \(group) 没有任务"
            )
        }
    }

    func testRequiresRootTasksExist() {
        let rootTasks = OptimizationTask.all.filter { $0.requiresRoot }
        XCTAssertFalse(rootTasks.isEmpty)
        // 有可运行的普通任务
        XCTAssertTrue(OptimizationTask.all.contains(where: { !$0.requiresRoot }))
    }

    // MARK: - 引擎执行

    func testRequiresRootTasksAreSkippedWithoutExecuting() {
        let rootTasks = OptimizationTask.all.filter { $0.requiresRoot }
        for task in rootTasks {
            let state = OptimizationEngine.run(task)
            guard case .skipped(let reason) = state else {
                XCTFail("root 任务 \(task.id) 应被跳过，实际 \(state)")
                return
            }
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testRunEchoCommandSucceeds() {
        let task = OptimizationTask(
            id: "test-echo", title: "t", detail: "d", symbol: "s",
            group: .maintenance, requiresRoot: false,
            action: .command(executable: "/bin/echo", arguments: ["hello"])
        )
        let state = OptimizationEngine.run(task)
        guard case .succeeded(let message) = state else {
            XCTFail("echo 应成功，实际 \(state)")
            return
        }
        XCTAssertEqual(message, "完成")
    }

    func testRunFailingCommandReportsFailure() {
        let task = OptimizationTask(
            id: "test-false", title: "t", detail: "d", symbol: "s",
            group: .maintenance, requiresRoot: false,
            action: .command(executable: "/usr/bin/false", arguments: [])
        )
        let state = OptimizationEngine.run(task)
        guard case .failed(let message) = state else {
            XCTFail("false 应失败，实际 \(state)")
            return
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testRunMissingExecutableReportsFailure() {
        let task = OptimizationTask(
            id: "test-missing", title: "t", detail: "d", symbol: "s",
            group: .maintenance, requiresRoot: false,
            action: .command(executable: "/nonexistent/mole-binary", arguments: [])
        )
        let state = OptimizationEngine.run(task)
        guard case .failed = state else {
            XCTFail("缺失可执行文件应失败，实际 \(state)")
            return
        }
    }

    // MARK: - 目录清理

    func testTrashDirectoryContentsMovesEntries() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-optimize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try Data(repeating: 0, count: 10).write(to: temp.appendingPathComponent("a.log"))
        try Data(repeating: 0, count: 10).write(to: temp.appendingPathComponent("b.log"))

        let task = OptimizationTask(
            id: "test-trash", title: "t", detail: "d", symbol: "s",
            group: .caches, requiresRoot: false,
            action: .trashDirectoryContents(path: temp.path)
        )
        let state = OptimizationEngine.run(task)
        guard case .succeeded(let message) = state else {
            XCTFail("应成功，实际 \(state)")
            return
        }
        XCTAssertTrue(message.contains("2"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("a.log").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("b.log").path))
    }

    func testTrashDirectoryContentsSkipsProtectedPath() {
        let task = OptimizationTask(
            id: "test-protected", title: "t", detail: "d", symbol: "s",
            group: .caches, requiresRoot: false,
            action: .trashDirectoryContents(path: "/System/Library")
        )
        let state = OptimizationEngine.run(task)
        guard case .skipped = state else {
            XCTFail("受保护路径应跳过，实际 \(state)")
            return
        }
    }

    func testTrashDirectoryContentsMissingDirectorySucceeds() {
        let task = OptimizationTask(
            id: "test-missing-dir", title: "t", detail: "d", symbol: "s",
            group: .caches, requiresRoot: false,
            action: .trashDirectoryContents(path: "/tmp/mole-nonexistent-\(UUID().uuidString)")
        )
        let state = OptimizationEngine.run(task)
        guard case .succeeded = state else {
            XCTFail("缺失目录应视为无需清理，实际 \(state)")
            return
        }
    }
}
