import XCTest
@testable import MoleUI

final class ByteFormatterTests: XCTestCase {
    func testZeroIsRepresentable() {
        let output = ByteFormatter.fileString(from: 0)
        XCTAssertFalse(output.isEmpty)
        // ByteCountFormatter 对 0 的表示可能是 "0 KB" 或 "Zero KB"，随 locale 变化
        XCTAssertTrue(output.contains("0") || output.contains("Zero"))
    }

    func testFileStyleUnitProgression() {
        XCTAssertTrue(ByteFormatter.fileString(from: 1024).contains("KB"))
        XCTAssertTrue(ByteFormatter.fileString(from: 1024 * 1024).contains("MB"))
        XCTAssertTrue(ByteFormatter.fileString(from: 1024 * 1024 * 1024).contains("GB"))
    }

    func testDifferentSizesProduceDifferentStrings() {
        XCTAssertNotEqual(
            ByteFormatter.fileString(from: 1024),
            ByteFormatter.fileString(from: 2048)
        )
    }

    func testMemoryStyleUsesBinaryUnits() {
        XCTAssertTrue(ByteFormatter.memoryString(from: 8 * 1024 * 1024 * 1024).contains("GB"))
    }
}
