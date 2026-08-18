import SwiftUI

/// 侧边栏导航。
struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        List(selection: $selection) {
            Section("概览") {
                SidebarRow(section: .dashboard)
                SidebarRow(section: .processes)
            }
            Section("清理") {
                SidebarRow(section: .clean)
                SidebarRow(section: .uninstall)
                SidebarRow(section: .purge)
                SidebarRow(section: .installers)
                SidebarRow(section: .fvm)
                SidebarRow(section: .gradle)
            }
            Section("工具") {
                SidebarRow(section: .analyze)
                SidebarRow(section: .optimize)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    }
}

private struct SidebarRow: View {
    let section: AppSection

    var body: some View {
        Label(section.title, systemImage: section.symbol)
            .tag(section)
    }
}
