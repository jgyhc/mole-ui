import SwiftUI
import AppKit

/// Flutter / FVM 版本盘点与智能清理视图
struct FVMView: View {
    @ObservedObject private var viewModel = FVMViewModel.shared
    @State private var expandedVersionIds: Set<String> = []
    @State private var selectedVersionForMigration: FVMInstalledVersion? = nil

    var body: some View {
        VStack(spacing: 0) {
            topSummaryBar
            Divider()

            searchRootsBar
            Divider()

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isCleaning)

            if !viewModel.versions.isEmpty && !viewModel.isCleaning {
                Divider()
                bottomActionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Flutter SDK 清理")
        .toolbar {
            ToolbarItemGroup {
                Picker("视图模式", selection: $viewModel.activeTab) {
                    ForEach(FVMViewTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    pickSearchRootFolder()
                } label: {
                    Label("添加项目目录", systemImage: "folder.badge.plus")
                }
                .help("添加 Flutter 项目存放的根目录")

                Button {
                    viewModel.scan()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .help("重新扫描 FVM 版本及本地 Flutter 项目")
                .disabled(viewModel.isLoading || viewModel.isCleaning)
            }
        }
        .onAppear {
            if !viewModel.hasScannedOnce {
                viewModel.scan()
            }
        }
        .alert("确认清理", isPresented: $viewModel.isShowingCleanConfirmation) {
            Button("移入废纸篓", role: .destructive) {
                viewModel.cleanSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .sheet(item: $selectedVersionForMigration) { version in
            MigrationSheetView(version: version) { targetVersion in
                viewModel.migrateProjects(for: version, to: targetVersion)
                selectedVersionForMigration = nil
            } onCancel: {
                selectedVersionForMigration = nil
            }
        }
    }

    // MARK: - 顶部统计栏

    private var topSummaryBar: some View {
        HStack(spacing: 16) {
            statItem(
                title: "已安装版本",
                value: "\(viewModel.summary.totalVersionsCount) 个",
                icon: "cube.box.fill",
                color: .blue
            )

            Divider().frame(height: 24)

            statItem(
                title: "总空间占用",
                value: ByteFormatter.fileString(from: viewModel.summary.totalSizeBytes),
                icon: "internaldrive.fill",
                color: .indigo
            )

            Divider().frame(height: 24)

            statItem(
                title: "发现 Flutter 项目",
                value: "\(viewModel.summary.totalProjectsFound) 个",
                icon: "folder.fill",
                color: .teal
            )

            Divider().frame(height: 24)

            statItem(
                title: "建议释放空间",
                value: ByteFormatter.fileString(from: viewModel.summary.cleanableSizeBytes),
                icon: "sparkles",
                color: viewModel.summary.cleanableVersionsCount > 0 ? .green : .secondary
            )

            Spacer()

            if let fvmDir = viewModel.fvmDetectedDir {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fvmDir.path)
                } label: {
                    Label("打开 FVM 目录", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
            }
        }
    }

    // MARK: - 扫描目录栏

    private var searchRootsBar: some View {
        HStack(spacing: 8) {
            Label("扫描范围", systemImage: "folder.badge.gearshape")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.searchRoots, id: \.path) { root in
                        HStack(spacing: 4) {
                            Text(root.lastPathComponent)
                                .font(.caption2)
                            Button {
                                viewModel.removeSearchRoot(root)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                        .help(root.path)
                    }
                }
            }

            Spacer()

            Button {
                pickSearchRootFolder()
            } label: {
                Label("添加目录", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }

    // MARK: - 主内容区分流

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isCleaning {
            cleaningProgressView
        } else if viewModel.isLoading {
            loadingProgressView
        } else if viewModel.versions.isEmpty && viewModel.activeTab == .versions {
            if viewModel.hasScannedOnce {
                emptyVersionsView
            } else {
                loadingProgressView
            }
        } else {
            if viewModel.activeTab == .versions {
                versionsListView
            } else {
                projectsListView
            }
        }
    }

    // MARK: - 加载与空状态

    private var loadingProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在扫描 FVM 版本与本机 Flutter 项目...")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("正在全盘深度分析项目依赖与 FVM 锁定关系")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cleaningProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在将选中的 Flutter SDK 移入废纸篓...")
                .font(.callout.weight(.medium))
            Text("可在 macOS 废纸篓中随时恢复")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyVersionsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("未检测到已安装的 FVM Flutter 版本")
                .font(.headline)
            Text("未在 ~/fvm/versions 或 ~/.fvm/versions 找到已下载的 SDK。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("重新扫描") {
                viewModel.scan()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 版本列表主视图

    private var versionsListView: some View {
        VStack(spacing: 0) {
            filterAndSearchBar
            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredVersions) { version in
                        versionCard(version)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - 筛选与搜索工具条

    private var filterAndSearchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索版本或项目名称...", text: $viewModel.searchText)
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

            Picker("状态筛选", selection: $viewModel.selectedStatusFilter) {
                Text("全部状态 (\(viewModel.versions.count))").tag(FVMRecommendationStatus?.none)
                ForEach(FVMRecommendationStatus.allCases, id: \.self) { status in
                    let count = viewModel.versions.filter { $0.status == status }.count
                    Text("\(status.title) (\(count))").tag(FVMRecommendationStatus?.some(status))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Spacer()

            Button("全选建议项") {
                viewModel.selectSafeVersions()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("取消选择") {
                viewModel.deselectAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.selectedVersionIds.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 单个版本卡片

    private func versionCard(_ version: FVMInstalledVersion) -> some View {
        let isExpanded = expandedVersionIds.contains(version.id)
        let isSelected = viewModel.selectedVersionIds.contains(version.id)

        return VStack(spacing: 0) {
            // 卡片头部（点击整行可展开/收起项目列表）
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in viewModel.toggleSelection(version.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(version.status.isProtected)

                Image(systemName: "shippingbox.fill")
                    .font(.title2)
                    .foregroundStyle(versionColor(for: version))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Flutter \(version.versionName)")
                            .font(.headline)

                        if version.isGlobal {
                            Text("GLOBAL 默认")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .cornerRadius(4)
                        }

                        statusBadge(version.status)
                    }

                    HStack(spacing: 12) {
                        Text(ByteFormatter.fileString(from: version.diskSizeBytes))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.tertiary)

                        if version.projects.isEmpty {
                            Text("无本地项目使用 (0 引用)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(version.projects.count) 个项目正在使用")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(version.status.isProtected ? Color.primary : Color.blue)
                        }
                    }
                }

                Spacer()

                // 操作区
                HStack(spacing: 8) {
                    if let alt = version.alternativeVersion, !version.projects.isEmpty {
                        Button {
                            selectedVersionForMigration = version
                        } label: {
                            Label("迁移至 \(alt)", systemImage: "arrow.triangle.swap")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("将当前项目配置升级至 \(alt)，以便安全清理旧版本")
                    }

                    if !version.projects.isEmpty {
                        Button {
                            toggleExpand(version.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "收起" : "查看 \(version.projects.count) 个项目")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            }
                            .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: version.path.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中打开此 SDK 目录")
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                if !version.projects.isEmpty {
                    toggleExpand(version.id)
                }
            }

            // 展开的项目列表
            if isExpanded && !version.projects.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("依赖此 Flutter \(version.versionName) 的项目清单：")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("共 \(version.projects.count) 个项目")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(version.projects) { proj in
                        projectRow(proj)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private func toggleExpand(_ id: String) {
        if expandedVersionIds.contains(id) {
            expandedVersionIds.remove(id)
        } else {
            expandedVersionIds.insert(id)
        }
    }

    private func projectRow(_ proj: FlutterProjectInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.teal)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(proj.name)
                        .font(.callout.weight(.semibold))

                    Text("[\(proj.versionSource.rawValue)]")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(proj.path.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if proj.isActiveRecently {
                    Text("近期活跃")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                } else if proj.isArchived {
                    Text("半年以上未动")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("正常维护")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("更新于: \(formattedDate(proj.effectiveActiveDate))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(proj.path.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制项目路径")

                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: proj.path.path)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中定位项目")
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - 按项目查看视图

    private var projectsListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("共扫描到 \(viewModel.allProjects.count) 个本地 Flutter 项目")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("搜索项目名称或路径...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if viewModel.filteredProjects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("未找到匹配的 Flutter 项目")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredProjects) { proj in
                            projectGlobalCard(proj)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func projectGlobalCard(_ proj: FlutterProjectInfo) -> some View {
        let isInstalled = viewModel.versions.contains { ver in
            if let declared = proj.declaredVersion {
                return ver.versionName == declared || declared.contains(ver.versionName)
            }
            return ver.isGlobal
        }

        return HStack(spacing: 12) {
            Image(systemName: "cube.box")
                .font(.title2)
                .foregroundStyle(isInstalled ? .teal : .red)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(proj.name)
                        .font(.headline)

                    if let ver = proj.declaredVersion {
                        Text("Flutter \(ver)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isInstalled ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                            .foregroundStyle(isInstalled ? Color.green : Color.red)
                            .cornerRadius(4)
                    } else {
                        Text("跟随全局默认")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("[\(proj.versionSource.rawValue)]")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(proj.path.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(proj.isActiveRecently ? "近期活跃" : "历史项目")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(proj.isActiveRecently ? .green : .orange)

                Text("修改于: \(formattedDate(proj.effectiveActiveDate))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: proj.path.path)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中打开")
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 辅助组件与样式

    private func statusBadge(_ status: FVMRecommendationStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor(status))
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(badgeColor(status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(badgeColor(status).opacity(0.12))
        .cornerRadius(4)
    }

    private func badgeColor(_ status: FVMRecommendationStatus) -> Color {
        switch status {
        case .safeToClean: .green
        case .redundantPatch: .blue
        case .staleInUse: .orange
        case .activeInUse: .red
        case .globalDefault: .purple
        }
    }

    private func versionColor(for version: FVMInstalledVersion) -> Color {
        if version.isGlobal { return .purple }
        switch version.status {
        case .safeToClean: return .green
        case .redundantPatch: return .blue
        case .staleInUse: return .orange
        case .activeInUse: return .red
        case .globalDefault: return .purple
        }
    }

    // MARK: - 底部操作栏

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text("已勾选 \(viewModel.selectedVersions.count) 个版本，预计释放 \(ByteFormatter.fileString(from: viewModel.selectedSizeBytes)) 空间")
                .font(.callout)
                .foregroundStyle(viewModel.selectedVersions.isEmpty ? .secondary : .primary)

            Spacer()

            Button(role: .destructive) {
                viewModel.isShowingCleanConfirmation = true
            } label: {
                Label("清理所选版本 (\(ByteFormatter.fileString(from: viewModel.selectedSizeBytes)))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedVersions.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var confirmationMessage: String {
        let count = viewModel.selectedVersions.count
        let size = ByteFormatter.fileString(from: viewModel.selectedSizeBytes)
        let names = viewModel.selectedVersions.map(\.versionName).joined(separator: ", ")
        return "确定要将选中的 \(count) 个 Flutter SDK 版本 (\(names)) 移入废纸篓吗？\n\n预计释放空间：\(size)\n（操作后可随时在 macOS 废纸篓中恢复）"
    }

    private func pickSearchRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择项目根目录"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addSearchRoot(url)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - 迁移向导弹窗

private struct MigrationSheetView: View {
    let version: FVMInstalledVersion
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var targetVersion: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.triangle.swap")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("项目 Flutter 版本迁移向导")
                    .font(.headline)
            }

            Text("当前版本 Flutter \(version.versionName) 关联了 \(version.projects.count) 个项目。为了能够安全清理此 SDK，可将这些项目一键升级配置到本地已安装的更高补丁版本。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Text("受影响的项目：")
                .font(.caption.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(version.projects) { proj in
                        HStack {
                            Text("• \(proj.name)")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(proj.path.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxHeight: 120)

            Divider()

            HStack {
                Text("迁移目标版本：")
                    .font(.callout.weight(.medium))
                TextField("目标版本号", text: $targetVersion)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            Text("执行后将自动更新上述项目的 .fvm/fvm_config.json 以及 flutter_sdk 软链接。")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    onCancel()
                }
                Button("迁移并应用") {
                    onConfirm(targetVersion)
                }
                .buttonStyle(.borderedProminent)
                .disabled(targetVersion.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let alt = version.alternativeVersion {
                targetVersion = alt
            }
        }
    }
}
