// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LauncherCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LauncherCore",
            targets: ["LauncherCore"]
        )
    ],
    targets: [
        .target(
            name: "LauncherCore"
        ),
        .testTarget(
            name: "LauncherCoreTests",
            dependencies: ["LauncherCore"]
        )
    ]
)
