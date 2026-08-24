import SwiftUI
import AppKit

/// Node 软件包管理视图：管理通过 npm / pnpm 全局安装的软件、概况、一键更新与卸载。
public struct NodePackageView: View {
    @ObservedObject private var viewModel = NodePackageViewModel.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topSummaryBar
            Divider()

            if !viewModel.isAnyNodeManagerInstalled {
                nodeNotInstalledView
            } else if viewModel.isLoading && !viewModel.hasScannedOnce {
                loadingView
            } else {
                mainContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Node 软件包管理")
        .toolbar {
            ToolbarItemGroup {
                if viewModel.isAnyNodeManagerInstalled {
                    Button {
                        viewModel.checkAllUpdates()
                    } label: {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("联网检查 npm/pnpm 全局软件包的最新版本")
                    .disabled(viewModel.isOperating || viewModel.isLoading || viewModel.isCheckingUpdates)

                    Menu {
                        Button("清理 npm 缓存 (npm cache clean)") {
                            viewModel.cleanCache(manager: .npm)
                        }
                        Button("清理 pnpm 存储 (pnpm store prune)") {
                            viewModel.cleanCache(manager: .pnpm)
                        }
                    } label: {
                        Label("清理缓存", systemImage: "sparkles")
                    }
                    .help("清理 npm / pnpm 的全局缓存与孤立包")
                    .disabled(viewModel.isOperating || viewModel.isLoading)

                    Button {
                        viewModel.scan()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .help("重新扫描本地 npm / pnpm 全局安装的软件包")
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
            if viewModel.pendingActionPackage != nil {
                Button("卸载", role: .destructive) {
                    viewModel.confirmUninstall()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let pkg = viewModel.pendingActionPackage {
                Text("确定要从「\(pkg.environmentName)」卸载全局软件包「\(pkg.displayName)」(\(pkg.manager.title)) 吗？\n卸载后其提供的相关命令行工具将无法使用。")
            }
        }
        .alert("确认一键更新", isPresented: $viewModel.isShowingUpgradeAllAlert) {
            Button("开始全部升级", role: .none) {
                viewModel.upgradeAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("检测到共有 \(viewModel.outdatedPackages.count) 个软件包有可用更新。将按顺序调用对应的包管理器升级至 @latest 最新版本。")
        }
        .sheet(isPresented: $viewModel.showConsoleSheet) {
            consoleOutputSheet
        }
    }

    // MARK: - 顶部统计栏

    private var topSummaryBar: some View {
        HStack(spacing: 16) {
            statItem(
                title: "已安装软件包",
                value: "\(viewModel.summary.totalPackagesCount) 个",
                subtext: "npm: \(viewModel.summary.npmPackagesCount) · pnpm: \(viewModel.summary.pnpmPackagesCount)",
                icon: "shippingbox.circle.fill",
                color: .red
            )

            Divider().frame(height: 24)

            statItem(
                title: "磁盘占用空间",
                value: ByteFormatter.fileString(from: viewModel.summary.totalSizeBytes),
                subtext: envVersionSummary,
                icon: "internaldrive.fill",
                color: .indigo
            )

            Divider().frame(height: 24)

            statItem(
                title: "可更新软件",
                value: "\(viewModel.summary.outdatedCount) 个",
                subtext: viewModel.summary.outdatedCount > 0 ? "建议升级" : (viewModel.isCheckingUpdates ? "正在检查..." : "已是最新"),
                icon: "arrow.up.circle.fill",
                color: viewModel.summary.outdatedCount > 0 ? .orange : .green
            )

            Spacer()

            if viewModel.summary.outdatedCount > 0 {
                Button {
                    viewModel.promptUpgradeAll()
                } label: {
                    Label("一键全部升级 (\(viewModel.summary.outdatedCount))", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.isOperating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var envVersionSummary: String {
        var parts: [String] = []
        if let node = viewModel.summary.activeNodeVersion {
            parts.append("Node \(node)")
        }
        if let npm = viewModel.summary.activeNpmVersion {
            parts.append("npm \(npm)")
        }
        if let pnpm = viewModel.summary.activePnpmVersion {
            parts.append("pnpm \(pnpm)")
        }
        return parts.isEmpty ? "\(viewModel.summary.environmentNames.count) 个环境" : parts.joined(separator: " · ")
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
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
                packageDetailView
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 筛选与搜索工具条

    private var filterAndSearchBar: some View {
        HStack(spacing: 10) {
            // Tab 筛选
            Picker("分类", selection: $viewModel.activeFilterTab) {
                ForEach(NodePackageFilterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            // 环境筛选 (如果有多个环境)
            if viewModel.summary.environmentNames.count > 1 {
                Picker("环境", selection: Binding(
                    get: { viewModel.selectedEnvironment ?? "全部环境" },
                    set: { val in viewModel.selectedEnvironment = (val == "全部环境" ? nil : val) }
                )) {
                    Text("全部环境").tag("全部环境")
                    ForEach(viewModel.summary.environmentNames, id: \.self) { envName in
                        Text(envName).tag(envName)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索包名、命令、描述...", text: $viewModel.searchText)
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
            .frame(maxWidth: 220)

            Spacer()

            // 排序
            Picker("排序", selection: $viewModel.sortOption) {
                ForEach(NodePackageSortOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
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
                    Text("未找到符合条件的 Node 软件包")
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

    private func packageRow(_ pkg: NodePackage) -> some View {
        HStack(spacing: 8) {
            // 包管理器标志 (npm / pnpm)
            managerBadge(pkg.manager)

            VStack(alignment: .leading, spacing: 3) {
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
                }

                HStack(spacing: 6) {
                    Text("v\(pkg.displayVersion)")
                        .font(.caption2)
                        .foregroundStyle(pkg.isOutdated ? .orange : .secondary)
                        .lineLimit(1)

                    if let bin = pkg.binaries.first {
                        HStack(spacing: 2) {
                            Image(systemName: "terminal")
                                .font(.system(size: 8))
                            Text(bin.command)
                                .font(.system(size: 9, design: .monospaced))
                            if pkg.binaries.count > 1 {
                                Text("+\(pkg.binaries.count - 1)")
                                    .font(.system(size: 8))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }

                    Text("· \(pkg.environmentName)")
                        .font(.system(size: 9))
                        .foregroundStyle(pkg.isActiveEnvironment ? Color.accentColor : Color.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.fileString(from: pkg.diskSizeBytes))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if let date = pkg.installedTime {
                    Text(relativeDate(date))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func managerBadge(_ manager: NodePackageManagerType) -> some View {
        Text(manager.title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(manager == .npm ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundStyle(manager == .npm ? Color.red : Color.orange)
            .cornerRadius(4)
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

                                if !pkg.keywords.isEmpty {
                                    FlowLayout(spacing: 4) {
                                        ForEach(pkg.keywords, id: \.self) { kw in
                                            Text(kw)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12))
                                                .cornerRadius(4)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }

                        // 2. CLI 命令行入口 (Binaries)
                        if pkg.hasBinaries {
                            binariesSection(pkg)
                        }

                        // 3. 基本信息卡片
                        basicInfoSection(pkg)

                        // 4. 依赖项信息
                        if !pkg.dependencies.isEmpty {
                            dependenciesSection(pkg)
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
                "选择一个 Node 软件包",
                systemImage: "shippingbox.fill",
                description: Text("从左侧列表中选择一个通过 npm 或 pnpm 全局安装的软件查看详细概况、CLI 命令与管理。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 详情头部

    private func detailHeader(_ pkg: NodePackage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: pkg.manager.symbol)
                .font(.system(size: 32))
                .foregroundStyle(pkg.manager == .npm ? Color.red : Color.orange)
                .frame(width: 44, height: 44)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(pkg.name)
                        .font(.title2.weight(.bold))
                        .textSelection(.enabled)

                    managerBadge(pkg.manager)

                    Text(pkg.environmentName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)

                    if pkg.isOutdated {
                        Text("新版本可用")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text("当前版本: v\(pkg.installedVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if let lic = pkg.license {
                        Text("· 许可证: \(lic)")
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

                if let repo = pkg.repository, let url = URL(string: repo) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("仓库", systemImage: "curlybraces")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    let cmd = pkg.manager == .npm ? "npm i -g \(pkg.name)" : "pnpm add -g \(pkg.name)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                } label: {
                    Label("复制安装命令", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - CLI 命令行入口卡片

    private func binariesSection(_ pkg: NodePackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.blue)
                Text("CLI 命令行工具入口 (\(pkg.binaries.count))")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(pkg.binaries) { bin in
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right.square.fill")
                            .foregroundStyle(.green)

                        Text(bin.command)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)

                        Text("➔ \(bin.targetPath)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(bin.command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("复制命令: \(bin.command)")
                    }
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 基本信息卡片

    private func basicInfoSection(_ pkg: NodePackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("基本概况")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("所属环境:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(pkg.environmentName)
                            .font(.subheadline.weight(.semibold))
                        if pkg.isActiveEnvironment {
                            Text("(当前活跃)")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }

                GridRow {
                    Text("已安装版本:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("v\(pkg.installedVersion)")
                        .font(.subheadline.weight(.semibold))
                        .textSelection(.enabled)
                }

                if let latest = pkg.latestVersion {
                    GridRow {
                        Text("远端最新版本:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text("v\(latest)")
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

                if let author = pkg.author {
                    GridRow {
                        Text("作者 / 维护者:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(author)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }

                if let engineNode = pkg.engines["node"] {
                    GridRow {
                        Text("Node 版本要求:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(engineNode)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let date = pkg.installedTime {
                    GridRow {
                        Text("安装 / 变更时间:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formattedDate(date))
                            .font(.subheadline)
                    }
                }

                if let path = pkg.path {
                    GridRow {
                        Text("本地存储路径:")
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

    // MARK: - 依赖项信息

    private func dependenciesSection(_ pkg: NodePackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("生产依赖项 (Dependencies)")
                    .font(.headline)
                Spacer()
                Text("共 \(pkg.dependencies.count) 个")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            FlowLayout(spacing: 6) {
                ForEach(pkg.dependencies.sorted(by: { $0.key < $1.key }), id: \.key) { depName, depVer in
                    HStack(spacing: 4) {
                        Text(depName)
                            .font(.caption.weight(.medium))
                        Text(depVer)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 底部操作栏

    private func detailBottomActionBar(_ pkg: NodePackage) -> some View {
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
                Label(pkg.isOutdated ? "一键升级" : "强制重新安装最新版", systemImage: "arrow.up.circle")
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
                    Text(viewModel.currentOperationTitle.isEmpty ? "Node 软件包执行日志" : viewModel.currentOperationTitle)
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
            Text("正在扫描 npm 与 pnpm 全局软件包...")
                .font(.headline)
            Text("分析已安装的模块元数据、CLI 命令入口与磁盘占用空间")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nodeNotInstalledView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("未检测到 Node.js / npm / pnpm")
                .font(.title2.weight(.bold))
            Text("当前系统未检测到全局可用的 npm 或 pnpm 包管理器。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
