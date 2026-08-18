import Foundation

/// 统一的字节大小格式化工具，基于系统原生 `ByteCountFormatter`。
/// 注意：`ByteCountFormatter` 输出跟随系统 locale，但单位名与数字格式在各 locale 下基本一致。
enum ByteFormatter {
    /// 文件风格（如 "1.5 GB"）。
    static func fileString(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 内存风格（二进制单位，如 "8 GB"）。
    static func memoryString(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}
