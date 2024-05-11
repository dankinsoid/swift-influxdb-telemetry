# swift-influxdb-telemetry

This library provides Swift-based tools for integrating InfluxDB with your application for metrics, logging, analytics and tracing purposes.

## Features

- **Metrics Collection**: Efficiently collects and batches metrics data to be written to InfluxDB.
- **Logging**: Configurable logging that writes directly to InfluxDB, using metadata tags for enhanced query performance.
- **Analytics**: Sends analytics data to InfluxDB for analysis and visualization.
- **Tracing**: Supports distributed tracing for monitoring and troubleshooting.
- **Batching and Throttling**: Supports batching and throttling to optimize data writing to InfluxDB.
- **Customizable Tagging**: Allows for flexible tagging to support diverse querying needs.

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

### Setting Up Tracing

```swift
import InfluxDBTracing

InstrumentationSystem.bootstrap(
    InfluxDBTracer(
        url: "http://localhost:8086",
        token: "your-token",
        org: "your-org-name",
        bucket: "your-bucket-name",
        precision: .ms, // Optional
        batchSize: 5000, // Optional
        throttleInterval: 5, // Optional
    )
)
```

### Writing Metrics, Logs, Analytics and Traces

```swift
// Metrics
Counter(label: "page_views", dimensions: ["type": "homepage"]).increment()

// Analytics
Analytics().send("page_view", parameters: ["type": "homepage"])

// Logs
Logger(label: "app").error("Something went wrong!")

// Traces
withSpan("operation") { span in
    // Perform operation
}
```

## Installation

1. [Swift Package Manager](https://github.com/apple/swift-package-manager)

Create a `Package.swift` file.
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "SomeProject",
  dependencies: [
    .package(url: "https://github.com/dankinsoid/swift-influxdb-telemetry.git", from: "1.3.6")
  ],
  targets: [
    .target(
        name: "SomeProject",
        dependencies: [
            .product(name: "InfluxDBLogs", package: "swift-influxdb-telemetry"),
            .product(name: "InfluxDBAnalytics", package: "swift-influxdb-telemetry"),
            .product(name: "InfluxDBMetrics", package: "swift-influxdb-telemetry"),
            .product(name: "InfluxDBTracing", package: "swift-influxdb-telemetry")
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

swift-influxdb-telemetry is available under the MIT license. See the LICENSE file for more info.
