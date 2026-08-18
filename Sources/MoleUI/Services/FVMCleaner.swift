import Foundation

/// FVM 版本安全清理与项目配置迁移服务
public final class FVMCleaner: Sendable {
    public static let shared = FVMCleaner()

    public init() {}

    /// 将指定的 FVM SDK 版本目录移入废纸篓
    /// - Parameter versions: 要删除的版本列表
    /// - Returns: 成功清理的版本数量
    @discardableResult
    public func cleanVersions(_ versions: [FVMInstalledVersion]) throws -> Int {
        let urls = versions.map(\.path)
        let count = try TrashService.moveToTrash(urls)

        for version in versions {
            OperationLog.append(module: "fvm", "已将 FVM Flutter SDK [\(version.versionName)] 移入废纸篓")
        }

        return count
    }

    /// 将指定 Flutter 项目的 FVM 锁定版本升级/迁移到新版本
    /// - Parameters:
    ///   - project: 目标项目信息
    ///   - targetVersion: 新目标版本名称（如 "3.24.5"）
    ///   - fvmVersionsDir: FVM versions 目录（用于重建软链接）
    public func migrateProject(
        project: FlutterProjectInfo,
        toVersion targetVersion: String,
        fvmVersionsDir: URL?
    ) throws {
        let fm = FileManager.default
        let fvmDir = project.path.appendingPathComponent(".fvm")

        // 1. 确保 .fvm 目录存在
        if !fm.fileExists(atPath: fvmDir.path) {
            try fm.createDirectory(at: fvmDir, withIntermediateDirectories: true)
        }

        // 2. 更新或创建 .fvm/fvm_config.json
        let configUrl = fvmDir.appendingPathComponent("fvm_config.json")
        var configDict: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: configUrl),
           let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            configDict = json
        }
        configDict["flutterSdkVersion"] = targetVersion
        configDict["flutter"] = targetVersion

        let data = try JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configUrl)

        // 3. 更新 .fvmrc（如果存在）
        let fvmrcUrl = project.path.appendingPathComponent(".fvmrc")
        if fm.fileExists(atPath: fvmrcUrl.path) {
            if let existingData = try? Data(contentsOf: fvmrcUrl),
               let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                var updatedJson = json
                updatedJson["flutter"] = targetVersion
                if let updatedData = try? JSONSerialization.data(withJSONObject: updatedJson, options: [.prettyPrinted]) {
                    try? updatedData.write(to: fvmrcUrl)
                }
            } else {
                try? targetVersion.write(to: fvmrcUrl, atomically: true, encoding: .utf8)
            }
        }

        // 4. 重建 .fvm/flutter_sdk 符号链接（若能定位目标版本路径）
        if let fvmVersionsDir {
            let targetSdkUrl = fvmVersionsDir.appendingPathComponent(targetVersion)
            let symlinkUrl = fvmDir.appendingPathComponent("flutter_sdk")

            // 移除旧符号链接/文件
            try? fm.removeItem(at: symlinkUrl)

            // 创建指向新版本的符号链接
            if fm.fileExists(atPath: targetSdkUrl.path) {
                try? fm.createSymbolicLink(at: symlinkUrl, withDestinationURL: targetSdkUrl)
            }
        }

        OperationLog.append(module: "fvm", "已将项目 [\(project.name)] 关联版本更新为 \(targetVersion)")
    }
}
