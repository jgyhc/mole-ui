import Foundation

/// 深度清理的扫描分类（对应 `mo clean`）。
enum CleanCategory: String, CaseIterable, Identifiable {
    case userCaches
    case browserCaches
    case logs
    case devCaches
    case leftovers
    case trash
    case temp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches: "用户应用缓存"
        case .browserCaches: "浏览器缓存"
        case .logs: "日志文件"
        case .devCaches: "开发者工具缓存"
        case .leftovers: "卸载残留"
        case .trash: "废纸篓"
        case .temp: "临时文件"
        }
    }

    var symbol: String {
        switch self {
        case .userCaches: "folder"
        case .browserCaches: "globe"
        case .logs: "doc.text"
        case .devCaches: "hammer"
        case .leftovers: "archivebox"
        case .trash: "trash"
        case .temp: "clock"
        }
    }

    /// 扫描根路径（残留类为空，单独处理）。
    var rootPaths: [URL] {
        func home(_ path: String) -> URL {
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
        }
        switch self {
        case .userCaches:
            return [home("Library/Caches")]
        case .browserCaches:
            return [
                home("Library/Caches/com.google.Chrome"),
                home("Library/Caches/Google/Chrome"),
                home("Library/Caches/com.apple.Safari"),
                home("Library/Caches/Firefox")
            ]
        case .logs:
            return [home("Library/Logs")]
        case .devCaches:
            return [
                home("Library/Developer/Xcode/DerivedData"),
                home(".npm/_cacache"),
                home(".gradle/caches"),
                home("Library/Caches/CocoaPods"),
                home("Library/Caches/go-build"),
                home("Library/Caches/pip"),
                home("Library/Caches/Yarn"),
                home(".cache")
            ]
        case .leftovers:
            return []
        case .trash:
            return [home(".Trash")]
        case .temp:
            return [URL(fileURLWithPath: "/private/tmp")]
        }
    }

    /// 默认是否勾选（危险类别默认不勾选，由用户确认）
    var defaultSelected: Bool {
        switch self {
        case .trash, .temp, .leftovers: false
        default: true
        }
    }

    /// 危险标记（废纸篓永久删除、临时文件误删风险高）
    var isDangerous: Bool {
        self == .trash || self == .temp
    }

    /// 清理方式：废纸篓内容为永久删除，其余移入废纸篓
    var isPermanentDelete: Bool {
        self == .trash
    }
}

/// 可清理的单个条目。
struct CleanItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let fileCount: Int
    let category: CleanCategory

    var isPermanent: Bool { category.isPermanentDelete }
}

/// 一个分类的扫描结果。
struct CleanCategoryResult: Identifiable {
    var id: String { category.id }
    let category: CleanCategory
    let totalSize: Int64
    let items: [CleanItem]
    let errorCount: Int
}

/// 扫描进度。
struct CleanScanProgress {
    var currentCategory: String = ""
    var scannedFiles: Int = 0
}
