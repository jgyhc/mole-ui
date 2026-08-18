import SwiftUI
import Charts

/// 状态监控仪表盘：健康分 + CPU/内存/磁盘/网络/电池/系统规格实时监控。
struct DashboardView: View {
    @StateObject private var viewModel = StatusViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerView
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    cpuCard
                    memoryCard
                    diskCard
                    networkCard
                    batteryOrHardwareCard
                    infoCard
                }
            }
            .padding(20)
        }
        .navigationTitle("状态监控")
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.togglePaused()
                } label: {
                    Label(
                        viewModel.isPaused ? "继续采样" : "暂停采样",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .help(viewModel.isPaused ? "继续定时采样" : "暂停定时采样")
            }
        }
    }

    // MARK: - 头部：健康分 + 系统概览 + 负载

    private var headerView: some View {
        HStack(spacing: 24) {
            HealthCompassView(score: viewModel.sample?.healthScore ?? 0)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    Text(viewModel.sample?.info.chip ?? "—")
                        .font(.title3.weight(.bold))
                }

                HStack(spacing: 8) {
                    Label(ByteFormatter.memoryString(from: Int64(viewModel.sample?.info.memory ?? 0)), systemImage: "memorychip")
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Label(osShort, systemImage: "desktopcomputer")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label("运行 \(DurationFormatter.uptime(from: viewModel.sample?.info.uptime ?? 0))", systemImage: "clock")
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Label(viewModel.sample?.info.hostName ?? "—", systemImage: "network")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isPaused ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isPaused ? "采样已暂停" : "实时监控中")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(viewModel.isPaused ? .orange : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                )

                VStack(alignment: .trailing, spacing: 4) {
                    Text("系统负载 (1 / 5 / 15 分钟)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        loadBadge(title: "1m", value: viewModel.sample?.loadAverage.0 ?? 0)
                        loadBadge(title: "5m", value: viewModel.sample?.loadAverage.1 ?? 0)
                        loadBadge(title: "15m", value: viewModel.sample?.loadAverage.2 ?? 0)
                    }
                }
            }
        }
        .padding(18)
        .cardBackground()
    }

    private func loadBadge(title: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.2f", value))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var osShort: String {
        let full = viewModel.sample?.info.osVersion ?? ""
        if let range = full.range(of: #"Version (\d+\.\d+)"#, options: .regularExpression) {
            let match = full[range].replacingOccurrences(of: "Version ", with: "")
            return "macOS \(match)"
        }
        return full
    }

    // MARK: - CPU 卡片

    private var cpuCard: some View {
        MetricCard(title: "CPU 处理器", symbol: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.sample?.cpuUsage.percentString ?? "—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(cpuColor(for: viewModel.sample?.cpuUsage ?? 0))
                    Spacer()
                    Text("\(viewModel.sample?.cpuPerCore.count ?? 0) 核心负载")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }

                // 核心柱状图
                coreBars

                // 历史趋势
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("使用率走势 (近 60 次采样)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    historyAreaChart(viewModel.cpuHistory, color: .accentColor)
                }
            }
        }
    }

    private func cpuColor(for usage: Double) -> Color {
        if usage > 85 { return .red }
        if usage > 60 { return .orange }
        return .primary
    }

    private var coreBars: some View {
        let cores = viewModel.sample?.cpuPerCore ?? []
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(cores.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: barColors(for: value),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(height: max(3, geo.size.height * CGFloat(value / 100)))
                            }
                        }
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 52)
        }
    }

    private func barColors(for value: Double) -> [Color] {
        if value > 85 {
            return [.orange, .red]
        } else if value > 60 {
            return [.accentColor, .orange]
        } else {
            return [Color.accentColor.opacity(0.7), Color.accentColor]
        }
    }

    // MARK: - 内存卡片

    private var memoryCard: some View {
        MetricCard(title: "内存占用", symbol: "memorychip") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.sample?.memoryUsedPercent.percentString ?? "—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.sample?.memoryUsedPercent ?? 0 > 85 ? Color.orange : Color.primary)
                    Spacer()
                    Text("已用 \(ByteFormatter.memoryString(from: Int64(viewModel.sample?.memoryUsed ?? 0))) / 共 \(ByteFormatter.memoryString(from: Int64(viewModel.sample?.memoryTotal ?? 0)))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }

                // 内存分配分段条
                memoryProgressBar

                // 历史趋势
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("内存走势 (近 60 次采样)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    historyAreaChart(viewModel.memoryHistory, color: .blue)
                }
            }
        }
    }

    private var memoryProgressBar: some View {
        let percent = min(max(viewModel.sample?.memoryUsedPercent ?? 0, 0), 100) / 100.0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 8)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * CGFloat(percent)), height: 8)
            }
        }
        .frame(height: 8)
    }

    // MARK: - 磁盘卡片

    private var diskCard: some View {
        MetricCard(title: "磁盘存储", symbol: "internaldrive") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.sample?.diskUsedPercent.percentString ?? "—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.sample?.diskUsedPercent ?? 0 > 90 ? Color.red : Color.primary)
                    Spacer()
                    Text("主卷 (APFS)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }

                diskProgressBar

                // 空间明细网格
                HStack(spacing: 12) {
                    diskMetricBox(
                        title: "已用空间",
                        value: ByteFormatter.fileString(from: viewModel.sample?.diskUsed ?? 0),
                        color: .accentColor
                    )
                    diskMetricBox(
                        title: "剩余可用",
                        value: ByteFormatter.fileString(from: viewModel.sample?.diskAvailable ?? 0),
                        color: .green
                    )
                    diskMetricBox(
                        title: "磁盘总容量",
                        value: ByteFormatter.fileString(from: viewModel.sample?.diskTotal ?? 0),
                        color: .secondary
                    )
                }
            }
        }
    }

    private var diskProgressBar: some View {
        let percent = min(max(viewModel.sample?.diskUsedPercent ?? 0, 0), 100) / 100.0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 8)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: percent > 0.9 ? [Color.orange, Color.red] : [Color.accentColor.opacity(0.8), Color.accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * CGFloat(percent)), height: 8)
            }
        }
        .frame(height: 8)
    }

    private func diskMetricBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color == .secondary ? Color.primary : color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - 网络卡片

    private var networkCard: some View {
        MetricCard(title: "网络流量", symbol: "network") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    networkRatePill(
                        direction: "下载",
                        speed: (viewModel.sample?.networkDownBytesPerSec ?? 0).speedString,
                        icon: "arrow.down.circle.fill",
                        color: .teal
                    )
                    networkRatePill(
                        direction: "上传",
                        speed: (viewModel.sample?.networkUpBytesPerSec ?? 0).speedString,
                        icon: "arrow.up.circle.fill",
                        color: .orange
                    )
                }
                networkDualChart
            }
        }
    }

    private func networkRatePill(direction: String, speed: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(direction)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(speed)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    private var networkDualChart: some View {
        Chart {
            ForEach(viewModel.networkHistory) { point in
                AreaMark(
                    x: .value("时间", point.time),
                    y: .value("下行速率", point.down)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.teal.opacity(0.3), Color.teal.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("时间", point.time),
                    y: .value("下行速率", point.down)
                )
                .foregroundStyle(Color.teal)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))

                LineMark(
                    x: .value("时间", point.time),
                    y: .value("上行速率", point.up)
                )
                .foregroundStyle(Color.orange)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let bytes = value.as(Double.self) {
                        Text(ByteFormatter.fileString(from: Int64(bytes)))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 80)
    }

    // MARK: - 电池与硬件状态卡片

    private var batteryOrHardwareCard: some View {
        let battery = viewModel.sample?.battery
        let hasBattery = battery?.isPresent ?? false

        return MetricCard(
            title: hasBattery ? "电池与电源" : "供电与运行环境",
            symbol: hasBattery ? "battery.100percent" : "powerplug"
        ) {
            if hasBattery, let battery = battery {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                            .frame(width: 68, height: 68)
                        Circle()
                            .trim(from: 0, to: CGFloat(battery.level))
                            .stroke(
                                battery.level > 0.2 ? Color.green : Color.red,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 68, height: 68)
                        Text("\(Int(battery.level * 100))%")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: battery.isCharging ? "bolt.fill" : (battery.isPlugged ? "powerplug.fill" : "battery.100"))
                                .foregroundStyle(battery.isCharging ? Color.orange : Color.green)
                            Text(battery.isCharging ? "正在充电" : (battery.isPlugged ? "已连接电源适配器" : "正在使用电池供电"))
                                .font(.callout.weight(.medium))
                        }
                        Text("当前电量 \(Int(battery.level * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 52, height: 52)
                        Image(systemName: "bolt.badge.checkmark.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("交流电持续供电")
                            .font(.callout.weight(.semibold))
                        Text("台式工作站模式 · 电源稳定接入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 系统信息卡片

    private var infoCard: some View {
        MetricCard(title: "系统规格", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                specRow(symbol: "cpu", label: "核心芯片", value: viewModel.sample?.info.chip ?? "—")
                specRow(symbol: "memorychip", label: "统一内存", value: ByteFormatter.memoryString(from: Int64(viewModel.sample?.info.memory ?? 0)))
                specRow(symbol: "apple.logo", label: "系统版本", value: osShort)
                specRow(symbol: "laptopcomputer", label: "主机标识", value: viewModel.sample?.info.hostName ?? "—")
                specRow(symbol: "clock.arrow.circlepath", label: "连续开机", value: DurationFormatter.uptime(from: viewModel.sample?.info.uptime ?? 0))
            }
        }
    }

    private func specRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - 辅助组件

/// 仪表盘卡片容器
private struct MetricCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

/// 健康度罗盘仪表
private struct HealthCompassView: View {
    let score: Int

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    .frame(width: 76, height: 76)

                Circle()
                    .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100.0)
                    .stroke(
                        LinearGradient(
                            colors: scoreGradient,
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 76)

                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            Text(statusLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(scoreColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(scoreColor.opacity(0.12))
                )
        }
    }

    private var scoreColor: Color {
        switch score {
        case 85...100: .green
        case 65..<85: .teal
        case 45..<65: .orange
        default: .red
        }
    }

    private var scoreGradient: [Color] {
        switch score {
        case 85...100: [.green.opacity(0.8), .green]
        case 65..<85: [.teal, .green]
        case 45..<65: [.orange, .yellow]
        default: [.red, .orange]
        }
    }

    private var statusLabel: String {
        switch score {
        case 85...100: "健康状态极佳"
        case 65..<85: "运行状态良好"
        case 45..<65: "系统轻度负载"
        default: "负载较高建议优化"
        }
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

private extension DashboardView {
    /// 渐变填充历史曲线图
    func historyAreaChart(_ history: [HistoryPoint], color: Color) -> some View {
        Chart(history) { point in
            AreaMark(
                x: .value("时间", point.time),
                y: .value("使用率", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.25), color.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("时间", point.time),
                y: .value("使用率", point.value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.8))
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let intVal = value.as(Int.self) {
                        Text("\(intVal)%")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(height: 80)
    }
}
