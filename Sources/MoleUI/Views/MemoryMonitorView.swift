import SwiftUI

/// 内存监控子页面：系统总内存概览 + 进程内存占用条形图（Top 10 + Other）+ 排序列表。
struct MemoryMonitorView: View {
    @StateObject private var viewModel = MemoryMonitorViewModel()

    /// 由父视图传入的最新进程数据与内存快照。
    let processes: [ProcessMetrics.Usage]
    let memorySnapshot: MemoryMetrics.Snapshot?

    var body: some View {
        VStack(spacing: 16) {
            systemMemorySummary
            memoryBarChart
            processMemoryList
        }
        .onAppear { refresh() }
        .onChange(of: processes.map(\.id)) { _ in refresh() }
    }

    // MARK: - 系统内存概览卡片

    private var systemMemorySummary: some View {
        HStack(spacing: 16) {
            MemoryStatCard(
                title: "物理内存总量",
                value: ByteFormatter.memoryString(from: Int64(viewModel.totalMemory)),
                symbol: "memorychip.fill",
                color: .accentColor
            )
            MemoryStatCard(
                title: "已使用",
                value: ByteFormatter.memoryString(from: Int64(viewModel.usedMemory)),
                symbol: "memorychip",
                color: .orange
            )
            MemoryStatCard(
                title: "空闲",
                value: ByteFormatter.memoryString(from: Int64(viewModel.freeMemory)),
                symbol: "leaf.fill",
                color: .green
            )
            MemoryStatCard(
                title: "可回收 (inactive)",
                value: ByteFormatter.memoryString(from: Int64(viewModel.inactiveMemory)),
                symbol: "arrow.triangle.2.circlepath",
                color: .blue
            )
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - 内存占用条形图

    private var memoryBarChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("进程内存占用分布")
                    .font(.headline)
                Spacer()
                Text("Top 10 进程 + 其他")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 横向堆叠条形图
            if viewModel.segments.isEmpty {
                HStack {
                    Spacer()
                    Text("暂无进程数据")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 48)
            } else {
                geometryBar
                legendList
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - 条形图（GeometryReader 精确比例）

    private var geometryBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(viewModel.segments) { segment in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(CGFloat(segment.percentOfTotal) / 100 * geo.size.width, 4))
                    }
                }
                .frame(height: 32)
            }
            .frame(height: 32)

            // 使用比例标注
            HStack {
                ForEach(viewModel.segments) { segment in
                    if segment.percentOfTotal >= 2.0 {
                        Text(String(format: "%.1f%%", segment.percentOfTotal))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    // MARK: - 颜色图例

    private var legendList: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(viewModel.segments) { segment in
                HStack(spacing: 6) {
                    Circle()
                        .fill(segment.color)
                        .frame(width: 8, height: 8)
                    Text(segment.pid > 0 ? segment.name : segment.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(ByteFormatter.memoryString(from: Int64(segment.memoryBytes)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 进程内存排序列表

    private var processMemoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(spacing: 12) {
                Text("进程名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID")
                    .frame(width: 80, alignment: .trailing)
                Text("内存占用")
                    .frame(width: 100, alignment: .trailing)
                Text("占比")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))

            Divider()

            if viewModel.sortedProcesses.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "memorychip")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("暂无进程数据")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(viewModel.sortedProcesses.enumerated()), id: \.element.id) { index, proc in
                            memoryRow(proc: proc, rank: index + 1, isEven: index % 2 == 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .cardBackground()
    }

    private func memoryRow(proc: ProcessMetrics.Usage, rank: Int, isEven: Bool) -> some View {
        let pct = viewModel.totalMemory > 0
            ? Double(proc.memoryBytes) / Double(viewModel.totalMemory) * 100
            : 0
        let color = segmentColors[min(rank - 1, segmentColors.count - 1)]

        return HStack(spacing: 12) {
            // 排名色标 + 进程名
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
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

            // 内存
            Text(ByteFormatter.memoryString(from: Int64(proc.memoryBytes)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(proc.memoryBytes > 500 * 1024 * 1024 ? .primary : .secondary)
                .frame(width: 100, alignment: .trailing)

            // 占比
            Text(String(format: "%.1f%%", pct))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(pct > 10 ? .orange : .secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isEven ? Color.primary.opacity(0.02) : Color.clear)
        )
    }

    // MARK: - Helpers

    private func refresh() {
        viewModel.refresh(processes: processes, snapshot: memorySnapshot)
    }
}

// MARK: - 内存统计小卡片

private struct MemoryStatCard: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
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
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 调色板（与 ViewModel 共享）

private let segmentColors: [Color] = [
    .blue, .green, .orange, .purple, .red,
    .teal, .pink, .indigo, .yellow, .mint,
]

// MARK: - 卡片背景（复用 ProcessesView 中的风格）

private extension View {
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