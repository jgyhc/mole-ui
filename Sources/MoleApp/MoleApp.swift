import SwiftUI
import AppKit

// SPM 构建时 MoleUI 是独立库模块，需要 import；
// Xcode 工程里所有代码在同一个 app target 中编译，无需（也无法）import 自身。
#if canImport(MoleUI)
import MoleUI
#endif

@main
struct MoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Mole") {
            ContentView()
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 740)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 通过 `swift run` 直接运行时没有 app bundle，确保以常规应用方式激活
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        #if DEBUG
        setupSnapshotIfRequested()
        setupLayoutProbeIfRequested()
        #endif
    }

    #if DEBUG
    /// 开发辅助：`--layout-probe` 逐个切换标签页并打印窗口/分栏 frame，用于排查布局问题。
    private func setupLayoutProbeIfRequested() {
        guard CommandLine.arguments.contains("--layout-probe") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Self.probeLayout()
        }
    }

    private static var probeFile: String {
        "/tmp/mole-probe.txt"
    }

    private static func probeLog(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: probeFile) {
                fh.seekToEndOfFile()
                fh.write(data)
            } else {
                try? data.write(to: URL(fileURLWithPath: probeFile))
            }
        }
        print(line)
    }

    private static func probeLayout() {
        try? "".write(to: URL(fileURLWithPath: probeFile), atomically: true, encoding: .utf8)
        // 轮询所有标签页，打印窗口 frame 与 DocumentView 高度
        let sequence: [(String, String)] = [
            ("dashboard", "dashboard"),
            ("clean", "clean"),
            ("uninstall", "uninstall"),
            ("purge", "purge"),
            ("installers", "installers"),
            ("analyze", "analyze"),
            ("optimize", "optimize"),
            ("back-to-dashboard", "dashboard")
        ]
        for (label, section) in sequence {
            NotificationCenter.default.post(name: Notification.Name("MoleLayoutProbe"), object: section)
            Thread.sleep(forTimeInterval: 2.5)
            guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.mainWindow else { continue }
            let docHeight = findDocumentViewHeight(window.contentView ?? NSView())
            probeLog("PROBE \(label): window=\(NSStringFromRect(window.frame)) docHeight=\(docHeight)")
            probeLog("PROBE \(label): listRows=\(countListRows(window.contentView ?? NSView()))")
        }
        // 先停在 optimize 页 14 秒，再切到 clean 页 14 秒，供外部 screencapture 分别抓屏
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: Notification.Name("MoleLayoutProbe"), object: "optimize")
        Thread.sleep(forTimeInterval: 6)
        if let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.mainWindow {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            Thread.sleep(forTimeInterval: 0.6)
            window.displayIfNeeded()
            Self.savePDF(of: window, to: "/tmp/pdf-optimize.png")
        }
        Thread.sleep(forTimeInterval: 6)
        NotificationCenter.default.post(name: Notification.Name("MoleLayoutProbe"), object: "clean")
        Thread.sleep(forTimeInterval: 6)
        if let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.mainWindow {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            Thread.sleep(forTimeInterval: 0.6)
            window.displayIfNeeded()
            Self.savePDF(of: window, to: "/tmp/pdf-clean.png")
        }
        Thread.sleep(forTimeInterval: 4)
        NSApp.terminate(nil)
    }

    private static func countListRows(_ view: NSView) -> Int {
        var count = 0
        if String(describing: type(of: view)).contains("ListTableRowView") {
            count += 1
        }
        for sub in view.subviews {
            count += countListRows(sub)
        }
        return count
    }

    private static func findDocumentViewHeight(_ view: NSView) -> CGFloat {
        if String(describing: type(of: view)).contains("DocumentView") {
            return view.frame.height
        }
        for sub in view.subviews {
            let h = findDocumentViewHeight(sub)
            if h > 0 { return h }
        }
        return 0
    }

    private static func savePDF(of window: NSWindow, to path: String) {
        guard let view = window.contentView else { return }
        let pdfData = view.dataWithPDF(inside: view.bounds)
        if !pdfData.isEmpty, let pdfImage = NSImage(data: pdfData) {
            let rep = NSBitmapImageRep(data: pdfImage.tiffRepresentation!)
            if let data = rep?.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                probeLog("PROBE saved \(path) \(data.count) bytes")
            }
        }
    }

    private static func dumpTree(_ view: NSView, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        let cls = String(describing: type(of: view))
        probeLog("PROBE   \(String(repeating: "  ", count: depth))\(cls) \(NSStringFromRect(view.frame))")
        for sub in view.subviews {
            dumpTree(sub, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private static func dumpSplitViews(_ view: NSView) {
        for sub in view.subviews {
            if let split = sub as? NSSplitView {
                print("PROBE   split=\(NSStringFromRect(split.frame)) panes=\(split.subviews.map { NSStringFromRect($0.frame) })")
            }
            dumpSplitViews(sub)
        }
    }
    #endif

    #if DEBUG
    /// 开发辅助：`--snapshot-to <path>` 启动后把主窗口截图保存并退出（无需屏幕录制权限）。
    private func setupSnapshotIfRequested() {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot-to"),
              index + 1 < CommandLine.arguments.count else { return }
        let path = CommandLine.arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            Self.captureMainWindow(to: path)
        }
    }

    private static func captureMainWindow(to path: String, terminateAfter: Bool = true) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.mainWindow,
              let view = window.contentView else {
            print("⚠️ 无法找到主窗口")
            NSApp.terminate(nil)
            return
        }
        print("📐 窗口: \(window.frame), isVisible=\(window.isVisible), occluded=\(window.occlusionState), contentView=\(view.frame)")

        // 强制前置并刷新，避免被遮挡时 CA 延迟绘制
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.displayIfNeeded()
        view.displayIfNeeded()
        Thread.sleep(forTimeInterval: 0.8)

        // 方式 1：PDF 表示（打印渲染路径，SwiftUI 视图通常可捕获）
        let pdfData = view.dataWithPDF(inside: view.bounds)
        print("📄 PDF 字节数: \(pdfData.count)")
        var saved = false
        if !pdfData.isEmpty, let pdfImage = NSImage(data: pdfData) {
            let rep = NSBitmapImageRep(data: pdfImage.tiffRepresentation!)
            if let data = rep?.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                print("📸 已保存 PDF 渲染截图: \(path)")
                saved = true
            }
        }

        // 方式 2：layer 渲染
        if !saved, let layer = view.layer {
            let scale: CGFloat = 2
            let width = Int(view.bounds.width * scale)
            let height = Int(view.bounds.height * scale)
            if let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                context.scaleBy(x: scale, y: scale)
                layer.render(in: context)
                if let image = context.makeImage(),
                   let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                    print("📸 已保存 layer 渲染截图: \(path)")
                    saved = true
                }
            }
        }

        print(saved ? "✅ 截图成功" : "⚠️ 所有渲染方式均失败")
        if terminateAfter {
            NSApp.terminate(nil)
        }
    }
    #endif
}
