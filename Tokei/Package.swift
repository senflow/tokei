// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tokei",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CZstd",
            path: "Sources/CZstd",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("ZSTD_DISABLE_ASM"),
            ]
        ),
        .executableTarget(
            name: "Tokei",
            dependencies: ["CZstd"],
            path: "Sources/Tokei"
        )
    ]
)
