// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PhysicsProblems",
	platforms: [.macOS(.v26)],
	dependencies: [.package(url: "https://github.com/swiftwasm/JavaScriptKit.git", branch: "main" )],
    targets: [
		.target(name: "PhysicsEngine"),
        .executableTarget(
            name: "PhysicsProblems",
			dependencies: [
				.product(name: "JavaScriptKit", package: "JavaScriptKit"),
				.product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
				.target(name: "PhysicsEngine")
			],
			swiftSettings: [
				.enableExperimentalFeature("Extern")
			],
			plugins: [
				.plugin(name: "BridgeJS", package: "JavaScriptKit")
			]
        ),
        .testTarget(
            name: "PhysicsProblemsTests",
            dependencies: ["PhysicsEngine"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
