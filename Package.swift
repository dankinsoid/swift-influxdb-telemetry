// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-influxdb-logs-metrics",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "SwiftInfluxDBLogs", targets: ["SwiftInfluxDBLogs"]),
        .library(name: "SwiftInfluxDBMetrics", targets: ["SwiftInfluxDBMetrics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/influxdata/influxdb-client-swift.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.4.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/dankinsoid/swift-analytics.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SwiftInfluxDBLogs",
            dependencies: [
                .product(name: "InfluxDBSwift", package: "influxdb-client-swift"),
                .product(name: "Logging", package: "swift-log"),
                .target(name: "SwiftInfluxDBCore")
            ]
        ),
        .target(
            name: "SwiftInfluxDBMetrics",
            dependencies: [
                .product(name: "InfluxDBSwift", package: "influxdb-client-swift"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Atomics", package: "swift-atomics"),
                .target(name: "SwiftInfluxDBCore")
            ]
        ),
        .target(
            name: "SwiftInfluxDBAnalytics",
            dependencies: [
                .product(name: "InfluxDBSwift", package: "influxdb-client-swift"),
                .product(name: "SwiftAnalytics", package: "swift-analytics"),
                .target(name: "SwiftInfluxDBCore")
            ]
        ),
        .target(
            name: "SwiftInfluxDBCore",
            dependencies: [
            ]
        ),
    ]
)
