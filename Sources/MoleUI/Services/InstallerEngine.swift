import Foundation

/// 安装包清理引擎：在下载/桌面/文稿/Homebrew 缓存/iCloud/邮件等位置查找安装包（对应 `mo installer`）。
enum InstallerEngine {
    static let fileExtensions: Set<String> = ["dmg", "pkg", "mpkg", "zip", "tgz", "iso"]
    /// 按文件名后缀匹配的复合扩展名。
    static let compoundSuffixes: [String] = [".tar.gz"]
    /// 默认不按大小过滤：列出全部安装包，由用户勾选。
    static let defaultMinSize: Int64 = 0

    /// 全部来源的默认搜索目录。
    static var defaultSearchDirectories: [(source: InstallerSource, url: URL)] {
        InstallerSource.allCases.flatMap { source in
            source.searchDirs.map { (source, $0) }
        }
    }

    /// 判断文件是否为安装包（dmg/pkg/mpkg/zip/tgz/iso，或 .tar.gz 复合后缀）。
    static func isInstallerFile(url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if compoundSuffixes.contains(where: { name.hasSuffix($0) }) { return true }
        return fileExtensions.contains(url.pathExtension.lowercased())
    }

    /// 扫描安装包文件（按大小降序）。
    /// 同一文件可能被多个来源覆盖（如 Homebrew 根目录与其 downloads 子目录），按标准化路径去重。
    static func scan(
        searchDirectories: [(source: InstallerSource, url: URL)] = defaultSearchDirectories,
        minSize: Int64 = defaultMinSize,
        onProgress: ((InstallerSource, String) -> Void)? = nil
    ) -> [InstallerFile] {
        var files: [InstallerFile] = []
        var seen = Set<String>()
        let fileManager = FileManager.default

        func walk(_ url: URL, depth: Int, source: InstallerSource) {
            if Task.isCancelled || depth > 3 { return }
            onProgress?(source, url.path)
            let children = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            for child in children ?? [] {
                guard let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
                ) else { continue }
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    walk(child, depth: depth + 1, source: source)
                } else {
                    let size = Int64(values.fileSize ?? 0)
                    guard size >= minSize, isInstallerFile(url: child) else { continue }
                    let key = child.standardizedFileURL.path
                    guard seen.insert(key).inserted else { continue }
                    files.append(InstallerFile(
                        url: child,
                        name: child.lastPathComponent,
                        size: size,
                        source: source
                    ))
                }
            }
        }

        for entry in searchDirectories where fileManager.fileExists(atPath: entry.url.path) {
            walk(entry.url, depth: 0, source: entry.source)
        }
        files.sort { $0.size > $1.size }
        return files
    }

    /// 将安装包移入废纸篓。返回移入数量。
    @discardableResult
    static func clean(files: [InstallerFile]) throws -> Int {
        var moved = 0
        var lastError: Error?
        for file in files {
            guard !TrashService.isProtected(file.url) else { continue }
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                moved += 1
                OperationLog.append(module: "installer", "移入废纸篓：\(file.url.path)（\(ByteFormatter.fileString(from: file.size))）")
            } catch {
                lastError = error
            }
        }
        if moved == 0, let lastError { throw lastError }
        OperationLog.append(module: "installer", "完成：移入废纸篓 \(moved) 个安装包")
        return moved
    }
}
