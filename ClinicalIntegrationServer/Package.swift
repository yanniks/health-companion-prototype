// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClinicalIntegrationServer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        .package(url: "https://github.com/apple/FHIRModels.git", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.7.2"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.8.2"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor.git", from: "1.0.1"),
    ],
    targets: [
        .executableTarget(
            name: "ClinicalIntegrationServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                "GDTKit",
                "FHIRToGDT",
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        .target(
            name: "GDTKit",
            dependencies: []
        ),
        .target(
            name: "FHIRToGDT",
            dependencies: [
                .product(name: "ModelsR4", package: "FHIRModels"),
                "GDTKit",
            ]
        ),
        .testTarget(
            name: "ClinicalIntegrationServerTests",
            dependencies: [
                "ClinicalIntegrationServer",
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
            ]
        ),
        .testTarget(
            name: "GDTKitTests",
            dependencies: ["GDTKit"]
        ),
        .testTarget(
            name: "FHIRToGDTTests",
            dependencies: [
                "FHIRToGDT",
                .product(name: "ModelsR4", package: "FHIRModels"),
            ]
        ),
    ]
)
