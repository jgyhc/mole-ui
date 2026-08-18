import SwiftUI

/// 独立进程监控页面：支持全量系统进程监控、搜索、多维排序与结束进程管理。
struct ProcessesView: View {
    @StateObject private var viewModel = ProcessesViewModel()
    @State private var hoveredPid: Int32?

    var body: some View {
        VStack(spacing: 16) {
            headerStatsCard
            filterAndSearchToolbar
            processListView
        }
        .padding(20)
        .navigationTitle("进程监控")
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.refreshNow()
                } label: {
                    Label("立即刷新", systemImage: "arrow.clockwise")
                }
                .help("立即采样一次最新进程状态")

                Button {
                    viewModel.togglePaused()
                } label: {
                    Label(
                        viewModel.isPaused ? "继续监控" : "暂停监控",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .help(viewModel.isPaused ? "继续定时采样" : "暂停定时采样")
            }
        }
        .alert(
            "确认结束进程？",
            isPresented: Binding(
                get: { viewModel.processToTerminate != nil },
                set: { if !$0 { viewModel.processToTerminate = nil } }
            ),
            presenting: viewModel.processToTerminate
        ) { proc in
            Button("强制结束", role: .destructive) {
                viewModel.terminateProcess(proc, force: true)
            }
            Button("正常退出") {
                viewModel.terminateProcess(proc, force: false)
            }
            Button("取消", role: .cancel) {
                viewModel.processToTerminate = nil
            }
        } message: { proc in
            Text("即将终止「\(proc.name)」（PID: \(proc.pid)）。未保存的数据可能会丢失。")
        }
        .alert(
            "操作提示",
            isPresented: Binding(
                get: { viewModel.terminateErrorMessage != nil },
                set: { if !$0 { viewModel.terminateErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                viewModel.terminateErrorMessage = nil
            }
        } message: {
            Text(viewModel.terminateErrorMessage ?? "")
        }
    }

    // MARK: - 顶部统计卡片

    private var headerStatsCard: some View {
        HStack(spacing: 16) {
            statItem(
                title: "运行进程总数",
                value: "\(viewModel.totalProcessCount)",
                symbol: "list.bullet.rectangle.portrait",
                color: .accentColor
            )

            Divider()
                .frame(height: 36)

            statItem(
                title: "高负载进程 (CPU > 10%)",
                value: "\(viewModel.highCPUCount)",
                symbol: "flame.fill",
                color: viewModel.highCPUCount > 0 ? .orange : .secondary
            )

            Divider()
                .frame(height: 36)

            statItem(
                title: "总常驻物理内存",
                value: ByteFormatter.memoryString(from: Int64(viewModel.totalResidentMemory)),
                symbol: "memorychip",
                color: .blue
            )

            Spacer()

            // 采样状态指示
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isPaused ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isPaused ? "监控已暂停" : "2 秒实时采样")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(viewModel.isPaused ? .orange : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                )

                Text("更新于 \(viewModel.lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func statItem(title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - 搜索与过滤工具栏

    private var filterAndSearchToolbar: some View {
        HStack(spacing: 12) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("搜索进程名称或 PID…", text: $viewModel.searchText)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
            )
            .frame(minWidth: 200, idealWidth: 260)

            // 快捷过滤分类
            Picker("", selection: $viewModel.filterKind) {
                ForEach(ProcessFilterKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Spacer()

            // 排序字段
            HStack(spacing: 6) {
                Text("排序：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $viewModel.sortField) {
                    ForEach(ProcessSortField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Button {
                    viewModel.sortAscending.toggle()
                } label: {
                    Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                }
                .help(viewModel.sortAscending ? "升序排列" : "降序排列")
            }
        }
    }

    // MARK: - 进程列表

    private var processListView: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 12) {
                Text("进程名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID")
                    .frame(width: 80, alignment: .trailing)
                Text("CPU 使用率")
                    .frame(width: 120, alignment: .trailing)
                Text("物理内存")
                    .frame(width: 100, alignment: .trailing)
                Text("操作")
                    .frame(width: 70, alignment: .center)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))

            Divider()

            let list = viewModel.filteredProcesses

            if viewModel.isLoading && list.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在采集系统进程列表…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else if list.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("未找到符合条件的进程")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, proc in
                            processRow(proc: proc, isEven: index % 2 == 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .cardBackground()
    }

    private func processRow(proc: ProcessMetrics.Usage, isEven: Bool) -> some View {
        let isHovered = hoveredPid == proc.pid

        return HStack(spacing: 12) {
            // 进程名 + 图标
            HStack(spacing: 10) {
                Image(systemName: isSystemProcess(proc) ? "gearshape.2.fill" : "app.fill")
                    .font(.caption)
                    .foregroundStyle(isSystemProcess(proc) ? .secondary : Color.accentColor)
                Text(proc.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // PID
            Text("\(proc.pid)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            // CPU
            HStack(spacing: 6) {
                if proc.cpuPercent > 1.0 {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 36, height: 4)
                        Capsule()
                            .fill(cpuBarColor(proc.cpuPercent))
                            .frame(width: max(4, min(36, CGFloat(proc.cpuPercent / 100.0 * 36))), height: 4)
                    }
                }
                Text(proc.cpuPercent.percentString)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(cpuTextColor(proc.cpuPercent))
            }
            .frame(width: 120, alignment: .trailing)

            // 内存
            Text(ByteFormatter.memoryString(from: Int64(proc.memoryBytes)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(proc.memoryBytes > 500 * 1024 * 1024 ? Color.primary : Color.secondary)
                .frame(width: 100, alignment: .trailing)

            // 操作按钮
            HStack {
                Button {
                    viewModel.processToTerminate = proc
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isHovered ? Color.red : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("结束此进程")
            }
            .frame(width: 70, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : (isEven ? Color.primary.opacity(0.02) : Color.clear))
        )
        .onHover { hovering in
            hoveredPid = hovering ? proc.pid : nil
        }
    }

    private func isSystemProcess(_ proc: ProcessMetrics.Usage) -> Bool {
        proc.pid < 100 || proc.name.hasPrefix("com.apple.") || proc.name.contains("daemon") || proc.name.contains("agent")
    }

    private func cpuTextColor(_ cpu: Double) -> Color {
        if cpu > 80 { return .red }
        if cpu > 30 { return .orange }
        return .primary
    }

    private func cpuBarColor(_ cpu: Double) -> Color {
        if cpu > 80 { return .red }
        if cpu > 30 { return .orange }
        return .accentColor
    }
}

private extension View {
    /// 原生卡片背景
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.8)
        )
    }
}
