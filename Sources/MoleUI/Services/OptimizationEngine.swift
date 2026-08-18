import Foundation

/// 系统优化引擎：执行内置维护任务（对应 `mo optimize`）。
/// 命令全部直接执行（不经 shell），可执行文件与参数均为固定白名单，不接受外部输入。
enum OptimizationEngine {
    /// 执行任务，返回结果状态。
    static func run(_ task: OptimizationTask) -> OptimizationTaskState {
        // 需要管理员权限的任务在普通权限下直接跳过
        if task.requiresRoot {
            return .skipped(reason: "需要管理员权限，请在终端中以 sudo 运行 mo optimize")
        }
        switch task.action {
        case .command(let executable, let arguments):
            let (exitCode, output) = runProcess(executable: executable, arguments: arguments)
            if exitCode == 0 {
                return .succeeded(message: "完成")
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? "退出码 \(exitCode)" : String(trimmed.prefix(300))
            return .failed(message: message)
        case .trashDirectoryContents(let path):
            return trashDirectoryContents(path)
        }
    }

    /// 直接执行外部命令（不经 shell）。返回 (退出码, 输出)。
    /// 先读取输出再等待退出，避免大输出填满管道缓冲导致死锁。
    static func runProcess(executable: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "无法启动 \(executable)：\(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    /// 将目录内的全部条目移入废纸篓（保留目录本身）。受保护路径直接跳过。
    private static func trashDirectoryContents(_ path: String) -> OptimizationTaskState {
        let url = URL(fileURLWithPath: path)
        guard !TrashService.isProtected(url) else {
            return .skipped(reason: "受保护路径：\(path)")
        }
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: []
        ) else {
            // 目录不存在或不可读，视为无需清理
            return .succeeded(message: "无需清理（目录不存在或不可读）")
        }
        var moved = 0
        var failed = 0
        for child in children {
            do {
                try fileManager.trashItem(at: child, resultingItemURL: nil)
                moved += 1
                OperationLog.append(module: "optimize", "清理诊断报告：\(child.path)")
            } catch {
                failed += 1
            }
        }
        if moved > 0 {
            let suffix = failed > 0 ? "，失败 \(failed) 项" : ""
            return .succeeded(message: "已移入废纸篓 \(moved) 项\(suffix)")
        }
        if failed > 0 {
            return .failed(message: "清理失败 \(failed) 项")
        }
        return .succeeded(message: "无需清理")
    }
}
