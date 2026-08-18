import SwiftUI
import AppKit

/// 智能卸载：应用清单 + 关联文件安全分级（应用本体 / 安全缓存 / 应用专属 / 需谨慎与共享）+ 移入废纸篓卸载。
struct UninstallView: View {
    @ObservedObject private var viewModel = UninstallViewModel.shared

    var body: some View {
        HSplitView {
            appList
            detailsPanel
        }
        .navigationTitle("智能卸载")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.loadApps()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("重新扫描已安装应用")
            }
        }
        .onChange(of: viewModel.selectedAppID) { _, _ in
            viewModel.handleSelectionChange()
        }
        .alert("确认卸载", isPresented: $viewModel.isShowingUninstallConfirmation) {
            Button("卸载", role: .destructive) { viewModel.uninstallSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - 应用列表

    private var appList: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在扫描已安装应用…")
                        .font(.headline)
                    Text("已发现 \(viewModel.progress.scannedApps) 个应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.apps.isEmpty {
                ContentUnavailableView {
                    Label("尚未扫描应用", systemImage: "app.dashed")
                } description: {
                    Text("点击「加载应用」扫描已安装应用及其关联文件")
                } actions: {
                    Button("加载应用") { viewModel.loadApps() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                searchField
                List(selection: Binding(
                    get: { viewModel.selectedAppID },
                    set: { id in
                        if let id, let app = viewModel.apps.first(where: { $0.id == id }) {
                            viewModel.select(app)
                        }
                    }
                )) {
                    ForEach(viewModel.filteredApps) { app in
                        appRow(app)
                            .tag(app.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用", text: $viewModel.searchText)
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
        .padding(8)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName)
                    .lineLimit(1)
                Text(subtitle(for: app))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(ByteFormatter.fileString(from: app.size))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 详情面板

    @ViewBuilder
    private var detailsPanel: some View {
        if viewModel.isLoading {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let app = viewModel.selectedApp {
            VStack(spacing: 0) {
                appHeader(app)
                Divider()
                if viewModel.isScanningDetails {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在进行关联文件安全分析…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.associatedFiles.isEmpty {
                    VStack(spacing: 0) {
                        List {
                            appBundleSection(app)
                        }
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                        summaryBar
                    }
                } else {
                    associatedFilesList(app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "选择一个应用",
                systemImage: "square.grid.2x2",
                description: Text("从左侧列表选择要卸载的应用，将进行精准匹配与安全关联分析。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func appHeader(_ app: InstalledApp) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.displayName)
                        .font(.title2.weight(.semibold))
                    if viewModel.isSelectedAppRunning {
                        HStack(spacing: 6) {
                            Label("正在运行", systemImage: "play.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            Button("退出应用") {
                                viewModel.quitSelectedApp()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                Text(subtitle(for: app))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(app.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([app.url])
                    }
                    .font(.caption)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormatter.fileString(from: viewModel.totalUninstallSize))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Text("本体 \(ByteFormatter.fileString(from: app.size))")
                    if viewModel.selectedFilesSize > 0 {
                        Text("+ 关联 \(ByteFormatter.fileString(from: viewModel.selectedFilesSize))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(14)
    }

    private func subtitle(for app: InstalledApp) -> String {
        var parts: [String] = []
        if let version = app.version { parts.append("版本 \(version)") }
        if let identifier = app.bundleIdentifier { parts.append(identifier) }
        return parts.joined(separator: " · ")
    }

    // MARK: - 关联文件列表

    private func associatedFilesList(_ app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            List {
                // 1. 置顶显示应用本体
                appBundleSection(app)

                // 2. 关联文件分类
                ForEach(Array(viewModel.associatedGroups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.files) { file in
                            fileRow(file)
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            summaryBar
        }
    }

    private func appBundleSection(_ app: InstalledApp) -> some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(.tint)
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(app.name).app")
                            .lineLimit(1)
                        safetyBadge(for: .appData)
                    }
                    Text(app.url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(ByteFormatter.fileString(from: app.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } header: {
            HStack(spacing: 6) {
                Label("应用本体", systemImage: "app.gift")
                safetyBadge(for: .appData)
                Spacer()
                Text(ByteFormatter.fileString(from: app.size))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func groupHeader(_ group: (kind: AppAssociatedFileKind, files: [AssociatedFile])) -> some View {
        HStack(spacing: 6) {
            Label(group.kind.title, systemImage: group.kind.symbol)
            safetyBadge(for: group.kind.defaultSafetyLevel)
            Spacer()
            Text(ByteFormatter.fileString(from: group.files.reduce(0) { $0 + $1.size }))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Toggle("", isOn: groupBinding(for: group.kind))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("全选此分类")
        }
    }

    private func fileRow(_ file: AssociatedFile) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: fileBinding(for: file))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: file.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    safetyBadge(for: file.safetyLevel)
                }
                if let note = file.warningNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(ByteFormatter.fileString(from: file.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func safetyBadge(for level: AssociatedFileSafetyLevel) -> some View {
        switch level {
        case .safe:
            Text("安全")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .appData:
            Text("专属")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .caution:
            Text("共享/谨慎")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    // MARK: - 汇总栏

    private var summaryBar: some View {
        HStack(spacing: 12) {
            if let app = viewModel.selectedApp {
                Text("合计 \(ByteFormatter.fileString(from: viewModel.totalUninstallSize))")
                    .font(.callout.weight(.medium))
                Text("（本体 \(ByteFormatter.fileString(from: app.size)) + 关联 \(viewModel.selectedFiles.count) 项 \(ByteFormatter.fileString(from: viewModel.selectedFilesSize))）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.hasSelectedCautionFiles {
                    Label("\(viewModel.selectedCautionFiles.count)项含共享风险", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let message = viewModel.lastUninstallMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Button {
                viewModel.isShowingUninstallConfirmation = true
            } label: {
                Label("卸载", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.hasSelectedCautionFiles ? .orange : .red)
            .disabled(viewModel.selectedApp == nil || viewModel.isSelectedAppRunning)
            .help(viewModel.isSelectedAppRunning ? "应用正在运行，请先退出后再卸载" : "卸载所选应用")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var confirmationMessage: String {
        guard let app = viewModel.selectedApp else { return "" }
        var message = "将「\(app.displayName)」（\(ByteFormatter.fileString(from: app.size))）"
        if viewModel.selectedFiles.isEmpty {
            message += " 移入废纸篓，可在废纸篓中恢复。"
        } else {
            message += " 与选中的 \(viewModel.selectedFiles.count) 项关联文件（\(ByteFormatter.fileString(from: viewModel.selectedFilesSize))）移入废纸篓，可在废纸篓中恢复。"
        }

        if viewModel.hasSelectedCautionFiles {
            message += "\n\n⚠️ 注意：您勾选了 \(viewModel.selectedCautionFiles.count) 项共享/敏感数据（可能影响同套件其他应用或清除用户本地工程/配置），请确认是否一并清理。"
        }

        if viewModel.isSelectedAppRunning {
            message += "\n\n⚠︎ 应用正在运行，卸载可能失败，请先退出应用。"
        }
        return message
    }

    // MARK: - 绑定

    private func fileBinding(for file: AssociatedFile) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedFileIDs.contains(file.id) },
            set: { viewModel.setSelected($0, for: file) }
        )
    }

    private func groupBinding(for kind: AppAssociatedFileKind) -> Binding<Bool> {
        Binding(
            get: {
                let files = viewModel.associatedFiles.filter { $0.kind == kind }
                return !files.isEmpty && files.allSatisfy { viewModel.selectedFileIDs.contains($0.id) }
            },
            set: { viewModel.setSelected($0, for: kind) }
        )
    }
}
