// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "BuddyCore",
	platforms: [.macOS(.v15)],
	products: [
		.library(name: "BuddyCore", targets: ["BuddyCore"]),
	],
	targets: [
		.target(name: "BuddyCore"),
		.testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"]),
	]
)
