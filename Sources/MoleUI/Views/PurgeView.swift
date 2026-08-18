import SwiftUI
import AppKit

/// 项目产物清理：识别项目类型（Flutter / Rust / SwiftPM / Node / Gradle / Python / Xcode 等），
/// 用类型化清单收集产物，执行时优先调用官方清理命令（flutter clean / cargo clean 等）。
struct PurgeView: View {
    @ObservedObject private var viewModel = PurgeViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            rootBar
            Divider()

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isCleaning)

            if !viewModel.candidates.isEmpty && !viewModel.isCleaning {
                Divider()
                summaryBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("项目产物清理")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.scan()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .help("重新扫描所有配置的目录")
                .disabled(viewModel.isLoading || viewModel.isCleaning)

                Button {
                    pickFolder()
                } label: {
                    Label("添加目录", systemImage: "folder.badge.plus")
                }
                .help("添加要扫描的项目目录")
            }
        }
        .alert("确认清理", isPresented: $viewModel.isShowingCleanConfirmation) {
            Button("确认清理", role: .destructive) { viewModel.cleanSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - 主内容区分流

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isCleaning {
            cleaningProgressView
        } else if viewModel.isLoading {
            scanProgressView
        } else if viewModel.candidates.isEmpty {
            if !viewModel.hasScannedOnce {
                initialGuideView
            } else if viewModel.roots.isEmpty {
                noRootsConfiguredView
            } else {
                noArtifactsFoundView
            }
        } else {
            candidateList
        }
    }

    // MARK: - 顶部目录配置栏

    private var rootBar: some View {
        HStack(spacing: 10) {
            Label("扫描目录", systemImage: "folder")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            if viewModel.roots.isEmpty {
                Text("尚未添加扫描目录（建议添加日常存放代码的文件夹）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.roots, id: \.path) { root in
                            rootChip(root)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Spacer()

            Button {
                pickFolder()
            } label: {
                Label("添加", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("添加自定义项目文件夹")

            Button {
                viewModel.scan()
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("扫描", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isLoading || viewModel.isCleaning || viewModel.roots.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func rootChip(_ root: URL) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            Text(root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Button {
                viewModel.removeRoot(root)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("从扫描列表中移除「\(root.path)」")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        panel.message = "选择包含项目的目录（将递归扫描构建产物）"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addRoot(url)
        }
    }

    // MARK: - 初始未扫描引导页 (Hero Initial View)

    private var initialGuideView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 顶部 Hero 宣传卡
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("智能项目产物清理")
                        .font(.title2.weight(.bold))

                    Text("自动识别开发项目，精准清理 node_modules、target、DerivedData、build 等大型构建缓存与临时文件，一键释放数十 GB 磁盘空间。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)

                    HStack(spacing: 12) {
                        Button {
                            viewModel.scan()
                        } label: {
                            Label("开始扫描项目", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            pickFolder()
                        } label: {
                            Label("添加扫描目录", systemImage: "folder.badge.plus")
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 16)

                // 支持的语言和框架矩阵
                VStack(alignment: .leading, spacing: 12) {
                    Text("支持清理的开发语言与框架")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        supportedTypeCard(
                            title: "Node.js / 前端",
                            symbol: "cube.box.fill",
                            color: .green,
                            artifacts: "node_modules, .next, dist, build",
                            action: "安全清理"
                        )
                        supportedTypeCard(
                            title: "Rust",
                            symbol: "flame.fill",
                            color: .orange,
                            artifacts: "target 构建目录",
                            action: "cargo clean"
                        )
                        supportedTypeCard(
                            title: "Xcode / SwiftPM",
                            symbol: "hammer.fill",
                            color: .blue,
                            artifacts: "DerivedData, .build, .swiftpm",
                            action: "swift package clean"
                        )
                        supportedTypeCard(
                            title: "Flutter / Dart",
                            symbol: "bird.fill",
                            color: .teal,
                            artifacts: ".dart_tool, build, ephemeral",
                            action: "flutter clean"
                        )
                        supportedTypeCard(
                            title: "Android / Gradle",
                            symbol: "building.2.fill",
                            color: .indigo,
                            artifacts: ".gradle, build, .cxx",
                            action: "./gradlew clean"
                        )
                        supportedTypeCard(
                            title: "Python 虚拟环境",
                            symbol: "snake.fill",
                            color: .yellow,
                            artifacts: ".venv, __pycache__, .pytest_cache",
                            action: "安全清理"
                        )
                    }
                }
                .frame(maxWidth: 680)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func supportedTypeCard(title: String, symbol: String, color: Color, artifacts: String, action: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Text(artifacts)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)

            HStack {
                Text(action)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(color.opacity(0.12))
                    )
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.8)
        )
    }

    // MARK: - 无配置目录空状态

    private var noRootsConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("尚未配置扫描目录")
                    .font(.title3.weight(.bold))
                Text("点击上方「添加」选择存放开发项目的文件夹（如 Projects / Workspace）。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                pickFolder()
            } label: {
                Label("添加扫描目录", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - 无产物结果空状态

    private var noArtifactsFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text("未发现可清理的构建产物")
                    .font(.title3.weight(.bold))
                Text("已扫描 \(viewModel.roots.count) 个目录中的所有项目，项目目录干净，无需清理。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.scan()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - 扫描进度

    private var scanProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                Text("正在扫描项目产物…")
                    .font(.title3.weight(.semibold))
                Text(viewModel.currentPath.isEmpty ? "正在遍历项目目录…" : viewModel.currentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - 清理进度

    private var cleaningProgressView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                Text("正在清理项目产物…")
                    .font(.title3.weight(.semibold))
                Text(viewModel.cleanProgressText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
                    .animation(.default, value: viewModel.cleanProgressText)
            }

            ProgressView(value: viewModel.cleanProgress)
                .frame(width: 320)
                .animation(.easeInOut(duration: 0.3), value: viewModel.cleanProgress)

            Text("已完成 \(viewModel.cleanCompleted) / \(viewModel.cleanTotal)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .transition(.opacity)
    }

    // MARK: - 产物列表

    private var candidateList: some View {
        List {
            ForEach(viewModel.groupedCandidates, id: \.type) { group in
                Section {
                    if group.items.isEmpty {
                        EmptyView()
                    } else {
                        ForEach(group.items) { candidate in
                            candidateRow(candidate)
                        }
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func groupHeader(_ group: (type: ProjectType, items: [PurgeCandidate])) -> some View {
        HStack(spacing: 6) {
            Label(group.type.title, systemImage: group.type.symbol)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(ByteFormatter.fileString(from: group.items.reduce(0) { $0 + $1.totalSize }))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Toggle("", isOn: selectAllBinding(for: group.type))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("全选此类型")
        }
        .padding(.vertical, 2)
    }

    private func candidateRow(_ candidate: PurgeCandidate) -> some View {
        DisclosureGroup {
            ForEach(candidate.artifacts) { artifact in
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.tertiary)
                    Text(artifact.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(artifact.fileCount) 项")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Text(ByteFormatter.fileString(from: artifact.size))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 22)
                .padding(.vertical, 2)
            }
        } label: {
            HStack(spacing: 8) {
                Toggle("", isOn: candidateBinding(for: candidate))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                Image(systemName: candidate.type.symbol)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(candidate.projectName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(candidate.type.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    Text(candidate.projectURL.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if candidate.isRecent {
                    Text("近期活跃")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
                Label(candidate.cleanLabel, systemImage: candidate.usesCommand ? "terminal" : "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(ByteFormatter.fileString(from: candidate.totalSize))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 汇总栏

    private var summaryBar: some View {
        HStack(spacing: 12) {
            Text("共 \(viewModel.candidates.count) 个项目（\(ByteFormatter.fileString(from: viewModel.totalSize))）")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("· 已选 \(viewModel.selectedCount) 项（\(ByteFormatter.fileString(from: viewModel.selectedSize))）")
                .font(.callout.weight(.medium))
                .foregroundStyle(viewModel.selectedCount > 0 ? Color.accentColor : Color.secondary)

            Spacer()

            if let message = viewModel.lastCleanMessage {
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
                viewModel.isShowingCleanConfirmation = true
            } label: {
                Label("清理所选", systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.selectedCandidates.isEmpty || viewModel.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var confirmationMessage: String {
        let commandCount = viewModel.selectedCandidates.filter { id in
            viewModel.candidates.first { $0.id == id }?.usesCommand == true
        }.count
        var message = "将清理选中的 \(viewModel.selectedCount) 个项目（共 \(ByteFormatter.fileString(from: viewModel.selectedSize))）。"
        if commandCount > 0 {
            message += "\n其中 \(commandCount) 个使用官方清理命令（如 flutter clean / cargo clean），其余移入废纸篓（可恢复）。"
        } else {
            message += "\n全部移入废纸篓，可在废纸篓中恢复。"
        }
        return message
    }

    // MARK: - 绑定

    private func candidateBinding(for candidate: PurgeCandidate) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSelected(candidate) },
            set: { viewModel.setSelected($0, for: candidate) }
        )
    }

    private func selectAllBinding(for type: ProjectType) -> Binding<Bool> {
        Binding(
            get: { viewModel.candidates.allSatisfy { $0.type != type || viewModel.isSelected($0) } },
            set: { viewModel.setSelected($0, for: type) }
        )
    }
}
