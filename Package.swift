// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "swiftfiddle-runner",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.52.1"),
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
