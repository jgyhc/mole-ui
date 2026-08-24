import SwiftUI
import AppKit

/// Homebrew 软件包管理视图：全景概览、分类检索、详情概况、一键更新与卸载。
public struct BrewView: View {
    @ObservedObject private var viewModel = BrewViewModel.shared
    @State private var showingDetailsModal = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topSummaryBar
            Divider()

            if !viewModel.isBrewInstalled {
                brewNotInstalledView
            } else if viewModel.isLoading && !viewModel.hasScannedOnce {
                loadingView
            } else {
                mainContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Homebrew 管理")
        .toolbar {
            ToolbarItemGroup {
                if viewModel.isBrewInstalled {
                    Button {
                        viewModel.updateBrewIndex()
                    } label: {
                        Label("刷新索引", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("执行 brew update 检查最新软件索引与更新")
                    .disabled(viewModel.isOperating || viewModel.isLoading)

                    Button {
                        viewModel.cleanupBrew()
                    } label: {
                        Label("清理缓存", systemImage: "sparkles")
                    }
                    .help("执行 brew cleanup 清理历史下载缓存与旧版本")
                    .disabled(viewModel.isOperating || viewModel.isLoading)

                    Button {
                        viewModel.scan()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .help("重新扫描本地 Homebrew 软件包状态")
                    .disabled(viewModel.isOperating || viewModel.isLoading)
                }
            }
        }
        .onAppear {
            if !viewModel.hasScannedOnce {
                viewModel.scan()
            }
        }
        .alert("确认卸载", isPresented: $viewModel.isShowingUninstallAlert) {
            if let pkg = viewModel.pendingActionPackage {
                if pkg.type == .cask {
                    Button("卸载并清理残留 (Zap)", role: .destructive) {
                        viewModel.zapCaskDataOnUninstall = true
                        viewModel.confirmUninstall()
                    }
                }
                Button("仅卸载", role: .destructive) {
                    viewModel.zapCaskDataOnUninstall = false
                    viewModel.confirmUninstall()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let pkg = viewModel.pendingActionPackage {
                let note = pkg.usedBy.isEmpty ? "" : "\n⚠️ 警告：当前有 \(pkg.usedBy.count) 个已安装软件包依赖它 (\(pkg.usedBy.prefix(3).joined(separator: ", "))\(pkg.usedBy.count > 3 ? " 等" : ""))，卸载可能导致依赖它们的应用无法运行！"
                Text("确定要卸载「\(pkg.displayName)」(\(pkg.type.shortTitle)) 吗？\(note)")
            }
        }
        .alert("确认一键更新", isPresented: $viewModel.isShowingUpgradeAllAlert) {
            Button("开始全部更新", role: .none) {
                viewModel.upgradeAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("检测到共有 \(viewModel.outdatedPackages.count) 个软件包有可用更新。将按顺序自动下载并升级最新版本。")
        }
        .sheet(isPresented: $viewModel.showConsoleSheet) {
            consoleOutputSheet
        }
    }

    // MARK: - 顶部统计栏

    private var topSummaryBar: some View {
        HStack(spacing: 16) {
            statItem(
                title: "已安装软件",
                value: "\(viewModel.summary.totalPackagesCount) 个",
                subtext: "CLI: \(viewModel.summary.formulaeCount) · App: \(viewModel.summary.casksCount)",
                icon: "mug.fill",
                color: .blue
            )

            Divider().frame(height: 24)

            statItem(
                title: "磁盘占用空间",
                value: ByteFormatter.fileString(from: viewModel.summary.totalSizeBytes),
                subtext: viewModel.summary.homebrewPrefix ?? "/opt/homebrew",
                icon: "internaldrive.fill",
                color: .indigo
            )

            Divider().frame(height: 24)

            statItem(
                title: "可更新软件",
                value: "\(viewModel.summary.outdatedCount) 个",
                subtext: viewModel.summary.outdatedCount > 0 ? "建议升级" : "已是最新",
                icon: "arrow.up.circle.fill",
                color: viewModel.summary.outdatedCount > 0 ? .orange : .green
            )

            Spacer()

            if viewModel.summary.outdatedCount > 0 {
                Button {
                    viewModel.promptUpgradeAll()
                } label: {
                    Label("一键全部更新 (\(viewModel.summary.outdatedCount))", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.isOperating)
            }

            if let prefix = viewModel.summary.homebrewPrefix {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: prefix)
                } label: {
                    Label("打开 Homebrew 目录", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func statItem(title: String, value: String, subtext: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(value)
                        .font(.callout.weight(.bold))
                    Text("(\(subtext))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 主内容区 (HSplitView: 左侧列表 + 右侧详情)

    private var mainContentView: some View {
        VStack(spacing: 0) {
            filterAndSearchBar
            Divider()

            HSplitView {
                packageListView
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                packageDetailView
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 筛选与搜索工具条

    private var filterAndSearchBar: some View {
        HStack(spacing: 12) {
            // Tab 筛选
            Picker("分类", selection: $viewModel.activeFilterTab) {
                ForEach(BrewFilterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索软件名、描述、依赖或 Tap...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 240)

            Spacer()

            // 排序
            Picker("排序", selection: $viewModel.sortOption) {
                ForEach(BrewSortOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 左侧软件列表

    private var packageListView: some View {
        VStack(spacing: 0) {
            if viewModel.filteredPackages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("未找到符合条件的软件包")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedPackageID },
                    set: { id in
                        if let id, let pkg = viewModel.packages.first(where: { $0.id == id }) {
                            viewModel.selectPackage(pkg)
                        }
                    }
                )) {
                    ForEach(viewModel.filteredPackages) { pkg in
                        packageRow(pkg)
                            .tag(pkg.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()
            HStack {
                Text("共 \(viewModel.filteredPackages.count) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func packageRow(_ pkg: BrewPackage) -> some View {
        HStack(spacing: 8) {
            // 图标
            Image(systemName: pkg.type.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pkg.type == .cask ? Color.indigo : Color.blue)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pkg.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    if pkg.isOutdated {
                        Text("可更新")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .cornerRadius(3)
                    }

                    if pkg.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                    }
                }

                HStack(spacing: 4) {
                    Text(pkg.displayVersion)
                        .font(.caption2)
                        .foregroundStyle(pkg.isOutdated ? .orange : .secondary)
                        .lineLimit(1)

                    if let tap = pkg.tap, tap != "homebrew/core" && tap != "homebrew/cask" {
                        Text("· \(tap)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.fileString(from: pkg.diskSizeBytes))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if pkg.installReason == .requested {
                    Text("独立安装")
                        .font(.system(size: 9))
                        .foregroundStyle(.teal)
                } else if pkg.installReason == .dependency {
                    Text("依赖")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 右侧软件详情面板

    @ViewBuilder
    private var packageDetailView: some View {
        if let pkg = viewModel.selectedPackage {
            VStack(spacing: 0) {
                // 详情头部
                detailHeader(pkg)
                Divider()

                // 详情主体内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. 软件概述与描述
                        if let desc = pkg.desc, !desc.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("软件概述")
                                    .font(.headline)
                                Text(desc)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }

                        // 2. 使用提示 (Caveats)
                        if let caveats = pkg.caveats, !caveats.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.bubble.fill")
                                        .foregroundStyle(.orange)
                                    Text("使用说明与配置提示 (Caveats)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                                Text(caveats)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.primary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                            .cornerRadius(6)
                        }

                        // 3. 基本信息卡片
                        basicInfoSection(pkg)

                        // 4. 依赖关系
                        dependenciesSection(pkg)

                        // 5. 产物与关联文件
                        if !pkg.artifacts.isEmpty {
                            artifactsSection(pkg)
                        }
                    }
                    .padding(16)
                }

                // 底部操作栏
                Divider()
                detailBottomActionBar(pkg)
            }
        } else {
            ContentUnavailableView(
                "选择一个软件包",
                systemImage: "mug.fill",
                description: Text("从左侧列表中选择一个通过 Homebrew 安装的软件查看概况与管理。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 详情头部

    private func detailHeader(_ pkg: BrewPackage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: pkg.type.symbol)
                .font(.system(size: 32))
                .foregroundStyle(pkg.type == .cask ? Color.indigo : Color.blue)
                .frame(width: 44, height: 44)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(pkg.displayName)
                        .font(.title2.weight(.bold))
                        .textSelection(.enabled)

                    typeBadge(pkg.type)

                    if pkg.isOutdated {
                        Text("新版本可用")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }

                    if pkg.isPinned {
                        Text("已锁定版本")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.18))
                            .foregroundStyle(.purple)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text(pkg.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if let tap = pkg.tap {
                        Text("· Tap: \(tap)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // 头部快速按钮
            HStack(spacing: 8) {
                if let hp = pkg.homepage, let url = URL(string: hp) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("官网", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if pkg.type == .formula {
                    Button {
                        viewModel.togglePin(package: pkg)
                    } label: {
                        Label(pkg.isPinned ? "取消锁定" : "锁定版本", systemImage: pkg.isPinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(pkg.isPinned ? "解除对此包的版本锁定" : "锁定版本，防止在 brew upgrade 时被自动升级")
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func typeBadge(_ type: BrewPackageType) -> some View {
        Text(type.title)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((type == .cask ? Color.indigo : Color.blue).opacity(0.15))
            .foregroundStyle(type == .cask ? Color.indigo : Color.blue)
            .cornerRadius(4)
    }

    // MARK: - 基本信息卡片

    private func basicInfoSection(_ pkg: BrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("基本概况")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("已安装版本:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(pkg.installedVersion ?? "未知")
                        .font(.subheadline.weight(.semibold))
                        .textSelection(.enabled)
                }

                if let current = pkg.currentVersion {
                    GridRow {
                        Text("最新可用版本:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(current)
                                .font(.subheadline.weight(pkg.isOutdated ? .bold : .regular))
                                .foregroundStyle(pkg.isOutdated ? .orange : .primary)
                                .textSelection(.enabled)
                            if pkg.isOutdated {
                                Text("(可升级)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                GridRow {
                    Text("磁盘占用空间:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.fileString(from: pkg.diskSizeBytes))
                        .font(.subheadline)
                        .monospacedDigit()
                }

                if let lic = pkg.license {
                    GridRow {
                        Text("开源许可证:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(lic)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }

                if let date = pkg.installedTime {
                    GridRow {
                        Text("安装时间:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formattedDate(date))
                            .font(.subheadline)
                    }
                }

                GridRow {
                    Text("安装类型:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(pkg.installReason == .requested ? "用户主动安装 (独立工具)" : (pkg.installReason == .dependency ? "作为依赖被动安装" : "未指定"))
                            .font(.subheadline)
                        if pkg.isKegOnly {
                            Text("[Keg-only: 不软链全局]")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                    }
                }

                if let path = pkg.path {
                    GridRow {
                        Text("文件系统路径:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(path.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path.path, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("复制路径")

                            Button {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.borderless)
                            .help("在 Finder 中打开")
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 依赖关系卡片

    private func dependenciesSection(_ pkg: BrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("依赖关系")
                .font(.headline)

            // 直接依赖
            VStack(alignment: .leading, spacing: 6) {
                Text("此软件依赖的包 (Dependencies):")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if pkg.dependencies.isEmpty && pkg.buildDependencies.isEmpty {
                    Text("无外部依赖（独立运行）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(pkg.dependencies, id: \.self) { dep in
                            dependencyChip(name: dep, isBuildOnly: false)
                        }
                        ForEach(pkg.buildDependencies, id: \.self) { dep in
                            dependencyChip(name: dep, isBuildOnly: true)
                        }
                    }
                }
            }

            Divider()

            // 反向依赖 (Used By)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("被以下已安装软件所依赖 (Used By):")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("共 \(pkg.usedBy.count) 个")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if pkg.usedBy.isEmpty {
                    Text("当前没有其他软件依赖此包（可安全卸载）")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(pkg.usedBy, id: \.self) { dep in
                            usedByChip(name: dep)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func dependencyChip(name: String, isBuildOnly: Bool) -> some View {
        Button {
            viewModel.selectPackage(byName: name)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 10))
                Text(name)
                    .font(.caption.weight(.medium))
                if isBuildOnly {
                    Text("(build)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("点击跳转至 \(name) 详情")
    }

    private func usedByChip(name: String) -> some View {
        Button {
            viewModel.selectPackage(byName: name)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(name)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("点击跳转至依赖此包的 \(name) 详情")
    }

    // MARK: - 产物与文件

    private func artifactsSection(_ pkg: BrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("安装产物与文件")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(pkg.artifacts, id: \.self) { art in
                    HStack(spacing: 6) {
                        Image(systemName: art.hasSuffix(".app") ? "macwindow" : "doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(art)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if FileManager.default.fileExists(atPath: art) {
                            Button {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: art)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.borderless)
                            .help("在 Finder 中打开")
                        }
                    }
                    .padding(6)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 底部操作栏

    private func detailBottomActionBar(_ pkg: BrewPackage) -> some View {
        HStack(spacing: 12) {
            if pkg.isOutdated {
                Label("发现新版本可用：\(pkg.displayVersion)", systemImage: "arrow.up.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Label("已是最新版本", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            Spacer()

            // 一键更新按钮
            Button {
                viewModel.promptUpgrade(package: pkg)
            } label: {
                Label(pkg.isOutdated ? "一键更新" : "强制重新升级", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(pkg.isOutdated ? .orange : .accentColor)
            .disabled(viewModel.isOperating)

            // 一键卸载按钮
            Button(role: .destructive) {
                viewModel.promptUninstall(package: pkg)
            } label: {
                Label("一键卸载", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(viewModel.isOperating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - 终端实时控制台弹窗

    private var consoleOutputSheet: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    if viewModel.isOperating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(.blue)
                    }
                    Text(viewModel.currentOperationTitle.isEmpty ? "Homebrew 执行日志" : viewModel.currentOperationTitle)
                        .font(.headline)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.consoleOutput, forType: .string)
                } label: {
                    Label("复制日志", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("关闭") {
                    viewModel.showConsoleSheet = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isOperating)
            }
            .padding(14)
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.consoleOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .textColor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                        .id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: viewModel.consoleOutput) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(width: 620, height: 400)
    }

    // MARK: - 加载与未安装状态

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("正在扫描 Homebrew 软件包与更新状态...")
                .font(.headline)
            Text("分析已安装的 Formula 与 Cask、计算磁盘空间与依赖关系")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var brewNotInstalledView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("未检测到 Homebrew")
                .font(.title2.weight(.bold))
            Text("当前系统未安装 Homebrew，或者未在标准路径 (/opt/homebrew 或 /usr/local) 找到 brew 可执行程序。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 6) {
                Text("可在终端中执行以下命令安装 Homebrew：")
                    .font(.caption.weight(.medium))
                HStack {
                    Text("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            .padding(.top, 8)

            Button("重新检测") {
                viewModel.scan()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 12)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 辅助格式化

    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: date)
    }
}

// MARK: - 流式标签布局 (FlowLayout)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
