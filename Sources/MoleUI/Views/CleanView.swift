import SwiftUI

/// 深度清理：分类扫描 + 逐项勾选 + 确认后清理（默认移入废纸篓）。
struct CleanView: View {
    @ObservedObject private var viewModel = CleanViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                scanProgressView
            } else if viewModel.results.isEmpty {
                if viewModel.hasScannedOnce {
                    ContentUnavailableView {
                        Label("未发现可清理内容", systemImage: "checkmark.circle")
                    } description: {
                        Text("系统缓存、日志与残留均为空，可稍后重新扫描")
                    } actions: {
                        Button("重新扫描") { viewModel.scan() }
                    }
                } else {
                    ContentUnavailableView {
                        Label("尚未扫描", systemImage: "sparkles")
                    } description: {
                        Text("点击「开始扫描」分析可清理的缓存、日志与残留")
                    } actions: {
                        Button("开始扫描") { viewModel.scan() }
                    }
                }
            } else {
                categoryList
            }

            if !viewModel.results.isEmpty {
                summaryBar
            }
        }
        .navigationTitle("深度清理")
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
            Text(confirmationMessage)
        }
    }

    // MARK: - 扫描进度

    private var scanProgressView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("正在扫描「\(viewModel.progress.currentCategory)」…")
                .font(.headline)
            Text("已处理 \(viewModel.progress.scannedFiles) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 分类列表

    private var categoryList: some View {
        List {
            ForEach(viewModel.results) { result in
                Section {
                    if result.items.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.tertiary)
                            Text("未发现可清理内容")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(result.items) { item in
                            itemRow(item)
                        }
                    }
                } header: {
                    categoryHeader(result)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func categoryHeader(_ result: CleanCategoryResult) -> some View {
        HStack(spacing: 6) {
            Label(result.category.title, systemImage: result.category.symbol)
            if result.category.isDangerous {
                Text("危险")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            }
            Spacer()
            Text(ByteFormatter.fileString(from: result.totalSize))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Toggle("", isOn: selectAllBinding(for: result))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("全选此分类")
        }
    }

    private func itemRow(_ item: CleanItem) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: itemBinding(for: item))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(item.category.isDangerous ? Color.red : .secondary)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(ByteFormatter.fileString(from: item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if item.isPermanent {
                Text("永久删除")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - 汇总栏

    private var summaryBar: some View {
        HStack(spacing: 12) {
            Text("可选 \(ByteFormatter.fileString(from: viewModel.totalSelectableSize))")
                .foregroundStyle(.secondary)
            Text("· 已选 \(viewModel.selectedCount) 项（\(ByteFormatter.fileString(from: viewModel.selectedSize))）")
                .foregroundStyle(viewModel.selectedCount > 0 ? .primary : .secondary)
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
            .tint(viewModel.hasPermanentSelection ? .red : .accentColor)
            .disabled(viewModel.selectedItems.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - 确认文案

    private var confirmationMessage: String {
        var message = "将选中的 \(viewModel.selectedCount) 项（共 \(ByteFormatter.fileString(from: viewModel.selectedSize))）移入废纸篓，可在废纸篓中恢复。"
        if viewModel.hasPermanentSelection {
            message += "\n注意：其中包含废纸篓内容，将永久删除且不可恢复。"
        }
        return message
    }

    // MARK: - 绑定

    private func itemBinding(for item: CleanItem) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSelected(item) },
            set: { viewModel.setSelected($0, for: item) }
        )
    }

    private func selectAllBinding(for result: CleanCategoryResult) -> Binding<Bool> {
        Binding(
            get: { result.items.allSatisfy { viewModel.isSelected($0) } },
            set: { viewModel.setSelected($0, for: result) }
        )
    }
}
