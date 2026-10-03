// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TravellerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TravellerKit", targets: ["TravellerKit"]),
    ],
    targets: [
        .target(name: "TravellerKit", resources: [.copy("Resources/airports.tsv"), .copy("Resources/visa_rules.tsv")]),
        .testTarget(name: "TravellerKitTests", dependencies: ["TravellerKit"]),
    ]
)
