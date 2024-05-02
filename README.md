# swift-influxdb-logs-metrics

## Description
This repository provides

## Example

```swift

```
## Usage

 
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
