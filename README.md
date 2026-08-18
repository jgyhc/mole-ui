# Mole UI 🐾

> **原生、优雅且强劲的 macOS 系统监控与深度清理工具**  
> 致敬终端神器 [tw93/Mole](https://github.com/tw93/Mole)，以纯原生 SwiftUI / AppKit 重新设计打造。

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-6.0%20%2F%205.0%20Mode-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Swift%20Charts-purple.svg)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## ✨ 核心特性

- **⚡️ 纯原生架构**：使用 SwiftUI + Swift Charts 构建，无任何第三方跨平台框架包袱，秒级启动与丝滑流畅的交互体验。
- **📊 实时状态监控 (Dashboard)**：
  - CPU 综合负载、每核占用柱状图与实时曲线
  - 内存分配分布（活跃/联动/非活跃/压缩）与压力监测
  - 磁盘读写与使用率计量 Gauge
  - 实时网络上下行带宽双曲线图
  - 电池健康状态、充放电功率与循环计数
  - 系统健康评分算法与 Top 进程动态追踪
- **🧹 深度系统清理 (Clean)**：
  - 系统及应用缓存、日志文件扫描
  - 卸载残留配置、未清理的 Crash 报告
  - 全流程 Dry-Run 预估与按分类勾选清理
- **📦 智能应用卸载 (Uninstall)**：
  - 深度检索 `/Applications` 与 `~/Applications`
  - 自动挖掘应用相关的 `Application Support`、`Preferences`、`Caches`、`LaunchAgents`、扩展插件等残留文件
  - 支持应用及关联数据一键全选彻底清理
- **🛠️ 系统维护与优化 (Optimize)**：
  - 重建 LaunchServices 数据库（修复应用打开方式错乱）
  - 刷新 DNS 缓存、重置 Spotlight 索引
  - 快速重启 Finder / Dock / 菜单栏系统服务
- **🗂️ 磁盘空间可视化 (Analyze)**：
  - 基于 **Squarified Treemap**（方形树图算法）实现自绘磁盘空间分布图（类 DaisyDisk）
  - 支持层级面包屑深度下钻、目录跳转与大文件快速定位
- **💻 开发者专项清理**：
  - **项目产物清理 (Purge)**：批量扫描 `node_modules`、`target`、`.build`、`build`、`dist` 等重型编译中间产物
  - **FVM 管理清理 (FVM)**：Flutter 多版本 SDK 缓存与无用版本安全清理
  - **Gradle 缓存清理 (Gradle)**：清理 Gradle 构建缓存与下载依赖
- **📥 安装包清理 (Installers)**：
  - 扫描下载目录、桌面、Homebrew 缓存中的 `.dmg`、`.pkg`、`.iso`、`.zip` 等残留安装介质

---

## 🛡️ 安全设计

我们深知系统工具的安全性至关重要：

1. **废纸篓优先原则**：所有删除操作统一通过 `FileManager.trashItem` 移动至系统废纸篓，可随时撤回还原，绝不直接执行不可逆的 `rm -rf`。
2. **核心系统路径保护**：内置路径保护白名单机制，严格阻断对 `/`、`/System`、`/Library`、`/Applications` 根目录及当前运行中应用的删除操作。
3. **安全路径校验**：校验符号链接逃逸与越界路径，杜绝误伤系统关键文件。
4. **完整操作审计**：所有清理/卸载操作均自动记录至 `~/Library/Logs/Mole/operations.log`，随时可回溯排查。

---

## 🛠️ 构建与运行

### 环境要求
- macOS 14.0 (Sonoma) 或更高版本
- Xcode 15.0+ 或 Swift 6.0+ 工具链

### 快速构建独立应用 (.app)

项目中提供了自动化打包脚本，可直接编译并生成原生 `.app` 文件：

```bash
# 克隆仓库
git clone https://github.com/jgyhc/mole-ui.git
cd mole-ui

# 执行打包脚本
./Scripts/make-app.sh
```

构建成功后，将在当前目录生成 `Mole.app`，直接拖入 `/Applications` 即可使用。

### 使用 Xcode 打开工程

```bash
open Mole.xcodeproj
```

或者直接使用 Swift Package Manager 命令行构建并运行测试：

```bash
# 运行单元测试
swift test

# 命令行运行
swift run Mole
```

> **注意**：由于需要扫描用户主目录、缓存与应用残留，初次运行并在进行深度清理/卸载时，建议在「系统设置 -> 隐私与安全性 -> 完全磁盘访问权限」中授予 Mole 访问权限。

---

## 📂 项目结构

```text
MoleUI/
├── Mole.xcodeproj         # Xcode 工程配置
├── Package.swift           # Swift Package Manager 清单
├── Sources/
│   ├── MoleApp/            # App 入口、Assets 资源与生命周期
│   └── MoleUI/
│       ├── Models/         # 数据结构定义 (Status, Disk, Clean, Uninstall, FVM...)
│       ├── Services/       # 底层服务层 (SystemMonitor, DiskScanner, TrashService...)
│       ├── ViewModels/     # 状态管理与业务逻辑
│       ├── Views/          # SwiftUI 视图组件
│       └── Support/        # 工具函数、字节格式化、日志模块
├── Tests/                  # 单元测试与基准测试
└── Scripts/                # 图标生成与 .app 打包脚本
```

---

## 🤝 参与贡献

欢迎提交 Issue 与 Pull Request！

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的修改 (`git commit -m 'feat: Add some AmazingFeature'`)
4. 推送至分支 (`git push origin feature/AmazingFeature`)
5. 新建 Pull Request

---

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 协议开源。

---

## 🙏 致谢

- 灵感与功能源自 [tw93/Mole](https://github.com/tw93/Mole) 终端工具，感谢作者的杰出创意与工作！
