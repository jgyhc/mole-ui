import XCTest
@testable import MoleUI

final class NodePackageServiceTests: XCTestCase {

    func testNodePackageModelDefaults() {
        let pkg = NodePackage(
            name: "wrangler",
            manager: .npm,
            displayName: "wrangler",
            scope: nil,
            installedVersion: "3.50.0",
            latestVersion: "3.55.0",
            isOutdated: true,
            desc: "Command-line interface for all things Cloudflare Workers",
            homepage: "https://developers.cloudflare.com/workers/wrangler/",
            repository: "https://github.com/cloudflare/workers-sdk",
            license: "MIT",
            author: "Cloudflare",
            binaries: [NodePackageBinary(command: "wrangler", targetPath: "bin/wrangler.js")],
            diskSizeBytes: 20_000_000,
            engines: ["node": ">=16.17.0"],
            dependencies: ["esbuild": "^0.20.0"],
            keywords: ["cloudflare", "workers", "serverless"]
        )

        XCTAssertEqual(pkg.id, "npm:默认环境:wrangler")
        XCTAssertEqual(pkg.name, "wrangler")
        XCTAssertEqual(pkg.manager, .npm)
        XCTAssertEqual(pkg.displayName, "wrangler")
        XCTAssertTrue(pkg.isOutdated)
        XCTAssertEqual(pkg.displayVersion, "3.50.0 ➔ 3.55.0")
        XCTAssertTrue(pkg.hasBinaries)
        XCTAssertEqual(pkg.binaries.count, 1)
        XCTAssertEqual(pkg.binaries.first?.command, "wrangler")
        XCTAssertEqual(pkg.engines["node"], ">=16.17.0")
        XCTAssertEqual(pkg.dependencies["esbuild"], "^0.20.0")
        XCTAssertEqual(pkg.keywords.count, 3)
    }

    func testScopedNodePackageModel() {
        let pkg = NodePackage(
            name: "@anthropic-ai/claude-code",
            manager: .npm,
            displayName: "@anthropic-ai/claude-code",
            scope: "@anthropic-ai",
            installedVersion: "2.1.139",
            latestVersion: "2.1.241",
            isOutdated: true,
            desc: "Use Claude right from your terminal",
            binaries: [NodePackageBinary(command: "claude", targetPath: "bin/claude.exe")]
        )

        XCTAssertEqual(pkg.id, "npm:默认环境:@anthropic-ai/claude-code")
        XCTAssertEqual(pkg.scope, "@anthropic-ai")
        XCTAssertEqual(pkg.displayVersion, "2.1.139 ➔ 2.1.241")
        XCTAssertTrue(pkg.hasBinaries)
    }

    func testNormalizeRepositoryURL() {
        let service = NodePackageService()

        XCTAssertEqual(
            service.normalizeRepositoryURL("git+https://github.com/facebook/react.git"),
            "https://github.com/facebook/react"
        )
        XCTAssertEqual(
            service.normalizeRepositoryURL("git://github.com/isaacs/rimraf.git"),
            "https://github.com/isaacs/rimraf"
        )
        XCTAssertEqual(
            service.normalizeRepositoryURL("github:expressjs/express"),
            "https://github.com/expressjs/express"
        )
        XCTAssertEqual(
            service.normalizeRepositoryURL("https://github.com/lodash/lodash.git"),
            "https://github.com/lodash/lodash"
        )
    }

    func testParseOutdatedJSON() {
        let service = NodePackageService()
        let sampleOutdated = """
        {
          "@anthropic-ai/claude-code": {
            "current": "2.1.139",
            "wanted": "2.1.241",
            "latest": "2.1.241",
            "location": "node_modules/@anthropic-ai/claude-code"
          },
          "wrangler": {
            "current": "3.50.0",
            "wanted": "3.55.0",
            "latest": "3.55.0",
            "location": "node_modules/wrangler"
          }
        }
        """

        let map = service.parseOutdatedJSON(sampleOutdated)
        XCTAssertNotNil(map)
        XCTAssertEqual(map?["@anthropic-ai/claude-code"], "2.1.241")
        XCTAssertEqual(map?["wrangler"], "3.55.0")
    }

