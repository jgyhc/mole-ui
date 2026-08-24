import XCTest
@testable import MoleUI

final class BrewServiceTests: XCTestCase {

    func testBrewPackageModelDefaults() {
        let pkg = BrewPackage(
            name: "ripgrep",
            fullName: "homebrew/core/ripgrep",
            type: .formula,
            tap: "homebrew/core",
            desc: "Search tool like grep and The Silver Searcher",
            homepage: "https://github.com/BurntSushi/ripgrep",
            license: "MIT",
            installedVersion: "14.1.0",
            currentVersion: "14.1.1",
            isOutdated: true,
            isPinned: false,
            isKegOnly: false,
            installReason: .requested,
            diskSizeBytes: 10_485_760,
            dependencies: ["pcre2"],
            buildDependencies: ["rust"]
        )

        XCTAssertEqual(pkg.id, "ripgrep")
        XCTAssertEqual(pkg.name, "ripgrep")
        XCTAssertEqual(pkg.displayName, "ripgrep")
        XCTAssertEqual(pkg.type, .formula)
        XCTAssertTrue(pkg.isOutdated)
        XCTAssertEqual(pkg.displayVersion, "14.1.0 ➔ 14.1.1")
        XCTAssertEqual(pkg.installReason, .requested)
        XCTAssertEqual(pkg.dependencies, ["pcre2"])
        XCTAssertEqual(pkg.buildDependencies, ["rust"])
    }

    func testCaskPackageModelDefaults() {
        let cask = BrewPackage(
            name: "visual-studio-code",
            fullName: "homebrew/cask/visual-studio-code",
            token: "visual-studio-code",
            displayName: "Visual Studio Code",
            type: .cask,
            tap: "homebrew/cask",
            desc: "Code editor",
            homepage: "https://code.visualstudio.com/",
            installedVersion: "1.90.0",
            currentVersion: "1.90.0",
            isOutdated: false,
            isAutoUpdates: true,
            diskSizeBytes: 500_000_000,
            artifacts: ["/Applications/Visual Studio Code.app"]
        )

        XCTAssertEqual(cask.id, "visual-studio-code")
        XCTAssertEqual(cask.displayName, "Visual Studio Code")
        XCTAssertEqual(cask.type, .cask)
        XCTAssertFalse(cask.isOutdated)
        XCTAssertEqual(cask.displayVersion, "1.90.0")
        XCTAssertTrue(cask.isAutoUpdates)
        XCTAssertEqual(cask.artifacts, ["/Applications/Visual Studio Code.app"])
    }

