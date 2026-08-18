import SwiftUI

/// 系统优化：维护任务列表（重建 LaunchServices、清理 DNS、刷新 Finder 等）。
struct OptimizeView: View {
    @StateObject private var viewModel = OptimizeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                ForEach(OptimizationGroup.allCases) { group in
                    let tasks = viewModel.entries.filter { $0.task.group == group }
                    if !tasks.isEmpty {
                        groupCard(group: group, tasks: tasks)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("系统优化")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.resetAll()
                } label: {
                    Label("重置状态", systemImage: "arrow.counterclockwise")
                }
                .help("将所有任务状态重置为未运行")
                .disabled(viewModel.isRunning)
            }
        }
    }

    // MARK: - 头部总览卡片

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("系统维护与优化")
                        .font(.title3.weight(.semibold))
                    Text("执行底层系统维护任务，修复应用图标异常、清理系统缓存并刷新桌面与网络响应。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.runAll()
                } label: {
                    if viewModel.isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("优化中…")
                        }
                    } else {
                        Label("全部运行", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isRunning || viewModel.runnableCount == 0)
                .help("依次运行全部非管理员任务")
            }

            Divider()

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("共 \(viewModel.entries.count) 项任务")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("可运行 \(viewModel.runnableCount) 项")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if viewModel.hasRunAny {
                    HStack(spacing: 8) {
                        if viewModel.succeededCount > 0 {
                            Label("\(viewModel.succeededCount) 项成功", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if viewModel.failedCount > 0 {
                            Label("\(viewModel.failedCount) 项失败", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if viewModel.skippedCount > 0 {
                            Label("\(viewModel.skippedCount) 项跳过", systemImage: "minus.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.caption)
                    Text("标有「需管理员权限」的任务请在终端中使用 sudo mo optimize 运行")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - 分组卡片

    private func groupCard(group: OptimizationGroup, tasks: [OptimizationTaskEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(group.title, systemImage: group.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 38)
                    }
                    taskRow(entry)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(14)
        .cardBackground()
    }

    private func taskRow(_ entry: OptimizationTaskEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.task.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(entry.task.requiresRoot ? .secondary : Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.task.title)
                        .font(.body.weight(.medium))
                    if entry.task.requiresRoot {
                        Text("需管理员权限")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
                Text(entry.task.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            stateBadge(entry.state)

            if !entry.task.requiresRoot {
                Button {
                    viewModel.runSingle(entry.task)
                } label: {
                    Text(entry.state.isRunning ? "运行中…" : "运行")
                }
                .disabled(viewModel.isRunning)
            }
        }
    }

    @ViewBuilder
    private func stateBadge(_ state: OptimizationTaskState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("运行中")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        case .succeeded(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label("失败", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .help(message)
        case .skipped(let reason):
            Label("跳过", systemImage: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(reason)
        }
    }
}

// MARK: - 样式与状态辅助

private extension View {
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        )
    }
}

extension OptimizationTaskState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
