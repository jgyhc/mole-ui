import SwiftUI
import AppKit

/// 设置窗口（⌘,），原生 Form + TabView。
public struct SettingsView: View {
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("moveToTrashInsteadOfDelete") private var moveToTrashInsteadOfDelete = true
    @AppStorage("keepHistoryLog") private var keepHistoryLog = true

    @State private var logText = ""

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            logTab
                .tabItem { Label("操作日志", systemImage: "doc.text") }

            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }

    // MARK: - 通用

    private var generalTab: some View {
        Form {
            Section("安全") {
                Toggle("删除前始终确认", isOn: $confirmBeforeDeleting)
                Toggle("默认移入废纸篓而不是直接删除", isOn: $moveToTrashInsteadOfDelete)
                Toggle("记录操作历史日志", isOn: $keepHistoryLog)
            }
            Section("扫描") {
                LabeledContent("项目产物扫描目录") {
                    Text("~/Projects、~/GitHub、~/dev")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 操作日志

    private var logTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("记录所有删除 / 清理操作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    refreshLog()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([OperationLog.logFileURL])
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
            }
            .padding(8)
            Divider()
            ScrollView {
                Text(logText.isEmpty ? "暂无日志" : logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .foregroundStyle(logText.isEmpty ? .secondary : .primary)
            }
        }
        .onAppear { refreshLog() }
    }

    private func refreshLog() {
        logText = OperationLog.read().joined(separator: "\n")
    }

    // MARK: - 关于

    private var aboutTab: some View {
        Form {
            Section {
                LabeledContent("名称", value: "Mole")
                LabeledContent("版本", value: appVersion)
                LabeledContent("许可", value: "GPL-3.0（源自 tw93/Mole）")
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "0.1.0（开发版）"
    }
}
