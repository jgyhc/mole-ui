import SwiftUI

/// 应用主窗口：左侧导航 + 右侧详情。
public struct ContentView: View {
    @State private var selection: AppSection = .dashboard

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MoleLayoutProbe"))) { note in
            if let raw = note.object as? String, let section = AppSection(rawValue: raw) {
                selection = section
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard: DashboardView()
        case .processes: ProcessesView()
        case .clean: CleanView()
        case .uninstall: UninstallView()
        case .purge: PurgeView()
        case .installers: InstallersView()
        case .fvm: FVMView()
        case .gradle: GradleView()
        case .analyze: AnalyzeView()
        case .optimize: OptimizeView()
        }
    }
}

// MARK: - 各功能视图（阶段 A 均为占位页）
