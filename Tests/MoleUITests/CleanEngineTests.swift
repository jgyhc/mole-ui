import XCTest
@testable import MoleUI

final class CleanEngineTests: XCTestCase {
    func testCategoryDefaults() {
        for category in CleanCategory.allCases {
            switch category {
            case .userCaches, .browserCaches, .logs, .devCaches:
                XCTAssertTrue(category.defaultSelected, "\(category) 应默认勾选")
                XCTAssertFalse(category.isDangerous)
            case .trash, .temp, .leftovers:
                XCTAssertFalse(category.defaultSelected, "\(category) 不应默认勾选")
            default:
                break
            }
        }
        XCTAssertTrue(CleanCategory.trash.isDangerous)
        XCTAssertTrue(CleanCategory.temp.isDangerous)
        XCTAssertTrue(CleanCategory.trash.isPermanentDelete)
        XCTAssertFalse(CleanCategory.userCaches.isPermanentDelete)
    }

    func testCategoryRootPathsUnderHome() {
        for category in CleanCategory.allCases where category != .leftovers {
            for path in category.rootPaths {
                XCTAssertTrue(
                    path.path.hasPrefix(NSHomeDirectory()) || path.path == "/private/tmp",
                    "\(category) 的路径超出允许范围: \(path.path)"
                )
            }
        }
        XCTAssertTrue(CleanCategory.leftovers.rootPaths.isEmpty)
    }

    func testNormalizeName() {
        XCTAssertEqual(CleanEngine.normalizeName("Google Chrome"), "googlechrome")
        XCTAssertEqual(CleanEngine.normalizeName("com.google.Chrome"), "comgooglechrome")
        XCTAssertEqual(CleanEngine.normalizeName("  Xcode  (beta)  "), "xcodebeta")
        XCTAssertEqual(CleanEngine.normalizeName(""), "")
    }

    func testCleanItemPermanentFlag() {
        let trashItem = CleanItem(
            url: URL(fileURLWithPath: "/tmp/x"), name: "x", size: 1,
            isDirectory: false, fileCount: 1, category: .trash
        )
        XCTAssertTrue(trashItem.isPermanent)

        let cacheItem = CleanItem(
            url: URL(fileURLWithPath: "/tmp/y"), name: "y", size: 1,
            isDirectory: false, fileCount: 1, category: .userCaches
        )
        XCTAssertFalse(cacheItem.isPermanent)
    }

    func testCleanSkipsProtectedPaths() throws {
        // 受保护路径不会被清理，且不抛错
        let protectedItem = CleanItem(
            url: URL(fileURLWithPath: "/"), name: "root", size: 1,
            isDirectory: true, fileCount: 0, category: .userCaches
        )
        let outcome = try CleanEngine.clean(items: [protectedItem])
        XCTAssertEqual(outcome.moved, 0)
        XCTAssertEqual(outcome.permanent, 0)
    }

    func testScanCategoryDoesNotCrashOnMissingPaths() {
        // 扫描不存在的分类路径不应崩溃，返回空结果
        let result = CleanEngine.scanCategory(.temp)
        XCTAssertEqual(result.category, .temp)
        XCTAssertGreaterThanOrEqual(result.totalSize, 0)
    }
}
