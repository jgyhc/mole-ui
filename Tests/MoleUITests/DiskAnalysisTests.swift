import XCTest
@testable import MoleUI

final class DiskAnalysisTests: XCTestCase {
    // MARK: - 树图布局

    func testTreemapLayoutFillsContainerWithoutOverlap() {
        let sizes: [Double] = [30, 25, 20, 15, 10]
        let rect = TreemapLayout.Rect(x: 0, y: 0, w: 100, h: 60)
        let rects = TreemapLayout.layout(sizes: sizes, in: rect)

        XCTAssertEqual(rects.count, sizes.count)

        // 无重叠
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let a = rects[i], b = rects[j]
                let overlapW = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
                let overlapH = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
                XCTAssertLessThanOrEqual(max(0, overlapW) * max(0, overlapH), 0.001,
                                         "矩形 \(i) 与 \(j) 重叠")
            }
        }

        // 总面积 ≈ 容器面积
        let totalArea = rects.reduce(0) { $0 + $1.area }
        XCTAssertEqual(totalArea, 6000, accuracy: 1.0)

        // 面积与大小成正比
        let sum = sizes.reduce(0, +)
        for (i, r) in rects.enumerated() {
            XCTAssertEqual(r.area / 6000, sizes[i] / sum, accuracy: 0.02)
        }
    }

    func testTreemapSingleItemFillsContainer() {
        let rects = TreemapLayout.layout(sizes: [1], in: TreemapLayout.Rect(x: 0, y: 0, w: 10, h: 5))
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0].w, 10)
        XCTAssertEqual(rects[0].h, 5)
    }

    func testTreemapSortedDescendingIsStable() {
        // 降序输入：第一项面积最大
        let rects = TreemapLayout.layout(sizes: [50, 30, 20], in: TreemapLayout.Rect(x: 0, y: 0, w: 100, h: 100))
        XCTAssertGreaterThan(rects[0].area, rects[1].area)
    }

    // MARK: - 分类与属性测试

    func testFileCategoryClassification() {
        XCTAssertEqual(FileCategory.of(name: "photo.jpg", isDirectory: false), .image)
        XCTAssertEqual(FileCategory.of(name: "movie.mov", isDirectory: false), .video)
        XCTAssertEqual(FileCategory.of(name: "song.mp3", isDirectory: false), .audio)
        XCTAssertEqual(FileCategory.of(name: "report.pdf", isDirectory: false), .document)
        XCTAssertEqual(FileCategory.of(name: "archive.zip", isDirectory: false), .archive)
        XCTAssertEqual(FileCategory.of(name: "main.swift", isDirectory: false), .code)
        XCTAssertEqual(FileCategory.of(name: "Xcode.app", isDirectory: true), .app)
        XCTAssertEqual(FileCategory.of(name: "随便目录", isDirectory: true), .directory)
        XCTAssertEqual(FileCategory.of(name: "data.bin", isDirectory: false), .other)

        XCTAssertEqual(FileCategory.image.displayName, "图片")
        XCTAssertEqual(FileCategory.video.displayName, "视频")
        XCTAssertFalse(FileCategory.archive.systemImage.isEmpty)
    }

    func testDiskEntryFormatting() {
        let now = Date()
        let home = NSHomeDirectory()
        let fileURL = URL(fileURLWithPath: "\(home)/Downloads/bigfile.dmg")
        let entry = DiskEntry(
            name: "bigfile.dmg",
            url: fileURL,
            size: 104857600,
            isDirectory: false,
            fileCount: 1,
            modificationDate: now
        )

        XCTAssertEqual(entry.abbreviatedPath, "~/Downloads/bigfile.dmg")
        XCTAssertFalse(entry.formattedDate.isEmpty)
        XCTAssertTrue(entry.formattedExactSize.contains("100 MB") || entry.formattedExactSize.contains("105 MB") || entry.formattedExactSize.contains("字节"))
        XCTAssertEqual(entry.category, .archive)
    }

    // MARK: - 扫描器（临时目录）

    func testScannerWithTempDirectory() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let dataA = Data(repeating: 0xAB, count: 4096)
        try dataA.write(to: temp.appendingPathComponent("a.bin"))
        try dataA.write(to: temp.appendingPathComponent("b.bin"))
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 2048).write(to: temp.appendingPathComponent("sub/c.bin"))
        try Data(repeating: 0, count: 100).write(to: temp.appendingPathComponent("pic.jpg"))
        // 符号链接应被跳过
        try? FileManager.default.createSymbolicLink(
            at: temp.appendingPathComponent("loop"),
            withDestinationURL: temp
        )

        let result = DiskScanner.scan(root: temp)

        XCTAssertEqual(result.root.fileCount, 4)
        XCTAssertEqual(result.root.children?.count, 4) // a.bin b.bin sub pic.jpg
        // 目录大小 ≥ 逻辑大小之和（分配大小可能更大）
        XCTAssertGreaterThanOrEqual(result.root.size, 4096 * 2 + 2048 + 100)
        // 无 5MB 以上文件
        XCTAssertTrue(result.largeFiles.isEmpty)
        // 子目录聚合
        let sub = result.root.children?.first { $0.name == "sub" }
        XCTAssertNotNil(sub)
        XCTAssertEqual(sub?.fileCount, 1)
        XCTAssertGreaterThanOrEqual(sub?.size ?? 0, 2048)
    }

    func testScannerCancellationDoesNotCrash() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mole-scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try? Data(repeating: 0, count: 100).write(to: temp.appendingPathComponent("x.bin"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let result = await Task.detached {
            DiskScanner.scan(root: temp)
        }.value
        XCTAssertEqual(result.root.fileCount, 1)
    }

    // MARK: - 受保护路径

    func testProtectedPaths() {
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/System")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: "/Applications")))
        XCTAssertTrue(TrashService.isProtected(URL(fileURLWithPath: NSHomeDirectory())))
        XCTAssertFalse(TrashService.isProtected(URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/test.dmg")))
    }
}
