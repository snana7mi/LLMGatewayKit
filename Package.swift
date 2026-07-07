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
        .library(name: "LLMGatewayKitGoogleAuth", targets: ["LLMGatewayKitGoogleAuth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", from: "5.0.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "LLMGatewayKit",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LLMGatewayKitGoogleAuth",
            dependencies: [
                "LLMGatewayKit",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ]
        ),
        .testTarget(
            name: "LLMGatewayKitTests",
            dependencies: ["LLMGatewayKit"]
        ),
    ]
)