    func testParsePackageDirectory() throws {
        let service = NodePackageService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pkgDir = tempDir.appendingPathComponent("my-cli-tool")
        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let packageJsonContent = """
        {
          "name": "my-cli-tool",
          "version": "1.2.3",
          "description": "A sample CLI utility for testing",
          "license": "MIT",
          "homepage": "https://example.com/tool",
          "author": {
            "name": "Alice Developer",
            "email": "alice@example.com"
          },
          "repository": {
            "type": "git",
            "url": "https://github.com/example/my-cli-tool.git"
          },
          "bin": {
            "mytool": "bin/index.js",
            "mytool-sub": "bin/sub.js"
          },
          "engines": {
            "node": ">=18"
          },
          "dependencies": {
            "commander": "^11.0.0"
          },
          "keywords": ["cli", "utility"]
        }
        """

        let pkgJsonURL = pkgDir.appendingPathComponent("package.json")
        try packageJsonContent.write(to: pkgJsonURL, atomically: true, encoding: .utf8)

        let parsed = service.parsePackageDirectory(dirURL: pkgDir, fullName: "my-cli-tool", scope: nil, manager: .npm)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.name, "my-cli-tool")
        XCTAssertEqual(parsed?.installedVersion, "1.2.3")
        XCTAssertEqual(parsed?.desc, "A sample CLI utility for testing")
        XCTAssertEqual(parsed?.license, "MIT")
        XCTAssertEqual(parsed?.author, "Alice Developer <alice@example.com>")
        XCTAssertEqual(parsed?.repository, "https://github.com/example/my-cli-tool")
        XCTAssertEqual(parsed?.homepage, "https://example.com/tool")
        XCTAssertEqual(parsed?.binaries.count, 2)
        XCTAssertEqual(parsed?.binaries[0].command, "mytool")
        XCTAssertEqual(parsed?.binaries[1].command, "mytool-sub")
        XCTAssertEqual(parsed?.engines["node"], ">=18")
        XCTAssertEqual(parsed?.dependencies["commander"], "^11.0.0")
        XCTAssertEqual(parsed?.keywords, ["cli", "utility"])
    }

    func testScanDirectoryPackagesWithScopedPackages() throws {
        let service = NodePackageService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. 普通包
        let normDir = tempDir.appendingPathComponent("rimraf")
        try FileManager.default.createDirectory(at: normDir, withIntermediateDirectories: true)
        let normJson = """
        { "name": "rimraf", "version": "5.0.5", "bin": { "rimraf": "bin.js" } }
        """
        try normJson.write(to: normDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        // 2. 作用域包
        let scopeDir = tempDir.appendingPathComponent("@scope").appendingPathComponent("scoped-tool")
        try FileManager.default.createDirectory(at: scopeDir, withIntermediateDirectories: true)
        let scopeJson = """
        { "name": "@scope/scoped-tool", "version": "0.1.0", "bin": "cli.js" }
        """
        try scopeJson.write(to: scopeDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let packages = service.scanDirectoryPackages(rootPath: tempDir.path, manager: .pnpm)
        XCTAssertEqual(packages.count, 2)

        let rimraf = packages.first { $0.name == "rimraf" }
        XCTAssertNotNil(rimraf)
        XCTAssertEqual(rimraf?.manager, .pnpm)
        XCTAssertEqual(rimraf?.installedVersion, "5.0.5")

        let scoped = packages.first { $0.name == "@scope/scoped-tool" }
        XCTAssertNotNil(scoped)
        XCTAssertEqual(scoped?.scope, "@scope")
        XCTAssertEqual(scoped?.installedVersion, "0.1.0")
    }

    @MainActor
    func testViewModelFilteringAndSorting() {
        let vm = NodePackageViewModel()
        XCTAssertEqual(vm.activeFilterTab, .all)
        XCTAssertEqual(vm.sortOption, .name)
        XCTAssertTrue(vm.searchText.isEmpty)

        let pkg1 = NodePackage(
            name: "wrangler",
            manager: .npm,
            installedVersion: "3.50.0",
            latestVersion: "3.55.0",
            isOutdated: true,
            desc: "Cloudflare Workers CLI",
            binaries: [NodePackageBinary(command: "wrangler", targetPath: "bin/wrangler.js")],
            diskSizeBytes: 20_000_000
        )

        let pkg2 = NodePackage(
            name: "pnpm-dlx",
            manager: .pnpm,
            installedVersion: "1.0.0",
            latestVersion: "1.0.0",
            isOutdated: false,
            desc: "Execute package binary",
            binaries: [],
            diskSizeBytes: 5_000_000
        )

        XCTAssertEqual(pkg1.manager, .npm)
        XCTAssertEqual(pkg2.manager, .pnpm)
        XCTAssertTrue(pkg1.isOutdated)
        XCTAssertFalse(pkg2.isOutdated)
        XCTAssertTrue(pkg1.hasBinaries)
        XCTAssertFalse(pkg2.hasBinaries)
    }

    func testScanInstalledPackagesLive() async throws {
        let service = NodePackageService()
        let (packages, summary) = try await service.scanInstalledPackages()
        XCTAssertGreaterThanOrEqual(packages.count, 4)
        XCTAssertGreaterThanOrEqual(summary.totalPackagesCount, 4)
    }
}
