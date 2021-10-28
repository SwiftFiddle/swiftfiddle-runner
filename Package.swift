// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "swiftfiddle-runner",
    platforms: [
        .macOS(.v11)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.51.0"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.2.4"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
            ]
        ),
        .executableTarget(name: "Run", dependencies: [.target(name: "App")])
    ]
)
