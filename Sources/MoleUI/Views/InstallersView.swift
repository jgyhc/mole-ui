import SwiftUI

/// 安装包清理：扫描下载/桌面/Homebrew 缓存等位置的 .dmg/.pkg/.zip。
struct InstallersView: View {
    @ObservedObject private var viewModel = InstallerViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                scanProgressView
            } else if viewModel.files.isEmpty {
                if viewModel.hasScannedOnce {
                    ContentUnavailableView {
                        Label("未发现安装包", systemImage: "doc.badge.arrow.up")
                    } description: {
                        Text("已扫描下载、桌面、文稿、Homebrew 缓存、iCloud 云盘与邮件下载，未找到 .dmg / .pkg / .zip / .tar.gz 等安装包文件")
                    } actions: {
                        Button("重新扫描") { viewModel.scan() }
                    }
                } else {
                    ContentUnavailableView {
                        Label("尚未扫描", systemImage: "doc.badge.arrow.up")
                    } description: {
                        Text("点击「开始扫描」在下载、桌面、文稿、Homebrew 缓存、iCloud 云盘与邮件下载中查找安装包")
                    } actions: {
                        Button("开始扫描") { viewModel.scan() }
                    }
                }
            } else {
                filesTable
            }

            if !viewModel.files.isEmpty {
                summaryBar
            }
        }
        .navigationTitle("安装包清理")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.scan()
                } label: {
                    Label("扫描", systemImage: "arrow.clockwise")
                }
                .help("重新扫描")
            }
        }
        .alert("确认清理", isPresented: $viewModel.isShowingCleanConfirmation) {
            Button("确认清理", role: .destructive) { viewModel.cleanSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将选中的 \(viewModel.selection.count) 个安装包（共 \(ByteFormatter.fileString(from: viewModel.selectedSize))）移入废纸篓，可在废纸篓中恢复。")
        }
    }

    // MARK: - 扫描进度

    private var scanProgressView: some View {
        VStack(spacing: 10) {
            ProgressView()
            if let source = viewModel.currentSource {
                Text("正在扫描「\(source.title)」…")
                    .font(.headline)
            }
            Text(viewModel.currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 文件表格

    private var filesTable: some View {
        Table(viewModel.files, selection: $viewModel.selection) {
            TableColumn("名称") { file in
                HStack(spacing: 6) {
                    Image(systemName: fileIcon(for: file.url.pathExtension))
                        .foregroundStyle(.secondary)
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            TableColumn("大小") { file in
                Text(ByteFormatter.fileString(from: file.size))
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100, max: 140)
            TableColumn("来源") { file in
                Label(file.source.title, systemImage: sourceSymbol(for: file.source))
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 150, max: 200)
            TableColumn("路径") { file in
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func fileIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case "dmg": "externaldrive"
        case "pkg", "mpkg": "shippingbox"
        case "zip": "archivebox"
        default: "doc"
        }
    }

    private func sourceSymbol(for source: InstallerSource) -> String {
        switch source {
        case .downloads: "arrow.down.circle"
        case .desktop: "macwindow"
        case .documents: "doc.text"
        case .homebrew: "mug"
        case .iCloud: "icloud"
        case .mail: "envelope"
        }
    }

    // MARK: - 汇总栏

    private var summaryBar: some View {
        HStack(spacing: 12) {
            Text("共 \(viewModel.files.count) 个安装包（\(ByteFormatter.fileString(from: viewModel.totalSize))）")
                .foregroundStyle(.secondary)
            Text("· 已选 \(viewModel.selection.count) 项（\(ByteFormatter.fileString(from: viewModel.selectedSize))）")
                .foregroundStyle(viewModel.selection.count > 0 ? .primary : .secondary)
            Spacer()
            if let message = viewModel.lastCleanMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            Button {
                viewModel.isShowingCleanConfirmation = true
            } label: {
                Label("清理所选", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selection.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
