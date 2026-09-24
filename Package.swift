// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sparekey",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "sparekey", targets: ["sparekey"])],
    targets: [
        .target(name: "SparekeyCore"),
        .executableTarget(name: "sparekey", dependencies: ["SparekeyCore"]),
        .testTarget(name: "SparekeyCoreTests", dependencies: ["SparekeyCore"])
    ]
)
