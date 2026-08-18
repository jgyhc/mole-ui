import Foundation

extension Double {
    /// "42.5%"
    var percentString: String { String(format: "%.1f%%", self) }
}

extension Int64 {
    /// 字节/秒 → "1.2 MB/s"
    var speedString: String { ByteFormatter.fileString(from: self) + "/s" }
}

extension Double {
    /// 字节/秒 → "1.2 MB/s"
    var speedString: String { Int64(self).speedString }
}

enum DurationFormatter {
    /// 运行时长："1d 2h 3m"
    static func uptime(from interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 || days > 0 { parts.append("\(hours)h") }
        parts.append("\(minutes)m")
        return parts.joined(separator: " ")
    }
}
