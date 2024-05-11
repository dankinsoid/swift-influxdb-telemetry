// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "swift-influxdb-telemetry",
	platforms: [
		.macOS(.v11),
		.iOS(.v14),
	],
	products: [
		.library(name: "InfluxDBLogs", targets: ["InfluxDBLogs"]),
		.library(name: "InfluxDBMetrics", targets: ["InfluxDBMetrics"]),
		.library(name: "InfluxDBAnalytics", targets: ["InfluxDBAnalytics"]),
		.library(name: "InfluxDBTracing", targets: ["InfluxDBTracing"]),
	],
	dependencies: [
		.package(url: "https://github.com/influxdata/influxdb-client-swift.git", from: "1.6.0"),
		.package(url: "https://github.com/apple/swift-metrics.git", from: "2.4.0"),
		.package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
		.package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
		.package(url: "https://github.com/dankinsoid/swift-analytics.git", from: "1.2.0"),
		.package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.0.0"),
	],
	targets: [
		.target(
			name: "InfluxDBLogs",
			dependencies: [
				.product(name: "Logging", package: "swift-log"),
				.target(name: "SwiftInfluxDBCore"),
			]
		),
		.target(
			name: "InfluxDBMetrics",
			dependencies: [
				.product(name: "Metrics", package: "swift-metrics"),
				.product(name: "Atomics", package: "swift-atomics"),
				.target(name: "SwiftInfluxDBCore"),
			]
		),
		.target(
			name: "InfluxDBAnalytics",
			dependencies: [
				.product(name: "SwiftAnalytics", package: "swift-analytics"),
				.target(name: "SwiftInfluxDBCore"),
			]
		),
		.target(
			name: "InfluxDBTracing",
			dependencies: [
				.product(name: "Tracing", package: "swift-distributed-tracing"),
				.product(name: "Instrumentation", package: "swift-distributed-tracing"),
				.target(name: "SwiftInfluxDBCore"),
			]
		),
		.target(
			name: "SwiftInfluxDBCore",
			dependencies: [
				.product(name: "InfluxDBSwift", package: "influxdb-client-swift"),
			]
		),
	]
)
