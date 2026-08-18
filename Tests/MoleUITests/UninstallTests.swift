import XCTest
@testable import MoleUI

final class UninstallTests: XCTestCase {
    private var tempDir: URL!
    private var originalLogURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-uninstall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        originalLogURL = OperationLog.logFileURL
        OperationLog.logFileURL = tempDir.appendingPathComponent("operations.log")
    }

    override func tearDownWithError() throws {
        OperationLog.logFileURL = originalLogURL
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 工具

    private func makeAppBundle(named name: String, identifier: String, version: String? = "1.0", in dir: URL) throws -> URL {
        let appURL = dir.appendingPathComponent(name + ".app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name
        ]
        if let version {
            info["CFBundleShortVersionString"] = version
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x41, count: 1024).write(to: contents.appendingPathComponent("x.bin"))
        return appURL
    }

    private func makeApp(identifier: String? = "com.example.fake", name: String = "Fake App") -> InstalledApp {
        InstalledApp(
            name: name,
            displayName: name,
            bundleIdentifier: identifier,
            version: "1.0",
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            size: 1024,
            fileCount: 2
        )
    }

    private func write(_ data: Data, to relativePath: String) throws {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    // MARK: - 应用枚举

    func testScanInstalledAppsFindsBundles() throws {
        let appsDir = tempDir.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        _ = try makeAppBundle(named: "Fake App", identifier: "com.example.fake", in: appsDir)
        _ = try makeAppBundle(named: "Zebra", identifier: "com.example.zebra", in: appsDir)
        try Data(repeating: 0, count: 10).write(to: appsDir.appendingPathComponent("readme.txt"))

        let apps = AppCatalog.scanInstalledApps(in: [appsDir])
        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(apps.map(\.name), ["Fake App", "Zebra"])
        XCTAssertEqual(apps[0].bundleIdentifier, "com.example.fake")
        XCTAssertEqual(apps[0].version, "1.0")
        XCTAssertEqual(apps[0].displayName, "Fake App")
        XCTAssertGreaterThan(apps[0].size, 0)
        XCTAssertGreaterThan(apps[0].fileCount, 1)
    }

    func testScanInstalledAppsFindsNestedBundles() throws {
        let appsDir = tempDir.appendingPathComponent("Applications")
        let utilitiesDir = appsDir.appendingPathComponent("Utilities")
        try FileManager.default.createDirectory(at: utilitiesDir, withIntermediateDirectories: true)
        _ = try makeAppBundle(named: "NestedTool", identifier: "com.example.tool", in: utilitiesDir)

        let apps = AppCatalog.scanInstalledApps(in: [appsDir])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].name, "NestedTool")
        XCTAssertEqual(apps[0].bundleIdentifier, "com.example.tool")
    }

    func testScanInstalledAppsDeduplicatesByIdentifier() throws {
        let dir1 = tempDir.appendingPathComponent("a")
        let dir2 = tempDir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        _ = try makeAppBundle(named: "Same", identifier: "com.example.same", in: dir1)
        _ = try makeAppBundle(named: "Same", identifier: "com.example.same", in: dir2)

        let apps = AppCatalog.scanInstalledApps(in: [dir1, dir2])
        XCTAssertEqual(apps.count, 1)
    }

    // MARK: - 关联文件定位与安全分级

    func testFindAssociatedFiles() throws {
        let home: String = tempDir.path
        try write(Data(repeating: 0, count: 100), to: "Library/Preferences/com.example.fake.plist")
        try write(Data(repeating: 0, count: 2048), to: "Library/Caches/com.example.fake/data.bin")
        try write(Data(repeating: 0, count: 300), to: "Library/Application Support/Fake App/config.json")
        try write(Data(repeating: 0, count: 50), to: "Library/Logs/Fake App/run.log")
        try write(Data(repeating: 0, count: 10), to: "Library/Containers/com.example.fake/Container.plist")
        try write(Data(repeating: 0, count: 10), to: "Library/Group Containers/group.com.example.fake/shared.sqlite")
        try write(Data(repeating: 0, count: 10), to: "Library/LaunchAgents/com.example.fake.helper.plist")
        try write(Data(repeating: 0, count: 10), to: "Library/Saved Application State/com.example.fake.savedState/windows.plist")
        try write(Data(repeating: 0, count: 10), to: "Library/HTTPStorages/com.example.fake/cache.db")
        try write(Data(repeating: 0, count: 10), to: "Library/Application Scripts/com.example.fake/script.scpt")
        try write(Data(repeating: 0, count: 10), to: "Library/LaunchDaemons/com.example.fake.daemon.plist")
        try write(Data(repeating: 0, count: 10), to: ".config/fake-app/config.yaml")

        // 干扰项：不应匹配
        try write(Data(repeating: 0, count: 10), to: "Library/Caches/com.other.app/data.bin")
        try write(Data(repeating: 0, count: 10), to: "Library/LaunchAgents/com.other.agent.plist")
        try write(Data(repeating: 0, count: 10), to: "Library/Preferences/com.example.fake2.plist")

        let files = AppCatalog.findAssociatedFiles(for: makeApp(), home: home)
        XCTAssertGreaterThanOrEqual(files.count, 11)

        XCTAssertTrue(files.contains(where: { $0.kind == .preferences && $0.name == "com.example.fake.plist" }))
        XCTAssertTrue(files.contains(where: { $0.kind == .caches && $0.size >= 2048 && $0.safetyLevel == .safe }))
        XCTAssertTrue(files.contains(where: { $0.kind == .applicationSupport && $0.isDirectory && $0.safetyLevel == .appData }))
        XCTAssertTrue(files.contains(where: { $0.kind == .logs && $0.safetyLevel == .safe }))
        XCTAssertTrue(files.contains(where: { $0.kind == .containers && $0.safetyLevel == .appData }))
        XCTAssertTrue(files.contains(where: { $0.kind == .groupContainers && $0.safetyLevel == .caution }))
        XCTAssertTrue(files.contains(where: { $0.kind == .applicationScripts }))
        XCTAssertTrue(files.contains(where: { $0.kind == .launchAgents }))
        XCTAssertTrue(files.contains(where: { $0.kind == .launchDaemons && $0.safetyLevel == .caution }))
        XCTAssertTrue(files.contains(where: { $0.kind == .userConfig && $0.safetyLevel == .caution }))
        XCTAssertTrue(files.contains(where: { $0.kind == .savedState && $0.safetyLevel == .safe }))
        XCTAssertTrue(files.contains(where: { $0.kind == .httpStorages && $0.safetyLevel == .safe }))

        // 干扰项不被匹配
        XCTAssertFalse(files.contains(where: { $0.name.contains("com.other") }))
        XCTAssertFalse(files.contains(where: { $0.name.contains("com.example.fake2") }))
    }

    func testClueArkDesktopExcludesGenericDesktopAndDeduplicatesCaseInsensitively() throws {
        let home: String = tempDir.path
        let cluearkApp = InstalledApp(
            name: "ClueArk", displayName: "ClueArk",
            bundleIdentifier: "com.clueark.desktop", version: "0.1.24",
            url: URL(fileURLWithPath: "/Applications/ClueArk.app"), size: 100, fileCount: 5
        )

        // 1. 候选词中必须包含 ClueArk / clueark / com.clueark.desktop，但绝不能包含 "desktop"
        let candidates = AppCatalog.candidateNames(for: cluearkApp)
        XCTAssertTrue(candidates.contains("com.clueark.desktop"))
        XCTAssertTrue(candidates.contains("ClueArk"))
        XCTAssertFalse(candidates.contains(where: { $0.lowercased() == "desktop" }))

        // 2. 模拟文件系统：
        // 目标应用缓存和应用支持
        try write(Data(repeating: 0, count: 100), to: "Library/Caches/com.clueark.desktop/cache.db")
        try write(Data(repeating: 0, count: 100), to: "Library/Application Support/com.clueark.desktop/data.db")
        // 系统或其他软件可能存在的 "Desktop" 文件夹（绝不能误作为 ClueArk 的关联文件！）
        try write(Data(repeating: 0, count: 100), to: "Library/Application Support/Desktop/something.db")
        // 开机启动项（模拟 ClueArk.plist）
        try write(Data(repeating: 0, count: 50), to: "Library/LaunchAgents/clueark.plist")

        let files = AppCatalog.findAssociatedFiles(for: cluearkApp, home: home)
        // 必须识别到 com.clueark.desktop
        XCTAssertTrue(files.contains(where: { $0.name == "com.clueark.desktop" }))
        // 绝不能匹配到无关的 "Desktop" 文件夹！
        XCTAssertFalse(files.contains(where: { $0.name == "Desktop" }))
        // LaunchAgents 只能出现 1 个 clueark.plist / ClueArk.plist，不能出现重复的 2 个
        let launchAgentFiles = files.filter { $0.kind == .launchAgents }
        XCTAssertEqual(launchAgentFiles.count, 1)
    }

    func testVendorSubdirectoryMatchesExactProductAndExcludesUnrelatedAndBlacklist() throws {
        let home: String = tempDir.path
        let chromeApp = InstalledApp(
            name: "Google Chrome", displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome", version: "120.0",
            url: URL(fileURLWithPath: "/Applications/Google Chrome.app"), size: 100, fileCount: 10
        )

        // 目标应用文件
        try write(Data(repeating: 0, count: 100), to: "Library/Application Support/Google/Chrome/Default/Cookies")
        // 同厂商其他产品（绝对不能误删！）
        try write(Data(repeating: 0, count: 200), to: "Library/Application Support/Google/Drive/drive.db")
        try write(Data(repeating: 0, count: 300), to: "Library/Application Support/Google/Google Earth/earth.db")
        // 公共黑名单组件（绝对不能误删！）
        try write(Data(repeating: 0, count: 50), to: "Library/Application Support/Google/Google Software Update/ksadmin")

        let files = AppCatalog.findAssociatedFiles(for: chromeApp, home: home)
        // 应该只匹配到 Google/Chrome
        XCTAssertTrue(files.contains(where: { $0.kind == .applicationSupport && $0.name == "Chrome" }))
        // 不应误匹配 Drive、Google Earth、Google Software Update
        XCTAssertFalse(files.contains(where: { $0.name == "Drive" }))
        XCTAssertFalse(files.contains(where: { $0.name == "Google Earth" }))
        XCTAssertFalse(files.contains(where: { $0.name == "Google Software Update" }))
    }

    func testCandidateNamesExcludesBroadVendorNames() {
        let chromeApp = InstalledApp(
            name: "Google Chrome", displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome", version: nil,
            url: URL(fileURLWithPath: "/Applications/Google Chrome.app"), size: 1, fileCount: 1
        )
        let candidates = AppCatalog.candidateNames(for: chromeApp)
        XCTAssertTrue(candidates.contains("com.google.Chrome"))
        XCTAssertTrue(candidates.contains("Google Chrome"))
        XCTAssertTrue(candidates.contains("GoogleChrome"))
        XCTAssertTrue(candidates.contains("google-chrome"))
        XCTAssertTrue(candidates.contains("Chrome"))

        // 宽泛厂商词必须被过滤，防止全盘遍历该厂商所有软件
        XCTAssertFalse(candidates.contains("google"))
        XCTAssertFalse(candidates.contains("com"))
        XCTAssertFalse(candidates.contains("app"))
    }

    func testSafetyLevelDefaults() {
        XCTAssertTrue(AssociatedFileSafetyLevel.safe.defaultSelected)
        XCTAssertTrue(AssociatedFileSafetyLevel.appData.defaultSelected)
        XCTAssertFalse(AssociatedFileSafetyLevel.caution.defaultSelected)
    }

    // MARK: - 卸载防护规则与执行

    func testProtectedPathsIncludeSystemCoreAndRoots() {
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/System")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/System/Applications/Safari.app")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/System/Library/CoreServices")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/usr/bin/python3")))

        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/Applications")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/Library")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/Library/Application Support")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: NSHomeDirectory())))

        XCTAssertFalse(TrashService.isProtected(URL(fileURLWithPath: "/Applications/Google Chrome.app")))
        XCTAssertFalse(TrashService.isProtected(URL(fileURLWithPath: "/Applications/Utilities/ThirdPartyTool.app")))
        XCTAssertFalse(TrashService.isProtected(URL(fileURLWithPath: NSHomeDirectory() + "/Applications/Custom.app")))
        XCTAssertFalse(TrashService.isProtected(URL(fileURLWithPath: "/Library/Application Support/Google/Chrome")))
        XCTAssertFalse(TrashService.isProtected(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/com.google.Chrome")))
    }

    func testUninstallSkipsProtectedSystemApp() throws {
        let protectedApp = InstalledApp(
            name: "System App", displayName: "System App", bundleIdentifier: "com.apple.system", version: nil,
            url: URL(fileURLWithPath: "/System/Applications/System App.app"), size: 1, fileCount: 1
        )
        XCTAssertThrowsError(try Uninstaller.uninstall(app: protectedApp, files: []))
    }

    func testUninstallAppWithoutAssociatedFiles() throws {
        let appsDir = tempDir.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        let appURL = try makeAppBundle(named: "CleanApp", identifier: "com.example.clean", in: appsDir)

        let app = InstalledApp(
            name: "CleanApp", displayName: "CleanApp", bundleIdentifier: "com.example.clean",
            version: "1.0", url: appURL, size: 1024, fileCount: 2
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))

        let outcome = try Uninstaller.uninstall(app: app, files: [])
        XCTAssertTrue(outcome.appMoved)
        XCTAssertEqual(outcome.filesMoved, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
    }

    func testUninstallMovesAppAndFilesToTrash() throws {
        let appsDir = tempDir.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        let appURL = try makeAppBundle(named: "Fake App", identifier: "com.example.fake", in: appsDir)
        try write(Data(repeating: 0, count: 100), to: "Library/Preferences/com.example.fake.plist")
        let prefsURL = tempDir.appendingPathComponent("Library/Preferences/com.example.fake.plist")

        let app = InstalledApp(
            name: "Fake App", displayName: "Fake App", bundleIdentifier: "com.example.fake",
            version: "1.0", url: appURL, size: 1024, fileCount: 2
        )
        let file = AssociatedFile(
            url: prefsURL, name: "com.example.fake.plist", size: 100,
            isDirectory: false, kind: .preferences
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefsURL.path))

        let outcome = try Uninstaller.uninstall(app: app, files: [file])
        XCTAssertTrue(outcome.appMoved)
        XCTAssertEqual(outcome.filesMoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prefsURL.path))
    }
}
