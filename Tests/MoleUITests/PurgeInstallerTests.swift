import XCTest
@testable import MoleUI

final class PurgeEngineTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-purge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    // MARK: - 项目类型识别

    func testProjectTypeDetection() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        func detect(in dir: String, file: String? = nil) -> ProjectType {
            let url = root.appendingPathComponent(dir)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if let file {
                try? Data(repeating: 0, count: 1).write(to: url.appendingPathComponent(file))
            }
            return ProjectType.detect(in: url)
        }

        XCTAssertEqual(detect(in: "f1", file: "pubspec.yaml"), .flutter)
        XCTAssertEqual(detect(in: "r1", file: "Cargo.toml"), .rust)
        XCTAssertEqual(detect(in: "s1", file: "Package.swift"), .swiftPackage)
        XCTAssertEqual(detect(in: "n1", file: "package.json"), .node)
        XCTAssertEqual(detect(in: "g1", file: "build.gradle"), .gradle)
        XCTAssertEqual(detect(in: "g2", file: "settings.gradle.kts"), .gradle)
        XCTAssertEqual(detect(in: "p1", file: "Podfile"), .cocoapods)
        XCTAssertEqual(detect(in: "y1", file: "pyproject.toml"), .python)

        // *.xcodeproj 目录自身即 Xcode 项目
        let xcode = root.appendingPathComponent("App.xcodeproj")
        try? FileManager.default.createDirectory(at: xcode, withIntermediateDirectories: true)
        XCTAssertEqual(ProjectType.detect(in: xcode), .xcode)

        XCTAssertEqual(detect(in: "u1"), .unknown)
    }

    func testTypeScopedArtifactLists() {
        // Flutter 只认 Flutter 产物（不含 node_modules）；Node 不认 .dart_tool
        XCTAssertTrue(ProjectType.flutter.artifactDirNames.contains(".dart_tool"))
        XCTAssertTrue(ProjectType.flutter.artifactDirNames.contains("build"))
        XCTAssertFalse(ProjectType.flutter.artifactDirNames.contains("node_modules"))
        XCTAssertTrue(ProjectType.node.artifactDirNames.contains("node_modules"))
        XCTAssertFalse(ProjectType.node.artifactDirNames.contains(".dart_tool"))
        XCTAssertTrue(ProjectType.rust.artifactDirNames.contains("target"))
        XCTAssertTrue(ProjectType.swiftPackage.artifactDirNames.contains(".build"))
        XCTAssertTrue(ProjectType.xcode.artifactDirNames.contains("xcuserdata"))
    }

    func testCleanCommandsByType() {
        XCTAssertEqual(ProjectType.flutter.cleanCommand, "flutter clean")
        XCTAssertEqual(ProjectType.rust.cleanCommand, "cargo clean")
        XCTAssertEqual(ProjectType.swiftPackage.cleanCommand, "swift package clean")
        XCTAssertEqual(ProjectType.gradle.cleanCommand, "./gradlew clean")
        XCTAssertNil(ProjectType.node.cleanCommand)
        XCTAssertNil(ProjectType.xcode.cleanCommand)
        XCTAssertNil(ProjectType.unknown.cleanCommand)
    }

    // MARK: - 扫描（临时目录）

    func testScanFindsTypedProjects() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // my-app（Node）：node_modules 1KB
        let app = root.appendingPathComponent("my-app")
        let nodeModules = app.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 1024).write(to: nodeModules.appendingPathComponent("a.bin"))
        try Data(repeating: 0, count: 1).write(to: app.appendingPathComponent("package.json"))

        // rust-proj（Rust）：target 2KB
        let rust = root.appendingPathComponent("rust-proj")
        let target = rust.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 2048).write(to: target.appendingPathComponent("b.bin"))
        try Data(repeating: 0, count: 1).write(to: rust.appendingPathComponent("Cargo.toml"))

        let candidates = PurgeEngine.scan(roots: [root])

        XCTAssertEqual(candidates.count, 2)
        guard let node = candidates.first(where: { $0.projectName == "my-app" }),
              let rustCandidate = candidates.first(where: { $0.projectName == "rust-proj" }) else {
            XCTFail("未找到预期项目")
            return
        }
        XCTAssertEqual(node.type, .node)
        XCTAssertEqual(node.artifacts.count, 1)
        XCTAssertEqual(node.artifacts[0].name, "node_modules")
        XCTAssertGreaterThanOrEqual(node.totalSize, 1024)
        XCTAssertEqual(rustCandidate.type, .rust)
        XCTAssertEqual(rustCandidate.artifacts[0].name, "target")
        // 按大小降序
        XCTAssertGreaterThanOrEqual(candidates[0].totalSize, candidates[1].totalSize)
    }

    func testFlutterProjectCollectsOnlyFlutterArtifacts() throws {
        // 安全关键：Flutter 项目里的 node_modules 不被收集（类型化清单）
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("fapp")
        try FileManager.default.createDirectory(at: app.appendingPathComponent(".dart_tool"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("build"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512).write(to: app.appendingPathComponent(".dart_tool/package_config.json"))
        try Data(repeating: 0, count: 256).write(to: app.appendingPathComponent("build/x.o"))
        try Data(repeating: 0, count: 1024).write(to: app.appendingPathComponent("node_modules/x.js"))
        try Data(repeating: 0, count: 1).write(to: app.appendingPathComponent("pubspec.yaml"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 1)
        let candidate = candidates[0]
        XCTAssertEqual(candidate.type, .flutter)
        XCTAssertEqual(Set(candidate.artifacts.map { $0.name }), [".dart_tool", "build"])
        XCTAssertFalse(candidate.artifacts.contains { $0.name == "node_modules" })
    }

    func testUnknownProjectFallsBackToFullArtifactSet() throws {
        // 未识别类型的项目（无清单文件）退回通用目录名匹配
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let proj = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: proj.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: proj.appendingPathComponent(".dart_tool"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512).write(to: proj.appendingPathComponent("node_modules/a.js"))
        try Data(repeating: 0, count: 256).write(to: proj.appendingPathComponent(".dart_tool/b.json"))

        // 无清单文件即 unknown；项目根判定需要标记，故在子目录放 package.json 触发一层检测
        try FileManager.default.createDirectory(at: proj.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1).write(to: proj.appendingPathComponent("sub/package.json"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].type, .unknown)
        XCTAssertEqual(Set(candidates[0].artifacts.map { $0.name }), ["node_modules", ".dart_tool"])
    }

    func testScanFindsHiddenArtifacts() throws {
        // 回归：.build / .dart_tool 等隐藏目录必须能被扫描到
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let swiftApp = root.appendingPathComponent("swift-app")
        let build = swiftApp.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 2048).write(to: build.appendingPathComponent("x.o"))
        try Data(repeating: 0, count: 1).write(to: swiftApp.appendingPathComponent("Package.swift"))

        let flutterApp = root.appendingPathComponent("flutter-app")
        let dartTool = flutterApp.appendingPathComponent(".dart_tool")
        try FileManager.default.createDirectory(at: dartTool, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 1024).write(to: dartTool.appendingPathComponent("package_config.json"))
        try Data(repeating: 0, count: 1).write(to: flutterApp.appendingPathComponent("pubspec.yaml"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 2)
        XCTAssertNotNil(candidates.first { $0.type == .swiftPackage })
        XCTAssertNotNil(candidates.first { $0.type == .flutter })
    }

    func testScanFindsAndroidWrapperArtifacts() throws {
        // myapp 无顶层标记（标记在 android/ 一层）→ unknown 类型，仍收集 gradle 产物
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("myapp")
        let android = app.appendingPathComponent("android")
        let androidApp = android.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: androidApp.appendingPathComponent(".cxx"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: android.appendingPathComponent(".gradle"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: androidApp.appendingPathComponent(".kotlin"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512).write(to: androidApp.appendingPathComponent(".cxx/CMakeCache.txt"))
        try Data(repeating: 0, count: 512).write(to: android.appendingPathComponent(".gradle/caches.txt"))
        try Data(repeating: 0, count: 512).write(to: androidApp.appendingPathComponent(".kotlin/session.bin"))
        try Data(repeating: 0, count: 1).write(to: android.appendingPathComponent("build.gradle"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].projectName, "myapp")
        XCTAssertEqual(Set(candidates[0].artifacts.map { $0.name }), [".cxx", ".gradle", ".kotlin"])
    }

    func testScanFindsFlutterEphemeral() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("fapp")
        let ephemeral = app.appendingPathComponent("ios/Flutter/ephemeral")
        try FileManager.default.createDirectory(at: ephemeral, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2048).write(to: ephemeral.appendingPathComponent("Flutter-generated.xcconfig"))
        try Data(repeating: 0, count: 1).write(to: app.appendingPathComponent("pubspec.yaml"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].type, .flutter)
        XCTAssertEqual(candidates[0].projectName, "fapp")
        XCTAssertEqual(candidates[0].artifacts[0].name, "ephemeral")
        XCTAssertGreaterThanOrEqual(candidates[0].totalSize, 2048)
    }

    func testScanFindsXcodeUserData() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let xcodeproj = root.appendingPathComponent("Sample.xcodeproj/xcuserdata/liucong.xcuserdatad")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024).write(to: xcodeproj.appendingPathComponent("UserInterfaceState.xcuserstate"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].type, .xcode)
        XCTAssertEqual(candidates[0].projectName, "Sample.xcodeproj")
        XCTAssertEqual(candidates[0].artifacts[0].name, "xcuserdata")
    }

    func testNestedProjectDoesNotDuplicateArtifacts() throws {
        // monorepo：proj1（Node）内含 sub（SwiftPM）——产物互不重复
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let proj1 = root.appendingPathComponent("proj1")
        try FileManager.default.createDirectory(at: proj1.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512).write(to: proj1.appendingPathComponent("node_modules/a.js"))
        try Data(repeating: 0, count: 1).write(to: proj1.appendingPathComponent("package.json"))

        let sub = proj1.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 256).write(to: sub.appendingPathComponent(".build/x.o"))
        try Data(repeating: 0, count: 1).write(to: sub.appendingPathComponent("Package.swift"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 2)
        let node = candidates.first { $0.type == .node }
        let swift = candidates.first { $0.type == .swiftPackage }
        XCTAssertNotNil(node)
        XCTAssertNotNil(swift)
        XCTAssertEqual(node?.artifacts.map { $0.name }, ["node_modules"])
        XCTAssertEqual(swift?.artifacts.map { $0.name }, [".build"])
        XCTAssertEqual(node?.projectName, "proj1")
        XCTAssertEqual(swift?.projectName, "sub")
    }

    func testBareArtifactDirWithoutProjectIsIgnored() throws {
        // 安全关键：没有项目标记的裸 build 目录不再作为清理候选（必须有项目根）
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let container = root.appendingPathComponent("container")
        let build = container.appendingPathComponent("proj/build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512).write(to: build.appendingPathComponent("x.bin"))

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertTrue(candidates.isEmpty, "无项目标记的裸产物目录不应成为清理候选")
    }

    func testRecentFlag() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fresh = root.appendingPathComponent("fresh-app")
        let freshNM = fresh.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: freshNM, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: freshNM.appendingPathComponent("x.bin"))
        try Data(repeating: 0, count: 1).write(to: fresh.appendingPathComponent("package.json"))

        let old = root.appendingPathComponent("old-app")
        let oldNM = old.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: oldNM, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: oldNM.appendingPathComponent("y.bin"))
        try Data(repeating: 0, count: 1).write(to: old.appendingPathComponent("package.json"))
        let oldDate = Date().addingTimeInterval(-30 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: old.path
        )

        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.first { $0.projectName == "fresh-app" }?.isRecent == true)
        XCTAssertTrue(candidates.first { $0.projectName == "old-app" }?.isRecent == false)
    }

    func testScanSkipsSymlinkArtifacts() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("link-app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: app.appendingPathComponent("node_modules"),
            withDestinationURL: root
        )
        let candidates = PurgeEngine.scan(roots: [root])
        XCTAssertTrue(candidates.isEmpty, "符号链接产物不应被扫描")
    }

    // MARK: - 命令执行

    func testRunCommandSuccess() {
        let result = PurgeEngine.runCommand("echo hello")
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("hello"))
    }

    func testRunCommandFailure() {
        let result = PurgeEngine.runCommand("nonexistent-command-xyz")
        XCTAssertFalse(result.success)
    }

    // MARK: - 清理

    func testCleanTrashesArtifactsForNoCommand() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10).write(to: file.appendingPathComponent("a.js"))

        let candidate = PurgeCandidate(
            projectURL: dir, projectName: "proj", type: .node,
            artifacts: [PurgeArtifact(url: file, name: "node_modules", size: 10, fileCount: 1)],
            totalSize: 10, fileCount: 1, isRecent: false
        )
        let outcome = PurgeEngine.clean(candidates: [candidate])
        XCTAssertEqual(outcome.trashed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(outcome.failures.isEmpty)
    }

    func testCleanSkipsProtectedPath() {
        let candidate = PurgeCandidate(
            projectURL: URL(fileURLWithPath: NSHomeDirectory()), projectName: "home", type: .unknown,
            artifacts: [PurgeArtifact(url: URL(fileURLWithPath: NSHomeDirectory()), name: "home", size: 1, fileCount: 0)],
            totalSize: 1, fileCount: 0, isRecent: false
        )
        let outcome = PurgeEngine.clean(candidates: [candidate])
        XCTAssertEqual(outcome.trashed, 0)
    }

    func testCleanReportsProgressPerCandidate() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var candidates: [PurgeCandidate] = []
        for name in ["proj-a", "proj-b", "proj-c"] {
            let proj = dir.appendingPathComponent(name)
            let nm = proj.appendingPathComponent("node_modules")
            try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
            try Data(repeating: 0, count: 10).write(to: nm.appendingPathComponent("x.js"))
            candidates.append(PurgeCandidate(
                projectURL: proj, projectName: name, type: .node,
                artifacts: [PurgeArtifact(url: nm, name: "node_modules", size: 10, fileCount: 1)],
                totalSize: 10, fileCount: 1, isRecent: false
            ))
        }

        var progress: [(label: String, completed: Int, total: Int)] = []
        let outcome = PurgeEngine.clean(candidates: candidates) { label, completed, total in
            progress.append((label, completed, total))
        }

        XCTAssertEqual(outcome.trashed, 3)
        XCTAssertEqual(progress.count, 3)
        XCTAssertEqual(progress.map { $0.completed }, [1, 2, 3])
        XCTAssertEqual(progress.map { $0.total }, [3, 3, 3])
        XCTAssertEqual(progress[0].label, "proj-a（移入废纸篓）")
        XCTAssertTrue(progress.allSatisfy { $0.label.contains("移入废纸篓") })
    }

    // MARK: - 默认扫描目录

    func testDefaultRootsOnlyExisting() {
        let roots = PurgeEngine.defaultRoots
        for root in roots {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        }
    }

    func testDefaultRootsNeverContainProtectedDirs() {
        // 回归：默认扫描目录绝不能在页面加载时探测桌面/文稿/下载（TCC 保护目录，会触发权限弹窗）
        let protectedSuffixes = ["/Desktop", "/Documents", "/Downloads"]
        for root in PurgeEngine.defaultRoots {
            XCTAssertFalse(
                protectedSuffixes.contains { root.path.hasSuffix($0) },
                "默认扫描目录不应包含受保护目录: \(root.path)"
            )
        }
    }

    func testProjectRootDetectionDirectMarker() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(PurgeEngine.isProjectRoot(root), "空目录不应被识别为项目根")
        try Data(repeating: 0, count: 1).write(to: root.appendingPathComponent("Package.swift"))
        XCTAssertTrue(PurgeEngine.isProjectRoot(root))
    }

    func testProjectRootDetectionXcodeMarker() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(PurgeEngine.isProjectRoot(root))
    }

    func testProjectRootDetectionOneLevelDeep() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("my-app")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1).write(to: proj.appendingPathComponent("pubspec.yaml"))
        XCTAssertTrue(PurgeEngine.isProjectRoot(root), "一层子目录含清单文件也应识别")
    }

    func testProjectRootDetectionNoMarkers() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 1).write(to: root.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("photos"), withIntermediateDirectories: true)
        XCTAssertFalse(PurgeEngine.isProjectRoot(root))
    }
}