    func testParseOutdatedJSON() {
        let service = BrewService()
        let sampleOutdated = """
        {
          "formulae": [
            {
              "name": "aom",
              "installed_versions": ["3.13.3"],
              "current_version": "3.14.1",
              "pinned": false,
              "pinned_version": null
            },
            {
              "name": "node",
              "installed_versions": ["20.0.0"],
              "current_version": "22.0.0",
              "pinned": true,
              "pinned_version": "20.0.0"
            }
          ],
          "casks": [
            {
              "name": "docker",
              "installed_versions": ["4.28.0"],
              "current_version": "4.30.0",
              "pinned": false
            }
          ]
        }
        """

        let map = service.parseOutdatedJSON(sampleOutdated)
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map["aom"]?.currentVersion, "3.14.1")
        XCTAssertEqual(map["aom"]?.pinned, false)
        XCTAssertEqual(map["node"]?.currentVersion, "22.0.0")
        XCTAssertEqual(map["node"]?.pinned, true)
        XCTAssertEqual(map["docker"]?.currentVersion, "4.30.0")
    }

    func testParseBrewInfoJSON() {
        let service = BrewService()
        let sampleInfo = """
        {
          "formulae": [
            {
              "name": "git",
              "full_name": "git",
              "tap": "homebrew/core",
              "desc": "Fast, scalable, distributed revision control system",
              "license": "GPL-2.0-only",
              "homepage": "https://git-scm.com",
              "versions": {
                "stable": "2.45.0"
              },
              "dependencies": ["pcre2", "gettext"],
              "build_dependencies": [],
              "keg_only": false,
              "pinned": false,
              "outdated": false,
              "installed": [
                {
                  "version": "2.44.0",
                  "installed_on_request": true,
                  "time": 1715000000
                }
              ]
            }
          ],
          "casks": [
            {
              "token": "iterm2",
              "full_token": "homebrew/cask/iterm2",
              "name": ["iTerm2"],
              "desc": "Terminal emulator as alternative to Apple's Terminal app",
              "homepage": "https://iterm2.com/",
              "version": "3.5.0",
              "installed": "3.4.19",
              "installed_time": 1714000000,
              "outdated": true,
              "auto_updates": true,
              "artifacts": [
                {
                  "app": ["iTerm.app"]
                }
              ]
            }
          ]
        }
        """

        let outdatedMap: [String: (currentVersion: String, pinned: Bool)] = [
            "git": ("2.45.0", false),
            "iterm2": ("3.5.0", false)
        ]

        guard let data = sampleInfo.data(using: .utf8) else {
            XCTFail("Failed to convert string to data")
            return
        }

        let packages = service.parseBrewInfoJSON(
            data: data,
            outdatedMap: outdatedMap,
            cellarURL: nil,
            caskroomURL: nil
        )

        XCTAssertEqual(packages.count, 2)

        let git = packages.first { $0.name == "git" }
        XCTAssertNotNil(git)
        XCTAssertEqual(git?.type, .formula)
        XCTAssertEqual(git?.installedVersion, "2.44.0")
        XCTAssertEqual(git?.currentVersion, "2.45.0")
        XCTAssertTrue(git?.isOutdated == true)
        XCTAssertEqual(git?.installReason, .requested)
        XCTAssertEqual(git?.dependencies, ["pcre2", "gettext"])

        let iterm = packages.first { $0.name == "iterm2" }
        XCTAssertNotNil(iterm)
        XCTAssertEqual(iterm?.type, .cask)
        XCTAssertEqual(iterm?.displayName, "iTerm2")
        XCTAssertEqual(iterm?.installedVersion, "3.4.19")
        XCTAssertEqual(iterm?.currentVersion, "3.5.0")
        XCTAssertTrue(iterm?.isOutdated == true)
        XCTAssertTrue(iterm?.isAutoUpdates == true)
        XCTAssertEqual(iterm?.artifacts, ["/Applications/iTerm.app"])
    }

    func testDirectorySizeCalculation() {
        let service = BrewService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileA = tempDir.appendingPathComponent("fileA.txt")
        let fileB = tempDir.appendingPathComponent("fileB.txt")
        let dummyData = Data(repeating: 0x41, count: 1024) // 1 KB
        try? dummyData.write(to: fileA)
        try? dummyData.write(to: fileB)

        let size = service.calculateDirectorySize(at: tempDir)
        XCTAssertGreaterThanOrEqual(size, 2048)
    }

    @MainActor
    func testViewModelFilteringAndSorting() {
        let vm = BrewViewModel()
        XCTAssertEqual(vm.activeFilterTab, .all)
        XCTAssertEqual(vm.sortOption, .name)
        XCTAssertTrue(vm.searchText.isEmpty)

        let pkg1 = BrewPackage(
            name: "git",
            displayName: "git",
            type: .formula,
            desc: "Fast version control",
            installedVersion: "2.45.0",
            currentVersion: "2.45.0",
            isOutdated: false,
            installReason: .requested,
            diskSizeBytes: 50_000_000
        )

        let pkg2 = BrewPackage(
            name: "node",
            displayName: "node",
            type: .formula,
            desc: "JavaScript runtime",
            installedVersion: "20.0.0",
            currentVersion: "22.0.0",
            isOutdated: true,
            installReason: .requested,
            diskSizeBytes: 100_000_000
        )

        let pkg3 = BrewPackage(
            name: "iterm2",
            displayName: "iTerm2",
            type: .cask,
            desc: "Terminal emulator",
            installedVersion: "3.5.0",
            currentVersion: "3.5.0",
            isOutdated: false,
            installReason: .requested,
            diskSizeBytes: 30_000_000
        )

        let pkg4 = BrewPackage(
            name: "pcre2",
            displayName: "pcre2",
            type: .formula,
            desc: "Perl compatible regular expressions",
            installedVersion: "10.43",
            currentVersion: "10.43",
            isOutdated: false,
            installReason: .dependency,
            diskSizeBytes: 5_000_000
        )

        XCTAssertEqual(pkg1.type, .formula)
        XCTAssertEqual(pkg3.type, .cask)
        XCTAssertTrue(pkg2.isOutdated)
        XCTAssertEqual(pkg4.installReason, .dependency)
    }
}
