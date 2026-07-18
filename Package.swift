// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "pmstt",
	platforms: [
		.macOS(.v15),
	],
	dependencies: [
		.package(url: "https://github.com/vapor/vapor.git", from: "4.121.0"),
		.package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
		.package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.12.0"),
		.package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
		.package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
		.package(url: "https://github.com/vapor/jwt.git", from: "5.0.0"),
		.package(url: "https://github.com/vapor/sql-kit.git", from: "3.36.0"),
		.package(url: "https://github.com/seanoshea/FuzzyMatchingSwift.git", exact: "0.11.1"),
	],
	targets: [
		.executableTarget(
			name: "pmstt",
			dependencies: [
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
				.product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
				.product(name: "Vapor", package: "vapor"),
				.product(name: "NIOCore", package: "swift-nio"),
				.product(name: "NIOPosix", package: "swift-nio"),
				.product(name: "JWT", package: "jwt"),
				.product(name: "SQLKit", package: "sql-kit"),
				.product(name: "FuzzyMatchingSwift", package: "FuzzyMatchingSwift"),
			],
			swiftSettings: swiftSettings
		),
		.testTarget(
			name: "pmsttTests",
			dependencies: [
				"pmstt",
				.product(name: "Fluent", package: "fluent"),
				.product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
				.product(name: "Vapor", package: "vapor"),
				.product(name: "XCTVapor", package: "vapor"),
			]
		),
	]
)

var swiftSettings: [SwiftSetting] {
	[
		.enableUpcomingFeature("ExistentialAny"),
	]
}