final class InstallerEngineTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    func testScanFindsInstallersWithSizeFilter() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bigDmg = Data(repeating: 0, count: 80 * 1024 * 1024) // 80MB
        let smallZip = Data(repeating: 0, count: 10 * 1024 * 1024) // 10MB，低于阈值
        try bigDmg.write(to: dir.appendingPathComponent("app.dmg"))
        try bigDmg.write(to: dir.appendingPathComponent("pkg.pkg"))
        try smallZip.write(to: dir.appendingPathComponent("small.zip"))
        // 非安装包扩展名应被忽略
        try Data(repeating: 0, count: 100 * 1024 * 1024).write(to: dir.appendingPathComponent("movie.mov"))

        let files = InstallerEngine.scan(
            searchDirectories: [(.downloads, dir)],
            minSize: 50 * 1024 * 1024
        )
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(files.map { $0.name }), ["app.dmg", "pkg.pkg"])
        XCTAssertTrue(files.allSatisfy { $0.source == .downloads })
        // 按大小降序
        XCTAssertGreaterThanOrEqual(files[0].size, files[1].size)
    }

    func testDefaultScansAllSizes() throws {
        // 默认不按大小过滤：小安装包也应列出
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(repeating: 0, count: 1024).write(to: dir.appendingPathComponent("tiny.dmg"))
        let files = InstallerEngine.scan(searchDirectories: [(.downloads, dir)])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "tiny.dmg")
    }

    func testScanSubdirectoriesDepth() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let nested = dir.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024).write(to: nested.appendingPathComponent("deep.dmg"))

        let files = InstallerEngine.scan(searchDirectories: [(.downloads, dir)])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "deep.dmg")
    }

    func testMatchesInstallerExtensions() {
        XCTAssertTrue(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.dmg")))
        XCTAssertTrue(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.pkg")))
        XCTAssertTrue(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.mpkg")))
        XCTAssertTrue(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.zip")))
        XCTAssertTrue(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.tgz")))
        XCTAssertTrue(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.iso")))
        // 复合后缀
        XCTAssertTrue(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.tar.gz")))
        XCTAssertFalse(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.gz")))
        XCTAssertFalse(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.tar.gz.txt")))
        XCTAssertFalse(InstallerEngine.isInstallerFile(url: URL(fileURLWithPath: "/tmp/a.mov")))
    }

    func testDeduplicatesOverlappingDirectories() throws {
        // Homebrew 根目录与其 downloads 子目录是父子关系：同一文件只应出现一次
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let downloads = dir.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024).write(to: downloads.appendingPathComponent("shared.dmg"))

        let files = InstallerEngine.scan(
            searchDirectories: [(.homebrew, dir), (.homebrew, downloads)]
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "shared.dmg")
    }

    func testCleanSkipsProtectedPath() throws {
        let file = InstallerFile(
            url: URL(fileURLWithPath: "/"),
            name: "root",
            size: 1,
            source: .downloads
        )
        let moved = try InstallerEngine.clean(files: [file])
        XCTAssertEqual(moved, 0)
    }

    func testExtensionSet() {
        XCTAssertTrue(InstallerEngine.fileExtensions.contains("dmg"))
        XCTAssertTrue(InstallerEngine.fileExtensions.contains("pkg"))
        XCTAssertTrue(InstallerEngine.fileExtensions.contains("mpkg"))
        XCTAssertTrue(InstallerEngine.fileExtensions.contains("zip"))
        XCTAssertTrue(InstallerEngine.fileExtensions.contains("tgz"))
        XCTAssertTrue(InstallerEngine.fileExtensions.contains("iso"))
    }
}
