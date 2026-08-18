import Foundation

/// 卸载执行：将应用本体与选中的关联文件移入废纸篓（可恢复），跳过受保护路径。
enum Uninstaller {
    struct Outcome {
        var appMoved: Bool
        var filesMoved: Int
    }

    enum UninstallError: LocalizedError {
        case protectedApp(String)
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .protectedApp(let name):
                return "「\(name)」受系统保护，无法卸载。"
            case .executionFailed(let reason):
                return "卸载失败：\(reason)"
            }
        }
    }

    /// 卸载：先移应用本体（失败则中止，不碰关联文件，避免把仍在用的数据孤立），
    /// 再逐个移入关联文件。均跳过受保护路径。
    @discardableResult
    static func uninstall(app: InstalledApp, files: [AssociatedFile]) throws -> Outcome {
        let fileManager = FileManager.default

        // 1. 应用本体
        var appMoved = false
        if TrashService.isProtected(app.url) {
            if files.isEmpty {
                throw UninstallError.protectedApp(app.displayName)
            }
        } else {
            do {
                try fileManager.trashItem(at: app.url, resultingItemURL: nil)
                appMoved = true
                OperationLog.append(module: "uninstall", "卸载应用「\(app.displayName)」：\(app.url.path)")
            } catch {
                // 应用正在运行或权限不足：中止，不清理关联文件
                throw error
            }
        }

        // 2. 关联文件
        var filesMoved = 0
        var lastError: Error?
        for file in files {
            guard !TrashService.isProtected(file.url) else { continue }
            do {
                try fileManager.trashItem(at: file.url, resultingItemURL: nil)
                filesMoved += 1
                OperationLog.append(module: "uninstall", "关联文件：\(file.url.path)（\(ByteFormatter.fileString(from: file.size))）")
            } catch {
                lastError = error
            }
        }

        if !appMoved && filesMoved == 0 {
            if let lastError {
                throw lastError
            } else if TrashService.isProtected(app.url) {
                throw UninstallError.protectedApp(app.displayName)
            }
        }

        OperationLog.append(module: "uninstall", "完成：应用\(appMoved ? "已移入废纸篓" : "未移动")，关联文件 \(filesMoved) 项")
        return Outcome(appMoved: appMoved, filesMoved: filesMoved)
    }
}
