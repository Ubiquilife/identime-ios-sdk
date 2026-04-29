// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IdentiMeAuth",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "IdentiMeAuth", targets: ["IdentiMeAuth"]),
    ],
    targets: [
        .target(name: "IdentiMeAuth", path: "Sources/IdentiMeAuth"),
        .testTarget(name: "IdentiMeAuthTests", dependencies: ["IdentiMeAuth"]),
    ]
)
