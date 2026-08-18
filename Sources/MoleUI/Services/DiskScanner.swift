import Foundation

/// 递归磁盘扫描器：自底向上聚合目录大小，同时收集大文件。
/// 在 `Task.detached` 中调用，通过 `Task.isCancelled` 支持取消。
enum DiskScanner {
    struct Progress {
        var scannedFiles: Int = 0
        var currentPath: String = ""
    }

    struct Options {
        var followSymlinks = false
        var collectLargeFiles = true
        var largeFilesMinSize: Int64 = 5 * 1024 * 1024
        var largeFilesLimit = 100
        var maxDepth: Int?
        /// 是否跳过隐藏文件/目录（磁盘分析等默认跳过；清理引擎扫描隐藏构建缓存时需要关闭）
        var skipHiddenFiles = true
    }

    struct Result {
        var root: DiskEntry
        var largeFiles: [DiskEntry]
        var errorCount: Int
        var totalFiles: Int
    }

    static func scan(root: URL, options: Options = Options(), onProgress: ((Progress) -> Void)? = nil) -> Result {
        var largeFiles: [DiskEntry] = []
        var progress = Progress()
        var errorCount = 0
        var totalFiles = 0
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey
        ]

        func scanNode(_ url: URL, depth: Int) -> DiskEntry? {
            if Task.isCancelled { return nil }
            let name = url.lastPathComponent
            var values: URLResourceValues?
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                errorCount += 1
            }

            // 符号链接默认跳过（避免循环引用与重复统计）
            if values?.isSymbolicLink == true && !options.followSymlinks { return nil }

            let modDate = values?.contentModificationDate

            if values?.isDirectory != true {
                let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                totalFiles += 1
                progress.scannedFiles += 1
                progress.currentPath = url.path
                if progress.scannedFiles % 500 == 0 { onProgress?(progress) }
                let entry = DiskEntry(
                    name: name, url: url, size: size, isDirectory: false,
                    children: nil, fileCount: 1, modificationDate: modDate
                )
                if options.collectLargeFiles, size >= options.largeFilesMinSize {
                    largeFiles.append(entry)
                }
                return entry
            }

            // 目录：递归子项，聚合大小
            let maxReached = options.maxDepth.map { depth >= $0 } ?? false
            var childURLs: [URL] = []
            if !maxReached {
                do {
                    childURLs = try fileManager.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: Array(resourceKeys),
                        options: options.skipHiddenFiles ? [.skipsHiddenFiles] : []
                    )
                } catch {
                    errorCount += 1
                }
            }
            var children: [DiskEntry] = []
            var size: Int64 = 0
            var fileCount = 0
            for childURL in childURLs {
                if Task.isCancelled { break }
                if let child = scanNode(childURL, depth: depth + 1) {
                    children.append(child)
                    size += child.size
                    fileCount += child.fileCount
                }
            }
            children.sort { $0.size > $1.size }
            progress.scannedFiles += 1
            progress.currentPath = url.path
            if progress.scannedFiles % 500 == 0 { onProgress?(progress) }
            return DiskEntry(
                name: name, url: url, size: size, isDirectory: true,
                children: children, fileCount: fileCount, modificationDate: modDate
            )
        }

        guard let rootEntry = scanNode(root, depth: 0) else {
            return Result(
                root: DiskEntry(name: root.lastPathComponent, url: root, size: 0,
                                isDirectory: true, children: [], fileCount: 0),
                largeFiles: [], errorCount: 1, totalFiles: 0
            )
        }
        onProgress?(progress)

        if options.collectLargeFiles {
            largeFiles.sort { $0.size > $1.size }
            if largeFiles.count > options.largeFilesLimit {
                largeFiles = Array(largeFiles.prefix(options.largeFilesLimit))
            }
        }
        return Result(root: rootEntry, largeFiles: largeFiles, errorCount: errorCount, totalFiles: totalFiles)
    }
}
