import Foundation

// MARK: - 项目产物清理（对应 `mo purge`）

/// 项目类型，按项目根顶层的清单文件识别。
/// 清理策略：优先用该类型的官方清理命令（flutter clean / cargo clean 等），
/// 无命令的类型对已知产物目录执行移入废纸篓。
enum ProjectType: String, CaseIterable, Identifiable {
    case flutter
    case rust
    case swiftPackage
    case node
    case gradle
    case xcode
    case python
    case cocoapods
    /// 未能识别类型的项目：退回通用产物目录名匹配
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flutter: "Flutter"
        case .rust: "Rust"
        case .swiftPackage: "SwiftPM"
        case .node: "Node.js"
        case .gradle: "Android / Gradle"
        case .xcode: "Xcode"
        case .python: "Python"
        case .cocoapods: "CocoaPods"
        case .unknown: "未识别"
        }
    }

    var symbol: String {
        switch self {
        case .flutter: "bird"
        case .rust: "flame"
        case .swiftPackage: "swift"
        case .node: "cube.box"
        case .gradle: "building.2"
        case .xcode: "hammer"
        case .python: "snake"
        case .cocoapods: "square.stack.3d.up"
        case .unknown: "questionmark.folder"
        }
    }

    /// 顶层清单文件（存在任一即识别该类型）。
    var detectionFiles: [String] {
        switch self {
        case .flutter: ["pubspec.yaml"]
        case .rust: ["Cargo.toml"]
        case .swiftPackage: ["Package.swift"]
        case .node: ["package.json"]
        case .gradle: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
        case .xcode: []
        case .python: ["requirements.txt", "pyproject.toml", "Pipfile", "setup.py"]
        case .cocoapods: ["Podfile"]
        case .unknown: []
        }
    }

    /// 顶层目录后缀（*.xcodeproj / *.xcworkspace 等）。
    var detectionSuffixes: [String] {
        switch self {
        case .xcode: [".xcodeproj", ".xcworkspace"]
        default: []
        }
    }

    /// 识别项目类型（按 allCases 顺序，优先级高者先匹配）。
    /// 目录自身后缀（*.xcodeproj）与顶层清单文件/后缀目录均可命中。
    static func detect(in url: URL) -> ProjectType {
        let name = url.lastPathComponent
        let children = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        for type in allCases {
            if type.detectionSuffixes.contains(where: { name.hasSuffix($0) }) { return type }
            for child in children {
                if type.detectionFiles.contains(child) { return type }
                if type.detectionSuffixes.contains(where: { child.hasSuffix($0) }) { return type }
            }
        }
        return .unknown
    }

    /// 该类型项目下可清理的产物目录名（任意深度匹配）。
    /// 已知类型只用自身清单——不会误删其他类型的目录（更安全）。
    var artifactDirNames: [String] {
        switch self {
        case .flutter: [".dart_tool", "build", "ephemeral", "Pods", ".gradle", ".cxx", ".kotlin", ".symlinks"]
        case .rust: ["target"]
        case .swiftPackage: [".build", ".swiftpm"]
        case .node: ["node_modules", "dist", "build"]
        case .gradle: ["build", ".gradle", ".cxx", ".kotlin", ".externalNativeBuild", "captures"]
        case .xcode: ["build", "DerivedData", "xcuserdata", "Pods"]
        case .python: ["venv", ".venv", "__pycache__", ".mypy_cache", ".pytest_cache"]
        case .cocoapods: ["Pods", "build"]
        case .unknown: ArtifactType.allCases.flatMap { $0.dirNames }
        }
    }

    /// 官方清理命令（nil 表示无命令，对产物目录执行移入废纸篓）。
    var cleanCommand: String? {
        switch self {
        case .flutter: "flutter clean"
        case .rust: "cargo clean"
        case .swiftPackage: "swift package clean"
        case .gradle: "./gradlew clean"
        default: nil
        }
    }

    /// 清理方式展示文案。
    var cleanLabel: String {
        cleanCommand ?? "移入废纸篓"
    }
}

/// 通用产物目录名（unknown 类型回退用，兼容旧目录名匹配）。
enum ArtifactType: String, CaseIterable {
    case nodeModules, buildDir, dist, dotBuild, pods, xcUserData, target, venv
    case dartTool, ephemeral, gradleCache, cxxCache, kotlinCache, externalNativeBuild, captures

    var dirNames: [String] {
        switch self {
        case .nodeModules: ["node_modules"]
        case .buildDir: ["build"]
        case .dist: ["dist"]
        case .dotBuild: [".build"]
        case .pods: ["Pods"]
        case .xcUserData: ["xcuserdata"]
        case .target: ["target"]
        case .venv: ["venv", ".venv"]
        case .dartTool: [".dart_tool"]
        case .ephemeral: ["ephemeral"]
        case .gradleCache: [".gradle"]
        case .cxxCache: [".cxx"]
        case .kotlinCache: [".kotlin"]
        case .externalNativeBuild: [".externalNativeBuild"]
        case .captures: ["captures"]
        }
    }
}

/// 单个产物目录明细。
struct PurgeArtifact: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let fileCount: Int
}

/// 一个项目级清理候选：项目根 + 类型 + 该项目的产物清单。
struct PurgeCandidate: Identifiable {
    let id = UUID()
    let projectURL: URL
    let projectName: String
    let type: ProjectType
    let artifacts: [PurgeArtifact]
    let totalSize: Int64
    let fileCount: Int
    /// 7 天内修改过（可能是活跃项目，默认不勾选）
    let isRecent: Bool

    var usesCommand: Bool { type.cleanCommand != nil }
    var cleanLabel: String { type.cleanLabel }
}

// MARK: - 安装包清理（对应 `mo installer`）

/// 安装包来源。
enum InstallerSource: String, CaseIterable, Identifiable {
    case downloads
    case desktop
    case documents
    case homebrew
    case iCloud
    case mail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "下载"
        case .desktop: "桌面"
        case .documents: "文稿"
        case .homebrew: "Homebrew 缓存"
        case .iCloud: "iCloud 云盘"
        case .mail: "邮件下载"
        }
    }

    var searchDirs: [URL] {
        let home = NSHomeDirectory()
        switch self {
        case .downloads: return [URL(fileURLWithPath: home + "/Downloads")]
        case .desktop: return [URL(fileURLWithPath: home + "/Desktop")]
        case .documents: return [URL(fileURLWithPath: home + "/Documents")]
        case .homebrew: return [
            URL(fileURLWithPath: home + "/Library/Caches/Homebrew/downloads"),
            URL(fileURLWithPath: home + "/Library/Caches/Homebrew")
        ]
        // iCloud 云盘开启时，桌面/文稿也可能在云盘下
        case .iCloud: return [
            URL(fileURLWithPath: home + "/Library/Mobile Documents/com~apple~CloudDocs/Downloads"),
            URL(fileURLWithPath: home + "/Library/Mobile Documents/com~apple~CloudDocs/Desktop"),
            URL(fileURLWithPath: home + "/Library/Mobile Documents/com~apple~CloudDocs/Documents")
        ]
        case .mail: return [URL(fileURLWithPath: home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads")]
        }
    }
}

/// 一个安装包文件。
struct InstallerFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let source: InstallerSource
}
