// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoleUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mole", targets: ["MoleApp"])
    ],
    targets: [
        // 全部功能代码（模型 / 服务 / 视图 / 工具），方便单元测试
        .target(
            name: "MoleUI",
            path: "Sources/MoleUI"
        ),
        // 薄薄的 app 入口（@main）
        .executableTarget(
            name: "MoleApp",
            dependencies: ["MoleUI"],
            path: "Sources/MoleApp",
            // asset catalog 由 Xcode 工程编译；SPM 构建无需（图标由 make-app.sh 嵌入）
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "MoleUITests",
            dependencies: ["MoleUI"],
            path: "Tests/MoleUITests"
        )
    ],
    // 使用 Swift 5 语言模式，避免与 AppKit/系统 C API 交互时严格的并发检查
    swiftLanguageModes: [.v5]
)
