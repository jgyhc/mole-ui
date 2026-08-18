import Foundation

/// 操作日志：所有删除/清理操作写入 `~/Library/Logs/Mole/operations.log`，可在设置页查看。
/// 线程安全：读写都在串行队列上同步执行，返回后即可读到刚写入的内容。
enum OperationLog {
    /// 日志文件 URL（可注入用于测试）。
    static var logFileURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Mole/operations.log")

    /// 文件最大保留行数（超出后从头部截断，防止无限膨胀）。
    static let maxLines = 2000

    private static let queue = DispatchQueue(label: "mole.operation-log", qos: .utility)

    /// 追加一条操作日志。尊重设置「记录操作历史日志」（keepHistoryLog，默认开启）。
    static func append(module: String, _ message: String) {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "keepHistoryLog") == nil
            ? true
            : defaults.bool(forKey: "keepHistoryLog")
        guard enabled else { return }

        let line = "\(Self.timestamp())  [\(module)] \(message)"
        queue.sync {
            Self.write(line)
        }
    }

    /// 读取最近 limit 行日志（保持时间顺序，最新在后）。文件不存在返回空数组。
    static func read(limit: Int = 500) -> [String] {
        queue.sync {
            guard let text = try? String(contentsOf: logFileURL, encoding: .utf8) else { return [] }
            // 省略空元素：每行以 \n 结尾，文件末尾的空字符串不应算作一行
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            return Array(lines.suffix(limit))
        }
    }

    /// 日志文件是否存在。
    static var fileExists: Bool {
        FileManager.default.fileExists(atPath: logFileURL.path)
    }

    // MARK: - 私有

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func write(_ line: String) {
        let fileManager = FileManager.default
        let directory = logFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            let offset = try? handle.seekToEnd()
            var needsLeadingNewline = false
            // 防御：文件末尾若不是换行（例如刚被截断），先补一个换行再追加，避免两行粘连
            if let offset, offset > 0 {
                try? handle.seek(toOffset: offset - 1)
                if let lastByte = try? handle.read(upToCount: 1), lastByte != Data([0x0A]) {
                    needsLeadingNewline = true
                }
            }
            handle.seekToEndOfFile()
            let payload = (needsLeadingNewline ? "\n" : "") + line + "\n"
            handle.write(Data(payload.utf8))
            try? handle.close()
        } else {
            try? (line + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
        }
        trimIfNeeded()
    }

    /// 行数超过上限时保留最后 maxLines 行。
    private static func trimIfNeeded() {
        guard let text = try? String(contentsOf: logFileURL, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxLines else { return }
        // 保留结尾换行，保证后续追加不会与最后一行粘连
        let kept = lines.suffix(maxLines).joined(separator: "\n") + "\n"
        try? kept.write(to: logFileURL, atomically: true, encoding: .utf8)
    }
}
