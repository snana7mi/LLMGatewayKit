// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LLMGatewayKit",
    defaultLocalization: "ja",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LLMGatewayKit", targets: ["LLMGatewayKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "LLMGatewayKit",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LLMGatewayKitTests",
            dependencies: ["LLMGatewayKit"]
        ),
    ]
)
