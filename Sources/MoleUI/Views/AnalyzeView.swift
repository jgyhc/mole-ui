import SwiftUI
import UniformTypeIdentifiers
import AppKit
import QuickLook

/// 磁盘分析：Canvas 方形树图 + 大文件列表 + 目录导航 + 访达联动与快捷操作。
struct AnalyzeView: View {
    @ObservedObject private var viewModel = DiskAnalysisViewModel.shared
    @State private var isImporterPresented = false

    var body: some View {
        HSplitView {
            treemapArea
            sidePanel
        }
        .navigationTitle("磁盘分析")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("主目录 (~)") { viewModel.scanRoot(URL(fileURLWithPath: NSHomeDirectory())) }
                    Button("根目录 (/)") { viewModel.scanRoot(URL(fileURLWithPath: "/")) }
                    Button("下载目录") {
                        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                            viewModel.scanRoot(downloads)
                        }
                    }
                    Button("应用程序") {
                        viewModel.scanRoot(URL(fileURLWithPath: "/Applications"))
                    }
                    Divider()
                    Button("选择自定义文件夹…") { isImporterPresented = true }
                } label: {
                    Label("位置", systemImage: "folder")
                }
                .help("选择扫描位置")

                Button {
                    viewModel.goUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(viewModel.pathIndices.isEmpty || viewModel.isLoading)
                .help("上一级目录")

                if viewModel.isLoading {
                    Button {
                        viewModel.cancelScan()
                    } label: {
                        Image(systemName: "stop.circle")
                            .foregroundStyle(.red)
                    }
                    .help("停止扫描")
                } else {
                    Button {
                        viewModel.start()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("重新扫描")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.scanRoot(url)
            }
        }
        .alert("移入废纸篓", isPresented: $viewModel.isShowingTrashConfirmation) {
            Button("移入废纸篓", role: .destructive) { viewModel.trashSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将选中的 \(viewModel.selectedFiles.count) 个项目（共 \(viewModel.selectedSizeString)）移入废纸篓？可在废纸篓中恢复。")
        }
        .quickLookPreview($viewModel.previewURL)
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: toast)
            }
        }
    }

    // MARK: - 树图区域

    @ViewBuilder
    private var treemapArea: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在扫描磁盘占用…")
                        .font(.headline)
                    Text(viewModel.progress.currentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 400)
                    Text("已分析 \(viewModel.progress.scannedFiles) 个项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    Button("停止扫描") {
                        viewModel.cancelScan()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.root == nil {
                ContentUnavailableView("扫描未完成", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if viewModel.root == nil {
                ContentUnavailableView {
                    Label("尚未扫描", systemImage: "internaldrive")
                } description: {
                    Text("点击「开始扫描」分析磁盘占用，或从工具栏选择指定扫描目录")
                } actions: {
                    Button("开始扫描") { viewModel.start() }
                        .buttonStyle(.borderedProminent)
                }
            } else if viewModel.currentEntry != nil {
                VStack(spacing: 0) {
                    breadcrumbBar
                    Divider()
                    TreemapView(
                        entries: Array(viewModel.currentChildren.filter { $0.size > 0 }.prefix(200)),
                        onSelect: { entry in
                            if entry.isDirectory,
                               let index = viewModel.currentChildren.firstIndex(where: { $0.id == entry.id }) {
                                viewModel.enter(childIndex: index)
                            }
                        },
                        onReveal: { entry in
                            viewModel.revealInFinder(entry.url)
                        },
                        onOpen: { entry in
                            viewModel.openWithDefaultApp(entry.url)
                        },
                        onCopyPath: { entry in
                            viewModel.copyPath(entry.url)
                        },
                        onTrash: { entry in
                            viewModel.trashSingle(entry: entry)
                        }
                    )
                    .padding(8)
                }
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 420, idealWidth: 700, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.jumpTo(index: -1)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                    Text(rootDisplayName)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.pathIndices.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(viewModel.pathIndices.isEmpty)

            ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.offset) { i, crumb in
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button {
                    viewModel.jumpTo(index: crumb.index)
                } label: {
                    Text(crumb.name)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(i == viewModel.breadcrumbs.count - 1 ? Color.primary : Color.accentColor)
                .disabled(i == viewModel.breadcrumbs.count - 1)
            }
            Spacer()
            if let entry = viewModel.currentEntry {
                HStack(spacing: 8) {
                    Text(ByteFormatter.fileString(from: entry.size))
                        .fontWeight(.semibold)
                    Text("·")
                    Text("\(entry.fileCount) 个项目")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private var rootDisplayName: String {
        let path = viewModel.scanRootURL.path
        if path == "/" { return "根目录 (/)" }
        let name = viewModel.scanRootURL.lastPathComponent
        return name.isEmpty ? "根目录" : name
    }

    // MARK: - 侧栏大文件列表

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("大文件（≥ 5MB）", systemImage: "doc.badge.arrow.up")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(viewModel.largeFiles.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if viewModel.isLoading {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在搜索大文件…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if viewModel.largeFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("未发现 5MB 以上的大文件")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedFiles) {
                    ForEach(viewModel.largeFiles) { file in
                        LargeFileRow(entry: file, viewModel: viewModel)
                            .tag(file.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    viewModel.isShowingTrashConfirmation = true
                } label: {
                    Label("移入废纸篓", systemImage: "trash")
                }
                .disabled(viewModel.selectedFiles.isEmpty || viewModel.isLoading)

                Spacer()

                if let message = viewModel.lastTrashMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !viewModel.selectedFiles.isEmpty {
                    Text("已选 \(viewModel.selectedFiles.count) 项 (\(viewModel.selectedSizeString))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
    }
}

// MARK: - 大文件行视图

struct LargeFileRow: View {
    let entry: DiskEntry
    @ObservedObject var viewModel: DiskAnalysisViewModel
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: entry.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(entry.formattedDate)
                    Text("·")
                    Text(entry.category.displayName)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.fileString(from: entry.size))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()

                // 快捷在访达中显示图标
                Button {
                    viewModel.revealInFinder(entry.url)
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundStyle(isHovering ? Color.accentColor : Color.secondary.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("在访达中显示 (⌘R)")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // 鼠标悬停显示完整路径与信息卡片
        .help("""
        名称: \(entry.name)
        路径: \(entry.url.path)
        大小: \(entry.formattedExactSize)
        修改: \(entry.formattedDate)
        类型: \(entry.category.displayName)
        """)
        // 右键上下文菜单
        .contextMenu {
            Button {
                viewModel.revealInFinder(entry.url)
            } label: {
                Label("在访达中显示", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("r", modifiers: .command)

            Button {
                viewModel.openWithDefaultApp(entry.url)
            } label: {
                Label("用默认程序打开", systemImage: "arrow.up.forward.app")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button {
                viewModel.quickLook(entry.url)
            } label: {
                Label("快速预览 (Quick Look)", systemImage: "eye")
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button {
                viewModel.copyPath(entry.url)
            } label: {
                Label("拷贝完整路径", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Divider()

            Button(role: .destructive) {
                viewModel.trashSingle(entry: entry)
            } label: {
                Label("移入废纸篓", systemImage: "trash")
            }
        }
    }
}

// MARK: - 树图

/// Canvas 绘制的方形树图，支持悬停高亮、右键上下文菜单、点击进入目录与在 Finder 中显示。
struct TreemapView: View {
    let entries: [DiskEntry]
    let onSelect: (DiskEntry) -> Void
    let onReveal: (DiskEntry) -> Void
    let onOpen: (DiskEntry) -> Void
    let onCopyPath: (DiskEntry) -> Void
    let onTrash: (DiskEntry) -> Void

    @State private var hoveredEntry: DiskEntry?
    @State private var contextMenuEntry: DiskEntry?

    private var sizes: [Double] { entries.map { Double($0.size) } }

    var body: some View {
        GeometryReader { geo in
            let layout = TreemapLayout.layout(
                sizes: sizes,
                in: TreemapLayout.Rect(x: 0, y: 0, w: geo.size.width, h: geo.size.height)
            )
            Canvas { context, _ in
                for (index, rect) in layout.enumerated() {
                    let entry = entries[index]
                    guard rect.w > 0, rect.h > 0 else { continue }
                    let inset = rect.w > 4 && rect.h > 4 ? 0.75 : 0
                    let drawRect = CGRect(
                        x: rect.x + inset, y: rect.y + inset,
                        width: rect.w - inset * 2, height: rect.h - inset * 2
                    )
                    let isHovered = hoveredEntry?.id == entry.id
                    let path = Path(drawRect)
                    context.fill(
                        path,
                        with: .color(entry.category.color.opacity(isHovered ? 1.0 : 0.82))
                    )
                    if rect.w > 42, rect.h > 16 {
                        context.draw(
                            Text(entry.name)
                                .font(.system(size: 11, weight: isHovered ? .semibold : .regular))
                                .foregroundStyle(.white),
                            at: CGPoint(x: rect.x + 4, y: rect.y + 3),
                            anchor: .topLeading
                        )
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let entry = hoveredEntry {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: entry.category.systemImage)
                            Text(entry.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(entry.category.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        HStack {
                            Text(ByteFormatter.fileString(from: entry.size))
                                .font(.caption.weight(.medium))
                            if entry.isDirectory {
                                Text("(\(entry.fileCount) 个项目)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("双击进入 / 右键更多")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: 320)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.1))
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    .padding(10)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoveredEntry = hitTest(point: point, layout: layout)
                case .ended:
                    hoveredEntry = nil
                }
            }
            .onTapGesture(count: 2) {
                if let entry = hoveredEntry {
                    if entry.isDirectory {
                        onSelect(entry)
                    } else {
                        onReveal(entry)
                    }
                }
            }
            .onTapGesture(count: 1) {
                if let entry = hoveredEntry, entry.isDirectory {
                    onSelect(entry)
                }
            }
            .contextMenu {
                if let entry = hoveredEntry ?? contextMenuEntry {
                    Button {
                        onReveal(entry)
                    } label: {
                        Label("在访达中显示", systemImage: "magnifyingglass")
                    }

                    Button {
                        onOpen(entry)
                    } label: {
                        Label("用默认程序打开", systemImage: "arrow.up.forward.app")
                    }

                    if entry.isDirectory {
                        Button {
                            onSelect(entry)
                        } label: {
                            Label("进入此文件夹", systemImage: "folder")
                        }
                    }

                    Divider()

                    Button {
                        onCopyPath(entry)
                    } label: {
                        Label("拷贝完整路径", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onTrash(entry)
                    } label: {
                        Label("移入废纸篓", systemImage: "trash")
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        )
    }

    private func hitTest(point: CGPoint, layout: [TreemapLayout.Rect]) -> DiskEntry? {
        for (index, rect) in layout.enumerated() {
            if point.x >= rect.x, point.x <= rect.x + rect.w,
               point.y >= rect.y, point.y <= rect.y + rect.h {
                return entries[index]
            }
        }
        return nil
    }
}

// MARK: - 分类配色

extension FileCategory {
    var color: Color {
        switch self {
        case .directory: Color(red: 0.30, green: 0.55, blue: 0.85)
        case .app: Color(red: 0.20, green: 0.70, blue: 0.60)
        case .image: Color(red: 0.60, green: 0.45, blue: 0.85)
        case .video: Color(red: 0.85, green: 0.40, blue: 0.55)
        case .audio: Color(red: 0.90, green: 0.60, blue: 0.25)
        case .document: Color(red: 0.85, green: 0.75, blue: 0.30)
        case .archive: Color(red: 0.55, green: 0.50, blue: 0.42)
        case .code: Color(red: 0.40, green: 0.70, blue: 0.40)
        case .system: Color(red: 0.75, green: 0.35, blue: 0.30)
        case .other: Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }
}
