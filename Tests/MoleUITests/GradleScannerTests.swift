import XCTest
@testable import MoleUI

final class GradleScannerTests: XCTestCase {
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
        let distsDir = tempDir.appendingPathComponent("dists")
        try fm.createDirectory(at: distsDir, withIntermediateDirectories: true)

        let g89 = distsDir.appendingPathComponent("gradle-8.9-all")
        let g76 = distsDir.appendingPathComponent("gradle-7.6.1-bin")
        try fm.createDirectory(at: g89, withIntermediateDirectories: true)
        try fm.createDirectory(at: g76, withIntermediateDirectories: true)

        try "fake binary 8.9".write(to: g89.appendingPathComponent("gradle.zip"), atomically: true, encoding: .utf8)
        try "fake binary 7.6".write(to: g76.appendingPathComponent("gradle.zip"), atomically: true, encoding: .utf8)

        let scanner = GradleScanner()
        let versions = scanner.scanInstalledVersions(in: distsDir)

        XCTAssertEqual(versions.count, 2)
        XCTAssertTrue(versions.contains(where: { $0.versionName == "gradle-8.9-all" }))
        XCTAssertTrue(versions.contains(where: { $0.versionName == "gradle-7.6.1-bin" }))
        XCTAssertGreaterThan(versions.first?.diskSizeBytes ?? 0, 0)
    }

    func testExtractGradleVersion() {
        let scanner = GradleScanner()
        let sampleContent = """
        distributionBase=GRADLE_USER_HOME
        distributionPath=wrapper/dists
        distributionUrl=https\\://services.gradle.org/distributions/gradle-8.9-all.zip
        zipStoreBase=GRADLE_USER_HOME
        zipStorePath=wrapper/dists
        """

        let (ver, url) = scanner.extractGradleVersion(from: sampleContent)
        XCTAssertEqual(ver, "gradle-8.9-all")
        XCTAssertEqual(url, "https://services.gradle.org/distributions/gradle-8.9-all.zip")
    }

    func testCorrelateGradleVersionsAndStatus() {
        let v67 = GradleInstalledVersion(versionName: "gradle-6.7.1-all", path: URL(fileURLWithPath: "/dists/6.7.1"), diskSizeBytes: 100)
        let v84 = GradleInstalledVersion(versionName: "gradle-8.4-bin", path: URL(fileURLWithPath: "/dists/8.4"), diskSizeBytes: 100)
        let v89 = GradleInstalledVersion(versionName: "gradle-8.9-bin", path: URL(fileURLWithPath: "/dists/8.9"), diskSizeBytes: 100)

        let staleProject = GradleProjectInfo(
            name: "OldAndroidApp",
            path: URL(fileURLWithPath: "/projects/OldAndroidApp"),
            declaredVersion: "gradle-8.4-bin",
            lastModifiedDate: Date().addingTimeInterval(-200 * 24 * 3600)
        )

        let activeProject = GradleProjectInfo(
            name: "ActiveAndroidApp",
            path: URL(fileURLWithPath: "/projects/ActiveAndroidApp"),
            declaredVersion: "gradle-8.9-bin",
            lastModifiedDate: Date()
        )

        let scanner = GradleScanner()
        let correlated = scanner.correlate(
            versions: [v67, v84, v89],
            with: [staleProject, activeProject]
        )

        // 1. gradle-6.7.1-all 无项目引用 -> safeToClean
        let r67 = correlated.first { $0.versionName == "gradle-6.7.1-all" }
        XCTAssertEqual(r67?.status, .safeToClean)

        // 2. gradle-8.9-bin 被活跃项目引用 -> activeInUse
        let r89 = correlated.first { $0.versionName == "gradle-8.9-bin" }
        XCTAssertEqual(r89?.status, .activeInUse)

        // 3. gradle-8.4-bin 仅被陈旧项目引用且有更高已装版本 8.9-bin -> redundantPatch
        let r84 = correlated.first { $0.versionName == "gradle-8.4-bin" }
        XCTAssertEqual(r84?.status, .redundantPatch)
        XCTAssertEqual(r84?.alternativeVersion, "gradle-8.9-bin")
    }

    func testMigrateGradleWrapperProperties() throws {
        let projectDir = tempDir.appendingPathComponent("SampleApp")
        let wrapperDir = projectDir.appendingPathComponent("gradle/wrapper")
        try FileManager.default.createDirectory(at: wrapperDir, withIntermediateDirectories: true)

        let propUrl = wrapperDir.appendingPathComponent("gradle-wrapper.properties")
        let originalContent = """
        distributionBase=GRADLE_USER_HOME
        distributionPath=wrapper/dists
        distributionUrl=https\\://services.gradle.org/distributions/gradle-8.4-bin.zip
        zipStoreBase=GRADLE_USER_HOME
        zipStorePath=wrapper/dists
        """
        try originalContent.write(to: propUrl, atomically: true, encoding: .utf8)

        let project = GradleProjectInfo(
            name: "SampleApp",
            path: projectDir,
            wrapperPropertiesPath: propUrl,
            declaredVersion: "gradle-8.4-bin",
            lastModifiedDate: Date()
        )

        let cleaner = GradleCleaner()
        try cleaner.migrateProject(project: project, toVersion: "gradle-8.9-bin")

        let updatedContent = try String(contentsOf: propUrl, encoding: .utf8)
        XCTAssertTrue(updatedContent.contains("gradle-8.9-bin.zip"))
    }
}
