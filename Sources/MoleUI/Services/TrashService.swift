import Foundation

/// 安全删除服务：移入废纸篓（可恢复），拒绝受保护路径。
enum TrashService {
    /// 受保护路径：系统核心目录（含子路径）与关键根目录，禁止移入废纸篓。
    /// 系统根目录（/System 等）拒绝删除；关键根目录（/Applications, /Library, ~ 等）本身受保护，
    /// 但其下的第三方应用（/Applications/Foo.app）与关联文件（/Library/Application Support/Foo 等）允许卸载清理。
    static func isProtected(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = NSHomeDirectory()

        // 1. 精确受保护：文件系统根、用户主目录根、系统一级/关键二级容器根目录
        let exactProtected: Set<String> = [
            "/", home, "/Users", "/Applications", "/System", "/Library", "/Volumes",
            "/private", "/System/Volumes", "/System/Applications", "/System/Library",
            "/usr", "/bin", "/sbin", "/etc", "/var", "/dev",
            "/Library/Application Support", "/Library/Preferences", "/Library/Caches",
            "/Library/Logs", "/Library/LaunchAgents", "/Library/LaunchDaemons",
            "/Library/PrivilegedHelperTools",
            "\(home)/Library",
            "\(home)/Library/Application Support",
            "\(home)/Library/Preferences",
            "\(home)/Library/Caches",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/LaunchAgents",
            "\(home)/Library/Logs",
            "\(home)/Library/Saved Application State"
        ]
        if exactProtected.contains(path) { return true }

        // 2. 系统核心全树保护：/System (含 /System/Applications 等系统组件) 及系统二进制目录
        let strictPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/dev/", "/private/var/db/"]
        for prefix in strictPrefixes {
            if path.hasPrefix(prefix) { return true }
        }

        return false
    }

    /// 将一批 URL 移入废纸篓，跳过受保护路径；返回成功移入的数量。
    @discardableResult
    static func moveToTrash(_ urls: [URL]) throws -> Int {
        let fileManager = FileManager.default
        var moved = 0
        var lastError: Error?
        for url in urls {
            guard !isProtected(url) else { continue }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                moved += 1
                OperationLog.append(module: "trash", "移入废纸篓：\(url.path)")
            } catch {
                lastError = error
            }
        }
        if moved == 0, let lastError {
            throw lastError
        }
        return moved
    }
}
