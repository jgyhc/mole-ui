import XCTest
@testable import MoleUI

final class OperationLogTests: XCTestCase {
    private var tempLogURL: URL!
    private var originalLogURL: URL!
    private var originalKeepHistoryLog: Any?

    override func setUpWithError() throws {
        originalLogURL = OperationLog.logFileURL
        tempLogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-log-\(UUID().uuidString)/operations.log")
        OperationLog.logFileURL = tempLogURL
        originalKeepHistoryLog = UserDefaults.standard.object(forKey: "keepHistoryLog")
    }

    override func tearDownWithError() throws {
        OperationLog.logFileURL = originalLogURL
        if let originalKeepHistoryLog {
            UserDefaults.standard.set(originalKeepHistoryLog, forKey: "keepHistoryLog")
        } else {
            UserDefaults.standard.removeObject(forKey: "keepHistoryLog")
        }
        try? FileManager.default.removeItem(at: tempLogURL.deletingLastPathComponent())
    }

    func testAppendAndRead() {
        OperationLog.append(module: "clean", "移入废纸篓：/tmp/a（1 KB）")
        OperationLog.append(module: "uninstall", "卸载应用「Fake」")
        // 写入在串行队列异步执行，轮询等待落盘
        let lines = waitForLines(count: 2)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("[clean]"))
        XCTAssertTrue(lines[0].contains("移入废纸篓：/tmp/a"))
        XCTAssertTrue(lines[1].contains("[uninstall]"))
        XCTAssertTrue(lines[1].contains("卸载应用「Fake」"))
    }

    func testReadRespectsLimit() {
        for i in 0..<10 {
            OperationLog.append(module: "test", "line \(i)")
        }
        let lines = waitForLines(count: 10)
        XCTAssertEqual(lines.count, 10)
        let limited = waitForLines(count: 10, limit: 3)
        XCTAssertEqual(limited.count, 3)
        XCTAssertEqual(limited.last, lines.last)
    }

    func testTrimKeepsLastLines() {
        // 直接写入超过 maxLines 的内容验证截断
        let tooMany = OperationLog.maxLines + 10
        for i in 0..<tooMany {
            OperationLog.append(module: "test", "line \(i)")
        }
        // 等待全部写入 + 截断完成：行数回到 maxLines 且最后一行是最新写入
        // 注意：read 默认 limit 500，需显式传入更大的 limit 才能观察到截断后的全部行
        let expectedLast = "line \(tooMany - 1)"
        let deadline = Date().addingTimeInterval(5)
        var lines = OperationLog.read(limit: OperationLog.maxLines + 10)
        while (lines.count != OperationLog.maxLines || lines.last?.contains(expectedLast) != true) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            lines = OperationLog.read(limit: OperationLog.maxLines + 10)
        }
        XCTAssertEqual(lines.count, OperationLog.maxLines, "应截断到 maxLines 行")
        XCTAssertTrue(lines.last?.contains(expectedLast) == true, "应保留最新行")
        let firstKept = tooMany - OperationLog.maxLines

        XCTAssertTrue(lines.first?.contains("line \(firstKept)") == true, "应从头部截断，首行应为 line \(firstKept)")
    }

    func testDisabledSettingSkipsWrites() {
        UserDefaults.standard.set(false, forKey: "keepHistoryLog")
        OperationLog.append(module: "test", "should not appear")
        // 给异步写一个落盘机会
        let expectation = expectation(description: "queue drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertFalse(OperationLog.fileExists, "关闭日志后不应创建日志文件")
    }

    func testReadMissingFileReturnsEmpty() {
        XCTAssertTrue(OperationLog.read().isEmpty)
        XCTAssertFalse(OperationLog.fileExists)
    }

    // MARK: - 引擎接入

    func testCleanEngineLogsPermanentDelete() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-log-item-\(UUID().uuidString)")
        try Data(repeating: 0, count: 10).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let item = CleanItem(
            url: temp, name: "temp-item", size: 10,
            isDirectory: false, fileCount: 1, category: .trash
        )
        let outcome = try CleanEngine.clean(items: [item])
        XCTAssertEqual(outcome.permanent, 1)

        let lines = waitForLines(count: 2)
        XCTAssertTrue(lines[0].contains("[clean]"))
        XCTAssertTrue(lines[0].contains("永久删除"))
        XCTAssertTrue(lines[0].contains(temp.path))
        XCTAssertTrue(lines[1].contains("完成"))
    }

    // MARK: - 工具

    /// 轮询等待日志中出现指定行数（写入是异步的）。
    private func waitForLines(count: Int, limit: Int = 500) -> [String] {
        let deadline = Date().addingTimeInterval(3)
        var lines = OperationLog.read(limit: limit)
        while lines.count < count && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            lines = OperationLog.read(limit: limit)
        }
        return lines
    }
}
