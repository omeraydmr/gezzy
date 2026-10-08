// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GezzyKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GezzyKit", targets: ["GezzyKit"]),
    ],
    targets: [
        .target(name: "GezzyKit", resources: [.copy("Resources/airports.tsv"), .copy("Resources/visa_rules.tsv")]),
        .testTarget(name: "GezzyKitTests", dependencies: ["GezzyKit"]),
    ]
)
