# swift-influxdb-logs-metrics

This library provides Swift-based tools for integrating InfluxDB with your application for metrics and logging purposes.
The `InfluxDBMetricsFactory` is designed for metric collection, while the `InfluxDBLogHandler` is tailored for logging, both conforming to Swift's metrics and logging standards.

## Features

- **Metrics Collection**: Efficiently collects and batches metrics data to be written to InfluxDB.
- **Logging**: Configurable logging that writes directly to InfluxDB, using metadata tags for enhanced query performance.
- **Batching and Throttling**: Supports batching and throttling to optimize data writing to InfluxDB.
- **Customizable Tagging**: Allows for flexible tagging of metrics and log data to support diverse querying needs.

## Usage

### Setting Up Metrics Factory

```swift
import InfluxDBMetrics

MetricsSystem.bootstrap(
    InfluxDBMetricsFactory(
        url: "http://localhost:8086",
        token: "your-token",
        org: "your-org-name",
        bucket: "your-bucket-name",
        precision: .ms, // Optional
        batchSize: 5000, // Optional
        throttleInterval: 5, // Optional
        dimensionsLabelsAsTags: .all // Optional
    )
)
```

### Setting Up Log Handler

```swift
import InfluxDBLogs

LoggingSystem.bootstrap { name in
    InfluxDBLogHandler(
        name: name,
        url: "http://localhost:8086",
        token: "your-token",
        org: "your-org-name",
        bucket: "your-bucket-name",
        precision: .ms, // Optional
        batchSize: 5000, // Optional
        throttleInterval: 5, // Optional
        metadataLabelsAsTags: .loggingDefault.union([.InfluxDBLogLabels.file]), // Optional
        logLevel: .info, // Optional
    )
}
```

### Setting Up Analytics

```swift
import InfluxDBAnalytics

AnalyticsSystem.bootstrap(
    InfluxDBAnalyticsHandler(
        url: "http://localhost:8086",
        token: "your-token",
        org: "your-org-name",
        bucket: "your-bucket-name",
        precision: .ms, // Optional
        batchSize: 5000, // Optional
        throttleInterval: 5, // Optional
        parametersLabelsAsTags: .analyticsDefault.union([.InfluxDBAnalyticsLabels.file]), // Optional
    )
)
```

### Writing Metrics, Logs and Analytics

```swift
// Metrics
Counter(label: "page_views", dimensions: ["type": "homepage"]).increment()

// Analytics
Analytics().send("page_view", parameters: ["type": "homepage"])

// Logs
Logger(label: "app").error("Something went wrong!")
```
## Installation

1. [Swift Package Manager](https://github.com/apple/swift-package-manager)

Create a `Package.swift` file.
```swift
// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "SomeProject",
  dependencies: [
    .package(url: "https://github.com/dankinsoid/swift-influxdb-logs-metrics.git", from: "1.2.2")
  ],
  targets: [
    .target(
        name: "SomeProject",
        dependencies: [
            .product(name: "InfluxDBLogs", package: "swift-influxdb-logs-metrics"),
            .product(name: "InfluxDBAnalytics", package: "swift-influxdb-logs-metrics"),
            .product(name: "InfluxDBMetrics", package: "swift-influxdb-logs-metrics")
       ]
    )
  ]
)
```
```ruby
$ swift build
```

## Author

dankinsoid, voidilov@gmail.com

## License

swift-influxdb-logs-metrics is available under the MIT license. See the LICENSE file for more info.
