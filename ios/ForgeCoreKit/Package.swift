// swift-tools-version:5.9
import PackageDescription

// Wraps the Rust-built ForgeCore.xcframework (see ../../forge-core/) as a
// local Swift package the app depends on declaratively, same as any other
// SPM dependency in project.yml. Re-run forge-core/build-xcframework.sh
// after changing anything in forge-core/src, then `xcodegen generate`.
let package = Package(
    name: "ForgeCoreKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ForgeCoreKit", targets: ["ForgeCoreKit"])
    ],
    targets: [
        .binaryTarget(
            name: "forge_coreFFI",
            path: "../Vendor/ForgeCore.xcframework"
        ),
        .target(
            name: "ForgeCoreKit",
            dependencies: ["forge_coreFFI"]
        ),
    ]
)
