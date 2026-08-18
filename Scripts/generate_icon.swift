#!/usr/bin/env swift
// 生成 Mole 应用图标：从源图（默认 Support/AppIconSource.png）生成带圆角遮罩的 1024px 主图标
// 及 16/32/64/128/256/512 各尺寸，写入 AppIcon.appiconset（Xcode / make-app.sh 均从此处取图）。
// 用法：swift Scripts/generate_icon.swift [源图路径]
import AppKit
import Foundation

let sourcePath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Support/AppIconSource.png"

guard let source = NSImage(contentsOfFile: sourcePath) else {
    fatalError("无法加载源图：\(sourcePath)")
}

let cornerRatio: CGFloat = 228.0 / 1024.0   // 与旧版仓鼠图标一致的圆角比例

func makeIcon(size: Int, from image: NSImage) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = cornerRatio * CGFloat(size)

    // 圆角遮罩（区域外透明，与 macOS 图标惯例一致）
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

    // 按最短边居中裁剪后等比缩放填充
    let imgSize = image.size
    let minSide = min(imgSize.width, imgSize.height)
    let cropRect = NSRect(
        x: (imgSize.width - minSide) / 2,
        y: (imgSize.height - minSide) / 2,
        width: minSide,
        height: minSide
    )
    image.draw(in: rect, from: cropRect, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let outputDir = URL(fileURLWithPath: "Sources/MoleApp/Assets.xcassets/AppIcon.appiconset")

// 主图标 1024px + 各尺寸（与 Contents.json 对应）
let sizes: [(name: String, size: Int)] = [
    ("AppIcon-16.png", 16),
    ("AppIcon-32.png", 32),
    ("AppIcon-64.png", 64),
    ("AppIcon-128.png", 128),
    ("AppIcon-256.png", 256),
    ("AppIcon-512.png", 512),
    ("AppIcon.png", 1024),
]

for item in sizes {
    guard let png = makeIcon(size: item.size, from: source) else {
        fatalError("生成 \(item.name) 失败")
    }
    let url = outputDir.appendingPathComponent(item.name)
    try! png.write(to: url)
    print("✅ \(item.name) (\(item.size)x\(item.size), \(png.count) bytes)")
}

print("✅ 图标已更新（源图：\(sourcePath)）")
