# Mole UI —— macOS 原生版开发计划

> 目标：将 [tw93/Mole](https://github.com/tw93/Mole)（终端版 Mac 清理/优化工具）以原生 macOS 应用形式实现。
> UI 尽量贴近 macOS 原生风格，组件尽量使用原生组件。

## 一、技术选型

| 项目 | 选择 | 理由 |
|---|---|---|
| 语言 | Swift（Swift 6，可用 Swift 5 语言模式降低迁移成本） | 原生、与系统 API 契合 |
| UI 框架 | SwiftUI（App 生命周期） | 原生组件、自动适配 macOS 26 Liquid Glass 设计；必要时桥接 AppKit（NSWorkspace / IOKit / NSMenuItem） |
| 图表 | Swift Charts（原生）+ Canvas 自绘磁盘树图 | Charts 是官方原生框架；树图需自绘（类 DaisyDisk） |

> **图表方案决策（2026-08）**：本项目保持原生，不用跨平台图表库。理由：① 应用只面向 macOS，跨平台框架（Flutter/Tauri 等）与原生 Swift 互斥，无收益；② 状态监控实时曲线/仪表盘正是 Swift Charts 的舒适区，自动适配深浅色、强调色、无障碍；③ 磁盘树图是自定义可视化，跨平台库也没有现成组件，原生 Canvas/Path 自绘最顺、性能最好；④ 第三方图表库自带渲染、外观有偏差、无障碍与维护成本高。仅当目标真正多平台或图表极其复杂时才值得引入跨平台方案。
| 工程结构 | Swift Package Manager executable + 打包脚本 | 可用 `swift build` / `swift run` 在命令行直接验证；Xcode 可打开 Package.swift |
| 最低系统 | macOS 14+ | 与 Mole Homebrew 支持层级一致 |
| 权限 | 非沙盒；用户需在系统设置授予「完全磁盘访问权限」 | 扫描用户 Library / 缓存等必需 |

## 二、功能模块（对应 Mole 命令）

| Mole CLI | 应用模块 | 说明 |
|---|---|---|
| `mo status` | 状态监控 | CPU / 内存 / 磁盘 / 网络 / 电池实时图表 + 健康分 + 进程列表 |
| `mo clean` | 深度清理 | 缓存 / 日志 / 残留扫描，dry-run 预览，可勾选，移入废纸篓 |
| `mo uninstall` | 智能卸载 | 应用列表 + 关联文件（偏好 / 缓存 / 日志 / LaunchAgents / 扩展） |
| `mo optimize` | 系统优化 | 维护项列表（重建 LaunchServices、清 DNS 缓存、刷新 Finder 等） |
| `mo analyze` | 磁盘分析 | 树图可视化 + 大文件列表，可导航 / 打开 / 移入废纸篓 |
| `mo purge` | 项目产物清理 | 扫描 node_modules / target / .build / build / dist |
| `mo installer` | 安装包清理 | 扫描 .dmg / .pkg / .zip（Downloads / Desktop / Homebrew 缓存 / iCloud / Mail） |
| — | 设置 | 白名单、扫描路径、确认选项、操作日志 |

## 三、架构分层

```
MoleUI/
├── Package.swift
├── Sources/MoleUI/
│   ├── App/            # 入口、AppDelegate、菜单栏、窗口
│   ├── Models/         # 数据模型（Category / AppInfo / DiskEntry / SystemStatus / PurgeCandidate / OptimizationTask…）
│   ├── Services/       # 系统服务：
│   │                   #   SystemMonitor   —— sysctl / host_statistics / IOKit / getifaddrs
│   │                   #   DiskScanner     —— FileManager 递归扫描（异步 + 进度）
│   │                   #   CleanupEngine    —— 缓存/日志/残留扫描与清理
│   │                   #   AppCatalog       —— 应用枚举与关联文件定位
│   │                   #   Uninstaller      —— 卸载执行（移入废纸篓）
│   │                   #   OptimizationEngine—— 维护任务执行
│   │                   #   PurgeEngine / InstallerScanner —— 产物/安装包扫描
│   │                   #   TrashService     —— 安全删除（FileManager.trashItem）
│   ├── ViewModels/     # @Observable 状态（每功能一个）
│   ├── Views/          # SwiftUI 视图（导航、仪表盘、列表、树图、设置…）
│   └── Support/        # 字节格式化、路径校验、日志、权限引导
├── Tests/MoleUITests/  # 单元测试（扫描器、清理引擎、路径校验）
└── Scripts/            # make-app.sh 打包 .app、Info.plist
```

### 系统数据获取（原生 API）
- CPU / 负载：`sysctl`（`hw.ncpu`、`host_statistics64`、`vm_loadavg`）
- 内存：`host_statistics64` / `vm_statistics64`
- 磁盘：`FileManager` 卷属性 / `statfs`
- 网络：`getifaddrs` 统计增量
- 电池：IOKit `IOPSCopyPowerSourcesInfo`
- 进程：`proc_listpids` / `proc_pidinfo`（或用 `ps` 兜底）

## 四、安全设计（重要）

- 所有删除操作默认流程：**dry-run 预览 → 用户勾选 → 明确确认 → 移入废纸篓**（可撤销，不用 `rm`）
- 受保护路径列表：`/`、`/System`、`/Library`、`/Applications`（根）、用户主目录根、正在运行的 app
- 路径校验：拒绝符号链接逃逸、拒绝越界路径
- 操作日志：写入 `~/Library/Logs/Mole/operations.log`，可在设置页查看
- 高风险操作二次确认；未选中项绝不删除

## 五、开发阶段（按交付价值排序）

- **阶段 A｜工程骨架**：SPM 工程 + 应用外壳（侧边栏 NavigationSplitView、原生样式、设置页、打包脚本）→ 可运行
- **阶段 B｜状态监控**：实时仪表盘（CPU / 内存 / 磁盘 / 网络 / 电池图表 + 健康分 + 进程）
- **阶段 C｜磁盘分析**：树图可视化 + 大文件列表 + 目录导航
- **阶段 D｜深度清理**：缓存/日志/残留扫描、dry-run 预览、移入废纸篓
- **阶段 E｜智能卸载**：应用列表 + 关联文件 + 卸载
- **阶段 F｜优化 / 产物清理 / 安装包清理**：剩余三个模块
- **阶段 G｜打磨**：单元测试、权限引导、.app 打包与签名、本地化

## 阶段 B 完成情况（2026-08-17）：状态监控仪表盘

- ✅ 监控服务层（原生 API）：CPU（host_statistics / host_processor_info / sysctl / getloadavg）、内存（host_statistics64）、磁盘（卷资源属性）、网络（sysctl NET_RT_IFLIST2，64 位计数无截断）、电池（IOKit Power Sources）、进程（sysctl KERN_PROC + proc_pidinfo）
- ✅ SystemMonitor 采样器（持有上次状态算 delta）+ StatusViewModel（1.5s 定时采样、60 点历史、暂停/继续）
- ✅ DashboardView：健康分环形仪表 + CPU（每核柱 + 折线）/ 内存（折线）/ 磁盘（Gauge）/ 网络（上下行双折线）/ 电池（Gauge）+ 进程表（Swift Charts + 原生 Table）
- ✅ 健康分：归一化压力加权（CPU 50% / 内存 30% / 磁盘 20%），满载=0
- ✅ 测试：14 个通过（纯函数 + 真实硬件采样冒烟测试）
- 已知问题：SwiftUI 窗口内容走 CARenderServer，离线截图（PDF/layer/cacheDisplay）均无法捕获，视觉验证需人工查看；NSTableView 重入警告通过「进程列表低频发布（6s）+ 首帧后发布」消除

## 阶段 C 完成情况（2026-08-17）：磁盘分析

- ✅ `DiskScanner`：递归扫描（跳过符号链接、进度回调、`Task.isCancelled` 取消、错误计数、≥5MB 大文件 Top100 收集）；主目录 305,711 文件 18s 扫描验证通过
- ✅ `TreemapLayout`：Squarified 方形树图算法（Bruls 2000），纯函数可测试（无重叠/填满容器/面积正比）
- ✅ `AnalyzeView`：Canvas 树图（按文件类型着色、悬停高亮 + 信息浮层、点击进入目录）+ 大文件 Table（可多选）+ 面包屑导航 + 工具栏（位置菜单/上一级/重新扫描）+ HSplitView 布局
- ✅ `TrashService`：受保护路径（/、/System、/Library、/Applications、主目录根）拒绝删除，默认移入废纸篓可恢复，删除前二次确认
- ✅ 测试：21 个全部通过（新增树图布局/扫描器临时目录/分类/受保护路径）

## 阶段 D 完成情况（2026-08-17）：深度清理

- ✅ 7 个分类（对应 `mo clean`）：用户应用缓存 / 浏览器缓存 / 日志 / 开发者工具缓存 / 卸载残留 / 废纸篓 / 临时文件，复用 DiskScanner 扫描
- ✅ 安全设计：危险分类（废纸篓永久删除、临时文件/残留）默认不勾选；普通清理移入废纸篓可恢复；删除前二次确认；受保护路径拒绝；`isPermanent` 标记
- ✅ 卸载残留检测：应用名 + Bundle ID + 显示名 + PATH 命令行工具四层覆盖，前缀匹配 ≥4 字符防误伤（如 `go` 不覆盖 `google`）；真实机器验证从 12.5GB 误报降到 4.8GB 合理候选
- ✅ 真实系统验证：缓存 6.4GB + 日志 0.2GB + 开发缓存 72GB + 残留 4.8GB + 临时 2.8GB
- ✅ 测试：38 个全部通过（含并行工作的 11 个卸载测试）；`swift build` / `xcodebuild` 零警告
- 协作修复：并行代理开发的智能卸载代码有 3 处编译错误（`NSRunningApplication.url` 在该 SDK 已移除→改用 `bundleURL`；元组 key path 不支持→改 enumerated；`private(set)` 绑定→自定义 Binding），已修复并入主构建

## 阶段 F 完成情况（2026-08-17）：项目产物清理 + 安装包清理

- ✅ `PurgeEngine`：扫描配置目录中的构建产物，找到产物目录后不再深入（避免重复统计），7 天内修改过的标记为「近期活跃」（默认不勾选防误删活跃项目）；默认扫描目录 Projects / GitHub / dev / Developer / Documents/Projects，UI 可增删扫描目录
- ✅ 产物类型（15 种，覆盖 Android/iOS/Flutter）：node_modules / build / dist / .build / Pods / xcuserdata / target / venv / .dart_tool / ephemeral（Flutter 平台）/ .gradle / .cxx / .kotlin / .externalNativeBuild / captures
- ✅ 关键修复：扫描不再跳过隐藏目录（.build/.dart_tool/.gradle/.cxx/.kotlin 全是隐藏目录，之前真实引擎扫不到），遍历时仅跳过 .git/.svn/.hg；`DiskScanner.Options` 新增 `skipHiddenFiles`（默认 true，仅清理引擎关闭，磁盘分析等行为不变）；projectName 改为递归传递（不用字符串偏移，规避 /var → /private/var 符号链接前缀差异），嵌套产物（如 android/app/.cxx）正确归到项目根
- ✅ 真实系统验证：Desktop/Documents/Downloads 扫描 227 个产物（build 21.8GB / target 9.8GB / .dart_tool 2.6GB / .build 0.9GB / node_modules 0.8GB / .gradle 0.2GB 等），Android/Flutter 各类型全部命中
- ✅ 默认扫描范围扩展：新增 `isProjectRoot` 项目标记检测（*.xcodeproj / *.xcworkspace / package.json / pubspec.yaml / Package.swift 等，含一层子目录），桌面/文稿/下载等散落地存在项目标记才纳入默认扫描；页面内新增常驻「扫描」按钮（不再只靠工具栏图标），空态区分「尚未配置扫描目录」（提供添加入口）与「未发现构建产物」（提供重新扫描）
- ✅ 项目根收敛：扫描时逐层自判定，遇到项目根（直接含清单/工程文件，或一层子目录含标记）即把 projectName 收敛到该层；平台子目录（android/ios/macos/windows/linux/web）即使含 build.gradle/Podfile 等标记也不收敛，归到外层项目；真实验证：Project/FTVision/flutter_module/.dart_tool → flutter_module、CNFT_Android/android/app/build → app、second-brain/gui/src-tauri/target → src-tauri（此前全部归到 Project）
- ✅ 类型化项目清理（重构）：`ProjectType` 按顶层清单文件识别项目类型（Flutter=pubspec.yaml / Rust=Cargo.toml / SwiftPM=Package.swift / Node=package.json / Gradle=build.gradle / Xcode=*.xcodeproj / Python / CocoaPods=Podfile，未识别回退 unknown）；每个类型有独立产物清单（Flutter 只认 .dart_tool/build/ephemeral/Pods 等，不再误收 node_modules）与官方清理命令（flutter clean / cargo clean / swift package clean / ./gradlew clean）；`PurgeCandidate` 改为项目级（项目根+类型+产物明细），清理时优先运行官方命令、无命令类型对产物目录移入废纸篓；walk 跳过产物目录内部（node_modules 子包不再被误识别为项目）；真实验证：96 个项目按类型归组（Flutter 22 个 8.6GB / SwiftPM 23 个 0.9GB / Node 5 个 0.5GB…）
- ✅ 扫描缓存 + 手动触发：Purge / Clean / Installer / DiskAnalysis / Uninstall 五个模块的 ViewModel 改为共享单例（static shared），扫描结果、选择集、导航位置跨页面切换缓存，切走再切回不重复扫描；移除各视图 `.task` 自动扫描——点击侧边栏菜单不再立即触发磁盘扫描/权限弹窗，页面空态提供「开始扫描 / 加载应用」按钮，用户手动点击才执行；Dashboard 实时监控保留自动采样
- ✅ 权限触发时机修复：`PurgeEngine.defaultRoots` 改为只含惯例目录（Projects/GitHub/dev 等，访问无需权限）；桌面/文稿/下载的探测拆为 `detectProjectRoots()`，仅在用户点击「扫描」时执行并合并进扫描目录——页面加载/ViewModel 初始化不再触碰 TCC 保护目录（新增回归测试：defaultRoots 绝不含 /Desktop /Documents /Downloads）
- ✅ `PurgeView`：扫描目录胶囊条（可增删，NSOpenPanel 选目录）+ 按类型分组列表（类型汇总 + 全选）+ 每项显示项目名/路径/文件数/大小/近期标记 + 汇总栏 + 二次确认 + 移入废纸篓
- ✅ `InstallerEngine`：扫描 下载 / 桌面 / 文稿 / Homebrew 缓存 / iCloud 云盘（Downloads+Desktop+Documents）/ 邮件下载 六类来源，识别 .dmg / .pkg / .mpkg / .zip / .tgz / .iso 及 .tar.gz 复合后缀，默认不按大小过滤（全部列出由用户勾选），递归 3 层，按大小降序；同一文件被父子目录重复覆盖时按标准化路径去重；真实验证从 1 个包 → 7 个（小 dmg、tar.gz 源码包等全部命中）
- ✅ `InstallersView`：原生 Table（名称/大小/来源/路径，图标区分文件类型，多选）+ 汇总栏 + 二次确认 + 移入废纸篓
- ✅ 真实系统验证：产物扫描找到 80 个（build 18.7GB / target 9.8GB / .build 0.9GB / node_modules 0.7GB 等，共 ~31GB）；安装包扫描找到 ChatGPT.dmg 638.7MB
- ✅ 测试：48 个全部通过（新增类型匹配/临时目录扫描/近期标记/符号链接跳过/受保护路径 10 个）；`swift build` / `xcodebuild` 零警告
- 遗留：阶段 F 的「系统优化（mo optimize）」模块（维护任务列表）尚未实现，仍为占位页

## 五.5、阶段 A 完成情况（2026-08-17）

- ✅ SPM 工程：库目标 `MoleUI` + 可执行目标 `MoleApp` + 测试目标 `MoleUITests`（Swift 5 语言模式，macOS 14+）
- ✅ 应用外壳：`NavigationSplitView` 侧边栏（概览/清理/工具 三组）+ 7 个功能占位页 + 设置窗口（⌘,，原生 Form + TabView）
- ✅ 入口：`@main App` + AppDelegate（支持 `swift run` 直接运行）
- ✅ 工具与测试：`ByteFormatter`（原生 ByteCountFormatter）+ 4 个单元测试
- ✅ 验证：`swift build`（debug/release）、`swift test`（4/4 通过）、应用启动冒烟测试、`Scripts/make-app.sh` 生成 Mole.app
- ✅ 应用图标：`Sources/MoleApp/Assets.xcassets`（AppIcon 全尺寸 + AccentColor 强调色）；`Scripts/generate_icon.swift` 从 `Support/AppIconSource.png` 源图生成带圆角遮罩的 16~1024 各尺寸图标；Xcode 构建产出 `AppIcon.icns` 零警告，`make-app.sh` 同步嵌入
- ✅ Xcode 工程：新增 `Mole.xcodeproj`（Xcode 16+ 同步文件夹格式，双击即可运行）+ 共享 scheme + `Support/Info.plist`；`xcodebuild build` 验证通过（ad-hoc 签名本地运行）。`MoleApp.swift` 用 `#if canImport(MoleUI)` 兼容两种构建方式（SPM 库/可执行分离 vs Xcode 单 target）

> 注意：ByteCountFormatter 输出随 locale/系统版本变化（如 0 → "0 KB"/"Zero KB"、1 GiB → "1 GB"/"1.07 GB"），测试断言避免依赖精确字符串。

## 阶段 E 完成情况（2026-08-17）：智能卸载

- ✅ `AppCatalog`：枚举 /Applications 与 ~/Applications 的已安装应用（跳过 /System/Applications 系统应用），读取 Bundle ID / 版本 / 显示名，用 DiskScanner 递归统计应用包大小，按名称排序、相同 Bundle ID 去重，支持进度回调与取消
- ✅ 关联文件定位：按 Bundle ID / 显示名 / 文件名多候选匹配偏好设置（含 ByHost 前缀）、缓存、应用支持文件、日志、沙盒容器、共享容器（group.* 前缀）、开机启动项（含守护进程前缀如 com.google.keystone）、保存的窗口状态、HTTP 存储、WebKit 数据、Cookie，符号链接一律跳过
- ✅ `Uninstaller`：先移应用本体（失败则中止不碰关联文件）、再移关联文件，全部移入废纸篓可恢复，跳过受保护路径
- ✅ `UninstallViewModel`：后台清单扫描（进度）、选中应用后后台定位关联文件、默认全选、按类别勾选、运行中应用禁止卸载（NSWorkspace 检测）、卸载后从列表移除
- ✅ `UninstallView`：HSplitView 双栏（搜索 + 应用列表 / 详情），详情含图标、版本、大小、路径、「在 Finder 中显示」、关联文件分组列表（逐项勾选 + 分类全选）、汇总栏与二次确认弹窗
- ✅ 安全加固：`TrashService.isProtected` 从「精确路径」扩展为「系统目录含子路径均受保护」（/System、/Library、/Applications、/Volumes），主目录下用户文件仍可清理
- ✅ 测试：新增 11 个（应用枚举/去重/无标识应用、关联文件定位含前缀匹配与干扰项、候选名、受保护路径、卸载执行），全套 38 个通过
- 已知问题：Swift 6.3 编译器中 `Collection.contains {}` 尾随闭包会优先解析到 Regex 的泛型 contains，需显式写 `contains(where:)`（本阶段已规避，后续代码注意）

## 阶段 F（系统优化）完成情况（2026-08-17）

- ✅ `OptimizationEngine`：8 个内置维护任务，命令一律直接执行（不经 shell，可执行文件与参数固定白名单，无注入面）；先读管道再等退出，避免大输出死锁
- ✅ 任务清单（对应 `mo optimize`）：重建 LaunchServices（lsregister）、刷新 Finder、刷新 Dock、重建 Spotlight 索引（mdutil，需管理员）、清理 DNS 缓存（dscacheutil）、重置 mDNS 响应器（需管理员）、清理用户诊断报告（移入废纸篓）、清理系统诊断报告（需管理员）
- ✅ 权限分级：需管理员权限的任务在普通权限下直接跳过（不执行、不报错），UI 标注「需管理员权限」；「全部运行」仅执行非管理员任务
- ✅ 安全：目录清理（诊断报告）移入废纸篓可恢复，受保护路径（/Library 及其子路径）拒绝执行
- ✅ `OptimizeViewModel`：单任务执行与「全部运行」串行化（MainActor 顺序 await）、运行中禁止并发、重置状态
- ✅ `OptimizeView`：分组任务列表（系统维护 / 网络 / 缓存与日志）+ 状态徽标（运行中/成功/失败/跳过，失败显示输出片段）+ 汇总栏（成功/失败/跳过计数 + 全部运行按钮）
- ✅ 测试：新增 9 个（任务元数据、分组覆盖、root 任务跳过、echo 成功、false 失败、缺失可执行文件、目录清理成功/受保护跳过/缺失目录），全套 58 个通过
- 说明：真正执行 `killall`/`mdutil` 等系统命令不做自动化测试（避免影响真实系统），仅用无害命令（echo/false）验证引擎；`sudo mo optimize` 场景由用户自行在终端执行

## 操作日志完成情况（2026-08-17）

- ✅ `OperationLog`（Support/OperationLog.swift）：所有删除/清理操作写入 `~/Library/Logs/Mole/operations.log`，串行队列同步读写保证线程安全；尊重设置「记录操作历史日志」（keepHistoryLog，默认开启）；超过 2000 行自动从头部截断；`read(limit:)` 供设置页展示（默认最近 500 行）
- ✅ 覆盖全部删除路径：深度清理（CleanEngine，含废纸篓类别永久删除）、智能卸载（Uninstaller，应用本体 + 关联文件）、项目产物清理（PurgeEngine）、安装包清理（InstallerEngine）、磁盘分析移入废纸篓（TrashService.moveToTrash）、系统优化诊断清理（OptimizationEngine），每项记录路径与大小，并附完成汇总行，格式 `2026-08-17 16:59:23  [clean] 移入废纸篓：…`
- ✅ 设置页新增「操作日志」页：等宽字体查看最近 500 行（可选中复制）、刷新按钮、「在 Finder 中显示」定位日志文件；窗口尺寸调整为 520×400
- ✅ 测试：新增 6 个（追加/读取、limit、截断、设置开关关闭时跳过写入、缺失文件、CleanEngine 永久删除接入验证）；引擎类测试（Uninstall/Optimize）重定向日志文件到临时目录避免污染真实日志；全套 69 个通过
- 协作说明：另一并行代理同步完成了 PurgeEngine/ArtifactType 的扩展（新增 Flutter/Android/Kotlin 等 8 类产物与 `skipHiddenFiles` 扫描选项），与本阶段操作日志改动无冲突，最终合并构建 69 测试全绿

## 六、验证方式

- `swift build` / `swift run` 本地运行验证
- `swift test` 覆盖扫描器与清理引擎（用临时目录构造假数据，不碰真实系统文件）
- 可选：`Scripts/make-app.sh` 生成 Mole.app 并签名
