// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "IAMServer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "IAMServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "IAMServerTests",
            dependencies: [
                "IAMServer",
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ]
)
