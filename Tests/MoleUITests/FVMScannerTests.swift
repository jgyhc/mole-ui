import XCTest
@testable import MoleUI

final class FVMScannerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testScanInstalledVersions() throws {
        let fm = FileManager.default
        let fvmVersionsDir = tempDir.appendingPathComponent("versions")
        try fm.createDirectory(at: fvmVersionsDir, withIntermediateDirectories: true)

        // 创建两个版本目录: 3.24.5 与 3.19.1
        let v324 = fvmVersionsDir.appendingPathComponent("3.24.5")
        let v319 = fvmVersionsDir.appendingPathComponent("3.19.1")
        try fm.createDirectory(at: v324, withIntermediateDirectories: true)
        try fm.createDirectory(at: v319, withIntermediateDirectories: true)

        // 写入测试文件
        try "test flutter sdk 3.24".write(to: v324.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "test flutter sdk 3.19".write(to: v319.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        // 创建 default 软链接指向 3.24.5
        let defaultLink = fvmVersionsDir.appendingPathComponent("default")
        try fm.createSymbolicLink(at: defaultLink, withDestinationURL: v324)

        let scanner = FVMScanner()
        let versions = scanner.scanInstalledVersions(in: fvmVersionsDir)

        XCTAssertEqual(versions.count, 2)

        let ver324 = versions.first { $0.versionName == "3.24.5" }
        XCTAssertNotNil(ver324)
        XCTAssertTrue(ver324?.isGlobal == true)
        XCTAssertGreaterThan(ver324?.diskSizeBytes ?? 0, 0)

        let ver319 = versions.first { $0.versionName == "3.19.1" }
        XCTAssertNotNil(ver319)
        XCTAssertFalse(ver319?.isGlobal == true)
    }

    func testParseFlutterProjectWithFVMConfig() throws {
        let fm = FileManager.default
        let projectDir = tempDir.appendingPathComponent("DemoApp")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // 写入 pubspec.yaml
        let pubspecContent = """
        name: demo_app
        description: A demo flutter project
        environment:
          sdk: '>=3.0.0 <4.0.0'
        dependencies:
          flutter:
            sdk: flutter
        """
        try pubspecContent.write(to: projectDir.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)

        // 写入 .fvm/fvm_config.json
        let fvmDir = projectDir.appendingPathComponent(".fvm")
        try fm.createDirectory(at: fvmDir, withIntermediateDirectories: true)
        let configContent = """
        {
          "flutterSdkVersion": "3.19.6"
        }
        """
        try configContent.write(to: fvmDir.appendingPathComponent("fvm_config.json"), atomically: true, encoding: .utf8)

        let scanner = FVMScanner()
        let project = scanner.parseFlutterProject(at: projectDir)

        XCTAssertNotNil(project)
        XCTAssertEqual(project?.name, "demo_app")
        XCTAssertEqual(project?.declaredVersion, "3.19.6")
        XCTAssertEqual(project?.versionSource, .fvmConfig)
    }

    func testCorrelateVersionsAndStatus() {
        let v310 = FVMInstalledVersion(versionName: "3.10.6", path: URL(fileURLWithPath: "/fvm/3.10.6"), diskSizeBytes: 1000)
        let v3191 = FVMInstalledVersion(versionName: "3.19.1", path: URL(fileURLWithPath: "/fvm/3.19.1"), diskSizeBytes: 1000)
        let v3196 = FVMInstalledVersion(versionName: "3.19.6", path: URL(fileURLWithPath: "/fvm/3.19.6"), diskSizeBytes: 1000)
        let v324 = FVMInstalledVersion(versionName: "3.24.5", path: URL(fileURLWithPath: "/fvm/3.24.5"), diskSizeBytes: 1000, isGlobal: true)

        let staleProject = FlutterProjectInfo(
            name: "OldApp",
            path: URL(fileURLWithPath: "/projects/OldApp"),
            declaredVersion: "3.19.1",
            versionSource: .fvmConfig,
            lastModifiedDate: Date().addingTimeInterval(-200 * 24 * 3600) // 200 天前
        )

        let activeProject = FlutterProjectInfo(
            name: "NewApp",
            path: URL(fileURLWithPath: "/projects/NewApp"),
            declaredVersion: "3.19.6",
            versionSource: .fvmConfig,
            lastModifiedDate: Date()
        )

        let scanner = FVMScanner()
        let correlated = scanner.correlate(
            versions: [v310, v3191, v3196, v324],
            with: [staleProject, activeProject]
        )

        // 1. 3.10.6 无项目引用且非 global -> safeToClean
        let r310 = correlated.first { $0.versionName == "3.10.6" }
        XCTAssertEqual(r310?.status, .safeToClean)

        // 2. 3.24.5 为 global -> globalDefault
        let r324 = correlated.first { $0.versionName == "3.24.5" }
        XCTAssertEqual(r324?.status, .globalDefault)

        // 3. 3.19.6 被 activeProject 引用 -> activeInUse
        let r3196 = correlated.first { $0.versionName == "3.19.6" }
        XCTAssertEqual(r3196?.status, .activeInUse)

        // 4. 3.19.1 仅被 staleProject 引用，且本地装有更高版本的 3.19.6 -> redundantPatch 且 alternativeVersion 为 3.19.6
        let r3191 = correlated.first { $0.versionName == "3.19.1" }
        XCTAssertEqual(r3191?.status, .redundantPatch)
        XCTAssertEqual(r3191?.alternativeVersion, "3.19.6")
    }

    func testMigrateProject() async throws {
        let fm = FileManager.default
        let projectDir = tempDir.appendingPathComponent("MigrationApp")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let fvmVersionsDir = tempDir.appendingPathComponent("versions")
        let targetSdkDir = fvmVersionsDir.appendingPathComponent("3.24.5")
        try fm.createDirectory(at: targetSdkDir, withIntermediateDirectories: true)

        let project = FlutterProjectInfo(
            name: "MigrationApp",
            path: projectDir,
            declaredVersion: "3.19.1",
            versionSource: .fvmConfig,
            lastModifiedDate: Date()
        )

        let cleaner = FVMCleaner()
        try cleaner.migrateProject(
            project: project,
            toVersion: "3.24.5",
            fvmVersionsDir: fvmVersionsDir
        )

        // 验证 .fvm/fvm_config.json 被正确更新
        let configUrl = projectDir.appendingPathComponent(".fvm/fvm_config.json")
        let data = try Data(contentsOf: configUrl)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["flutterSdkVersion"] as? String, "3.24.5")

        // 验证软链接
        let symlinkUrl = projectDir.appendingPathComponent(".fvm/flutter_sdk")
        let dest = try fm.destinationOfSymbolicLink(atPath: symlinkUrl.path)
        XCTAssertTrue(dest.hasSuffix("3.24.5"))
    }
}
