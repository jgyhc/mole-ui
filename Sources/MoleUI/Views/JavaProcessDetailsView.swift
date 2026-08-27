import SwiftUI

struct JavaProcessDetailsView: View {
    let details: ProcessMetrics.JavaProcessDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(details.name)
                        .font(.title2.weight(.semibold))
                    Text("PID \(details.pid) · \(details.activitySummary)")
                        .font(.subheadline)
                        .foregroundStyle(details.isInactive ? .orange : .secondary)
                }
                Spacer()
                Text(details.isInactive ? "建议清理" : "仍可能活跃")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((details.isInactive ? Color.orange : Color.green).opacity(0.12))
                    .foregroundStyle(details.isInactive ? .orange : .green)
                    .clipShape(Capsule())
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    detailRow("CPU / 内存", "\(details.cpuPercent.percentString) / \(ByteFormatter.memoryString(from: Int64(details.memoryBytes)))")
                    detailRow("父进程", "PID \(details.parentPID) · \(details.parentAlive ? "仍在运行" : "已退出或不可见")")
                    detailRow("启动时间", details.startDate?.formatted(date: .abbreviated, time: .standard) ?? "未知")
                    detailRow("可执行文件", details.executablePath ?? "无法读取（可能需要权限）")
                    detailRow("工作目录", details.workingDirectory ?? "无法读取（可能需要权限）")
                    detailRow("监听端口", details.portInspectionSucceeded
                        ? (details.listeningPorts.isEmpty ? "无" : details.listeningPorts.map(String.init).joined(separator: ", "))
                        : "无法检查")

                    VStack(alignment: .leading, spacing: 5) {
                        Text("启动命令")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(details.commandLine)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("父进程链")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if details.parentChain.isEmpty {
                            Text("无法读取")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(details.parentChain.enumerated()), id: \.offset) { index, parent in
                                Label(parent, systemImage: index == details.parentChain.count - 1 ? "arrow.turn.up.left" : "arrow.down")
                                    .font(.callout)
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
