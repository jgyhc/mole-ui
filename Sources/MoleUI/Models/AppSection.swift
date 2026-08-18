import Foundation

/// 侧边栏导航分区，对应 Mole 的各个功能模块。
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case processes
    case clean
    case uninstall
    case purge
    case installers
    case fvm
    case gradle
    case analyze
    case optimize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "状态监控"
        case .processes: "进程监控"
        case .clean: "深度清理"
        case .uninstall: "智能卸载"
        case .purge: "项目产物清理"
        case .installers: "安装包清理"
        case .fvm: "Flutter SDK 清理"
        case .gradle: "Gradle 版本清理"
        case .analyze: "磁盘分析"
        case .optimize: "系统优化"
        }
    }

    /// SF Symbols 图标名（macOS 13+ 可用）
    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .processes: "list.bullet.rectangle.portrait"
        case .clean: "sparkles"
        case .uninstall: "trash"
        case .purge: "hammer.fill"
        case .installers: "doc.badge.arrow.up"
        case .fvm: "shippingbox.fill"
        case .gradle: "gearshape.arrow.triangle.2.circlepath"
        case .analyze: "internaldrive"
        case .optimize: "wand.and.stars"
        }
    }

    /// 占位页中展示的功能简介（后续阶段替换为真实实现）
    var placeholderDescription: String {
        switch self {
        case .dashboard:
            "实时展示 CPU、内存、磁盘、网络与电池状态，并给出健康评分（对应 mo status）。"
        case .processes:
            "实时监控系统运行进程，查看 CPU 与内存占用，支持快速搜索与终止异常进程。"
        case .clean:
            "扫描缓存、日志与卸载残留，预览后可勾选清理，默认移入废纸篓（对应 mo clean）。"
        case .uninstall:
            "列出已安装应用及其关联文件，一键卸载并清理残留（对应 mo uninstall）。"
        case .purge:
            "扫描 node_modules、target、.build 等项目构建产物，按需清理（对应 mo purge）。"
        case .installers:
            "扫描 .dmg、.pkg、.zip 等安装包文件，清理占用空间（对应 mo installer）。"
        case .fvm:
            "扫描 FVM 安装的 Flutter 版本及本机 Flutter 项目引用，智能识别闲置版本并安全清理。"
        case .gradle:
            "扫描 ~/.gradle/wrapper/dists 下的已下载 Gradle 发行版与本机项目依赖，安全释放冗余 SDK 占用。"
        case .analyze:
            "以树图可视化磁盘占用，定位大文件与大目录（对应 mo analyze）。"
        case .optimize:
            "执行系统维护任务，如重建 LaunchServices、清理 DNS缓存等（对应 mo optimize）。"
        }
    }
}
