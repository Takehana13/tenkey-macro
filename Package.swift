// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TenkeyMacro",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TenkeyMacro",
            path: "Sources/TenkeyMacro"
        )
    ]
)
