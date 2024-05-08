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

let client = InfluxDBClient(url: "your-influxdb-url", token: "your-auth-token")

MetricsSystem.bootstrap(
    InfluxDBMetricsFactory(
        bucket: "your-bucket-name",
        org: "your-org-name",
        client: client,
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

let client = InfluxDBClient(url: "your-influxdb-url", token: "your-auth-token")
        
LoggingSystem.bootstrap { name in
    InfluxDBLogHandler(
        name: name,
        bucket: "your-bucket-name",
        org: "your-org-name",
        client: client,
        precision: .ms, // Optional
        batchSize: 5000, // Optional
        throttleInterval: 5, // Optional
        metadataLabelsAsTags: InfluxDBLogHandler.defaultMetadataLabelsAsTags.union([.InfluxDBLogHandlerLabels.file]), // Optional
        logLevel: .info, // Optional
        metadata: [:] // Optional
    )
}
```

### Writing Metrics and Logs

```swift
// Metrics
let counter = Counter(label: "page_views", dimensions: ["type": "homepage"])
counter.increment()

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
    .package(url: "https://github.com/dankinsoid/swift-influxdb-logs-metrics.git", from: "0.0.1")
  ],
  targets: [
    .target(
        name: "SomeProject",
        dependencies: [
            .product(name: "SwiftInfluxDBLogs", package: "swift-influxdb-logs-metrics"),
            .product(name: "SwiftInfluxDBMetrics", package: "swift-influxdb-logs-metrics")
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
