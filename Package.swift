// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusIsland",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FocusCore", targets: ["FocusCore"]), .executable(name: "FocusIsland", targets: ["FocusIsland"]), .executable(name: "FocusCoreChecks", targets: ["FocusCoreChecks"])],
    targets: [.target(name: "FocusCore"), .executableTarget(name: "FocusIsland", dependencies: ["FocusCore"]), .executableTarget(name: "FocusCoreChecks", dependencies: ["FocusCore"]), .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"])],
    swiftLanguageModes: [.v5]
)
