// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PhysicsProblems",
	platforms: [.macOS(.v26)],
	dependencies: [.package(url: "https://github.com/swiftwasm/JavaScriptKit.git", branch: "main" )],
    targets: [
        .executableTarget(
            name: "PhysicsProblems",
			dependencies: [
				.product(name: "JavaScriptKit", package: "JavaScriptKit"),
				.product(name: "JavaScriptEventLoop", package: "JavaScriptKit")
			]
        ),
        .testTarget(
            name: "PhysicsProblemsTests",
            dependencies: ["PhysicsProblems"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
