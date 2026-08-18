import Foundation
import AppKit

/// 文件类型分类（用于树图着色与分类统计）。
enum FileCategory: String, CaseIterable {
    case directory, app, image, video, audio, document, archive, code, system, other

    var displayName: String {
        switch self {
        case .directory: return "文件夹"
        case .app: return "应用程序"
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case .document: return "文稿"
        case .archive: return "归档与镜像"
        case .code: return "代码与工程"
        case .system: return "系统与框架"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .directory: return "folder.fill"
        case .app: return "app.badge.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .document: return "doc.text.fill"
        case .archive: return "archivebox.fill"
        case .code: return "curlybraces"
        case .system: return "gearshape.2.fill"
        case .other: return "doc.fill"
        }
    }
}

extension FileCategory {
    /// 根据文件名（含扩展名）与是否为目录分类。
    static func of(name: String, isDirectory: Bool) -> FileCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "app" { return .app }
        if ext == "framework" || ext == "bundle" || ext == "kext" || ext == "systemextension" || ext == "appex" {
            return .system
        }
        if isDirectory { return .directory }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "raw", "svg", "avif", "ico", "psd":
            return .image
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "flv", "wmv", "3gp", "mpg", "mpeg":
            return .video
        case "mp3", "wav", "aac", "flac", "m4a", "ogg", "wma", "aiff", "opus", "caf", "mid", "midi":
            return .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md", "pages",
             "numbers", "key", "epub", "csv", "tsv":
            return .document
        case "zip", "dmg", "pkg", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "cab", "zst":
            return .archive
        case "swift", "m", "mm", "h", "c", "cpp", "cc", "js", "ts", "py", "rb", "go", "rs", "java",
             "kt", "html", "css", "json", "yml", "yaml", "xml", "plist", "sh", "sql", "ipynb",
             "toml", "lock", "proto", "vue", "jsx", "tsx":
            return .code
        default:
            return .other
        }
    }
}

/// 磁盘分析树节点。
struct DiskEntry: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    /// 占用的磁盘空间（文件为自身大小，目录为子树合计）
    let size: Int64
    let isDirectory: Bool
    /// 目录的子树（文件为 nil）；扫描完成后按大小降序排列
    var children: [DiskEntry]?
    /// 文件数（目录为子树内文件总数）
    let fileCount: Int
    /// 修改时间
    let modificationDate: Date?

    init(name: String, url: URL, size: Int64, isDirectory: Bool, children: [DiskEntry]? = nil, fileCount: Int = 1, modificationDate: Date? = nil) {
        self.name = name
        self.url = url
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.fileCount = fileCount
        self.modificationDate = modificationDate
    }

    var category: FileCategory {
        FileCategory.of(name: name, isDirectory: isDirectory)
    }

    var sortedChildren: [DiskEntry] {
        (children ?? []).sorted { $0.size > $1.size }
    }

    /// 获取系统原生对应图标
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 友好显示的用户主目录相对路径或完整路径
    var abbreviatedPath: String {
        let home = NSHomeDirectory()
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// 格式化修改时间
    var formattedDate: String {
        guard let date = modificationDate else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 精确字节信息
    var formattedExactSize: String {
        let formatted = ByteFormatter.fileString(from: size)
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        let bytesStr = numberFormatter.string(from: NSNumber(value: size)) ?? "\(size)"
        return "\(formatted) (\(bytesStr) 字节)"
    }
}
