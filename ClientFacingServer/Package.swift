// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClientFacingServer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        .package(url: "https://github.com/apple/FHIRModels.git", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.7.2"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.8.2"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor.git", from: "1.0.1"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.0.2"),
    ],
    targets: [
        .executableTarget(
            name: "ClientFacingServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .testTarget(
            name: "ClientFacingServerTests",
            dependencies: [
                "ClientFacingServer",
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
            ]
        ),
    ]
)
