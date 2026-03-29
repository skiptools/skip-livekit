// swift-tools-version: 5.9
// This is a Skip (https://skip.tools) package,
// containing a Swift Package Manager project
// that will use the Skip build plugin to transpile the
// Swift Package, Sources, and Tests into an
// Android Gradle Project with Kotlin sources and JUnit tests.
import PackageDescription

let package = Package(
    name: "skip-livekit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        .library(name: "SkipLiveKit", type: .dynamic, targets: ["SkipLiveKit"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.3.3"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.3.1"),
    ],
    targets: [
        .target(name: "SkipLiveKit", dependencies: [
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "LiveKit", package: "client-sdk-swift")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipLiveKitTests", dependencies: [
            "SkipLiveKit",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)

if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
    package.dependencies += [.package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0")]
    package.targets.forEach({ target in
        target.dependencies += [.product(name: "SkipFuseUI", package: "skip-fuse-ui")]
    })
    // all library types must be dynamic to support bridging
    package.products = package.products.map({ product in
        guard let libraryProduct = product as? Product.Library else { return product }
        return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
    })
}
