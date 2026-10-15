// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ETFToGoCore", platforms: [.iOS(.v17), .macOS(.v13)], products: [.library(name: "ETFCore", targets: ["ETFCore"])], targets: [.target(name: "ETFCore", path: "ETFToGo/Core"), .testTarget(name: "ETFCoreTests", dependencies: ["ETFCore"], path: "Tests/ETFCoreTests", resources: [.copy("Fixtures")])])
