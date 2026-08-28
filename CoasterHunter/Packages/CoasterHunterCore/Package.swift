// swift-tools-version:5.8
import PackageDescription

// Platform-agnostic core: model, sensor maths, ranking and entitlements.
// Deliberately free of UIKit, SwiftUI and CoreMotion so it builds and tests on
// the host toolchain without Xcode — the parts most likely to be wrong are the
// parts that can be checked fastest.

let package = Package(
    name: "CoasterHunterCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [
        .library(name: "CoasterHunterCore", targets: ["CoasterHunterCore"]),
    ],
    targets: [
        .target(name: "CoasterHunterCore"),
        .testTarget(
            name: "CoasterHunterCoreTests",
            dependencies: ["CoasterHunterCore"]
        ),
    ]
)
