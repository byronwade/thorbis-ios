// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThorbisCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "ThorbisCore", targets: ["ThorbisCore"])],
    targets: [
        .target(name: "ThorbisCore"),
        .testTarget(name: "ThorbisCoreTests", dependencies: ["ThorbisCore"], resources: [.copy("Fixtures")]),
    ]
)
